"""Paystack payment integration — one-time plan purchase (hosted checkout).

No card-on-file, no auto-charge. User opens Paystack's page only when they
choose to subscribe; we never receive or store card numbers.
"""
import os
import re
import json
import httpx
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
from models import (
    Account, Subscription, PREMIUM_PLANS, PAYSTACK_CURRENCY, USD_TO_GHS,
)
from auth import get_current_account
from billing import ensure_utc
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime, timedelta, timezone
import secrets
from limiter import limiter

router = APIRouter(prefix="/api/paystack", tags=["paystack"])

PAYSTACK_SECRET_KEY = os.getenv("PAYSTACK_SECRET_KEY", "")
PAYSTACK_BASE_URL = "https://api.paystack.co"

# Local plan id → Paystack PLN_ code (created once on live dashboard)
_PLANS_FILE = Path(__file__).resolve().parent.parent / ".paystack_plans.json"
try:
    PAYSTACK_PLAN_CODES = json.loads(_PLANS_FILE.read_text()) if _PLANS_FILE.exists() else {}
except Exception:
    PAYSTACK_PLAN_CODES = {}


def _now_utc():
    return datetime.now(timezone.utc)


def _ensure_utc(dt):
    return ensure_utc(dt)


def _ps_headers():
    return {
        "Authorization": f"Bearer {PAYSTACK_SECRET_KEY}",
        "Content-Type": "application/json",
    }


class InitializeRequest(BaseModel):
    plan_id: str
    email: str = Field(..., max_length=254)
    # One-time checkout only — Paystack hosted page collects the card.
    mode: str = "subscribe"
    callback_url: Optional[str] = Field(default=None, max_length=512)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v):
        v = v.strip().lower()
        if not re.fullmatch(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", v):
            raise ValueError("Invalid email format")
        return v

    @field_validator("mode")
    @classmethod
    def validate_mode(cls, v):
        if v != "subscribe":
            raise ValueError("mode must be 'subscribe' (no card-on-file)")
        return v

    @field_validator("callback_url")
    @classmethod
    def validate_callback(cls, v):
        if v is None:
            return v
        v = v.strip()
        if not v:
            return None
        if not re.fullmatch(r"https://.+", v):
            raise ValueError("callback_url must be https://")
        return v


class InitializeResponse(BaseModel):
    authorization_url: str
    reference: str
    access_code: str
    mode: str = "subscribe"


class VerifyResponse(BaseModel):
    success: bool
    message: str
    reference: str
    plan_id: str
    expires_at: Optional[datetime] = None
    billing_ready: bool = False


def _plan_or_400(plan_id: str) -> dict:
    plan = PREMIUM_PLANS.get(plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Invalid plan selected")
    return plan


@router.post("/initialize", response_model=InitializeResponse)
@limiter.limit("20/hour")
def initialize_payment(
    request: Request,
    req: InitializeRequest,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """Initialize Paystack checkout (one-time plan payment, hosted page).

    We never touch card details — Paystack collects them on their domain.
    """
    plan = _plan_or_400(req.plan_id)
    if not PAYSTACK_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Payment gateway not configured")

    # Persist plan + receipt email on the payment intent only
    account.billing_plan_id = req.plan_id
    account.email = req.email
    db.commit()

    reference = f"SV-{secrets.token_hex(8).upper()}"
    amount_pesewas = int(plan["price"] * USD_TO_GHS * 100)
    metadata = {
        "account_id": account.id,
        "plan_id": req.plan_id,
        "mode": "subscribe",
        "amount_usd": plan["price"],
        "plan_name": plan["name"],
    }

    payload = {
        "email": req.email,
        "amount": amount_pesewas,
        "reference": reference,
        "currency": PAYSTACK_CURRENCY,
        "metadata": metadata,
        "plan": PAYSTACK_PLAN_CODES.get(req.plan_id),
    }
    if not payload["plan"]:
        payload.pop("plan")
    if req.callback_url:
        payload["callback_url"] = req.callback_url

    with httpx.Client(timeout=10.0) as client:
        resp = client.post(
            f"{PAYSTACK_BASE_URL}/transaction/initialize",
            headers=_ps_headers(),
            json=payload,
        )

    data = resp.json()
    if not data.get("status"):
        raise HTTPException(
            status_code=402,
            detail=data.get("message", "Payment initialization failed"),
        )

    result = data["data"]
    return InitializeResponse(
        authorization_url=result["authorization_url"],
        reference=result["reference"],
        access_code=result["access_code"],
        mode="subscribe",
    )


class VerifyRequest(BaseModel):
    reference: str = Field(..., max_length=64)
    plan_id: str

    @field_validator("reference")
    @classmethod
    def validate_reference(cls, v):
        if not re.fullmatch(r"SV-[A-F0-9]{16}", v):
            raise ValueError("Invalid payment reference format")
        return v


def _activate_plan_period(
    db: Session,
    account: Account,
    plan_id: str,
    payment_ref: str,
    plan_days: Optional[int] = None,
) -> datetime:
    """Start (or stack) a paid period. Never auto-renews — user pays again later."""
    plan = PREMIUM_PLANS[plan_id]
    days = plan_days or plan["days"]
    now = _now_utc()
    expires = now + timedelta(days=days)

    current_exp = _ensure_utc(account.premium_expires_at)
    if account.is_premium and current_exp and current_exp > now:
        # Stack on remaining paid/trial time so user doesn't lose days
        expires = current_exp + timedelta(days=days)
        max_expiry = now + timedelta(days=365)
        expires = min(expires, max_expiry)

    sub = Subscription(
        account_id=account.id,
        plan=plan_id,
        days=days,
        amount_usd=plan["price"],
        status="active",
        expires_at=expires,
        payment_ref=payment_ref,
    )
    db.add(sub)
    try:
        db.flush()
    except Exception:
        db.rollback()
        existing = db.query(Subscription).filter(Subscription.payment_ref == payment_ref).first()
        if existing:
            return _ensure_utc(existing.expires_at)
        raise

    account.is_premium = True
    account.is_trial = False
    account.premium_expires_at = expires
    # No auto-bill clock — manual subscribe only
    account.next_autobill_at = None
    account.billing_ready = False
    return expires


@router.post("/verify", response_model=VerifyResponse)
@limiter.limit("40/hour")
def verify_payment(
    request: Request,
    req: VerifyRequest,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """Verify Paystack transaction; activate the purchased plan period."""
    plan = _plan_or_400(req.plan_id)
    if not PAYSTACK_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Payment gateway not configured")

    with httpx.Client(timeout=10.0) as client:
        resp = client.get(
            f"{PAYSTACK_BASE_URL}/transaction/verify/{req.reference}",
            headers=_ps_headers(),
        )

    data = resp.json()
    if not data.get("status"):
        return VerifyResponse(
            success=False,
            message=data.get("message", "Verification failed"),
            reference=req.reference,
            plan_id=req.plan_id,
        )

    tx_data = data["data"]
    meta = tx_data.get("metadata") or {}
    mode = meta.get("mode", "subscribe")
    customer = tx_data.get("customer") or {}

    if tx_data.get("status") != "success":
        return VerifyResponse(
            success=False,
            message=f"Payment status: {tx_data.get('status', 'unknown')}",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    # Bind transaction to THIS account — stolen/leaked reference cannot
    # activate a plan on a different JWT.
    tx_account = str(meta.get("account_id") or "").upper()
    if not tx_account or tx_account != account.id:
        return VerifyResponse(
            success=False,
            message="Payment reference does not belong to this account",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    # Plan must match what was initialized (not a client-chosen upsell)
    tx_plan = meta.get("plan_id")
    if tx_plan and tx_plan != req.plan_id:
        return VerifyResponse(
            success=False,
            message="Plan mismatch for this payment",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    # Receipt email only (set by Paystack checkout) — optional on account
    if customer.get("email"):
        account.email = customer["email"]
    account.billing_plan_id = req.plan_id
    # Explicitly never store card auth for auto-charge
    account.paystack_authorization_code = None
    account.paystack_authorization_reusable = False
    account.billing_ready = False
    account.next_autobill_at = None

    expected_amount = int(plan["price"] * USD_TO_GHS * 100)
    if tx_data.get("amount") != expected_amount:
        db.rollback()
        return VerifyResponse(
            success=False,
            message="Amount mismatch",
            reference=req.reference,
            plan_id=req.plan_id,
        )
    if tx_data.get("currency") and tx_data.get("currency") != PAYSTACK_CURRENCY:
        db.rollback()
        return VerifyResponse(
            success=False,
            message="Currency mismatch",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    existing = db.query(Subscription).filter(
        Subscription.payment_ref == req.reference
    ).first()
    if existing:
        db.commit()
        return VerifyResponse(
            success=True,
            message="Plan already activated",
            reference=req.reference,
            plan_id=req.plan_id,
            expires_at=_ensure_utc(existing.expires_at),
            billing_ready=False,
        )

    expires = _activate_plan_period(db, account, req.plan_id, req.reference)
    db.commit()

    return VerifyResponse(
        success=True,
        message=f"Plan activated for {plan['days']} days",
        reference=req.reference,
        plan_id=req.plan_id,
        expires_at=expires,
        billing_ready=False,
    )


@router.post("/cancel")
@limiter.limit("10/hour")
def cancel_subscription(
    request: Request,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """No-op / clear any legacy Paystack sub code. Periods are one-time."""
    if account.paystack_subscription_code and PAYSTACK_SECRET_KEY:
        with httpx.Client(timeout=10.0) as client:
            code = account.paystack_subscription_code
            resp = client.get(
                f"{PAYSTACK_BASE_URL}/subscription/{code}",
                headers=_ps_headers(),
            )
            data = resp.json()
            email_token = (data.get("data") or {}).get("email_token") if data.get("status") else None
            if email_token:
                client.post(
                    f"{PAYSTACK_BASE_URL}/subscription/disable",
                    headers=_ps_headers(),
                    json={"code": code, "token": email_token},
                )
    account.paystack_subscription_code = None
    account.billing_ready = False
    account.next_autobill_at = None
    db.commit()
    return {"message": "Auto-renew disabled. Access continues until expiry."}
