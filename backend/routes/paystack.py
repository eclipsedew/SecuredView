"""Paystack payment integration routes."""
import os
import re
import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Subscription, PREMIUM_PLANS, PAYSTACK_CURRENCY, USD_TO_GHS
from auth import get_current_account
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime, timedelta, timezone
import secrets
from limiter import limiter

router = APIRouter(prefix="/api/paystack", tags=["paystack"])

PAYSTACK_SECRET_KEY = os.getenv("PAYSTACK_SECRET_KEY", "")
PAYSTACK_BASE_URL = "https://api.paystack.co"


def _now_utc():
    return datetime.now(timezone.utc)


def _ensure_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


class InitializeRequest(BaseModel):
    plan_id: str
    email: str = Field(..., max_length=254)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v):
        v = v.strip().lower()
        if not re.fullmatch(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", v):
            raise ValueError("Invalid email format")
        return v


class InitializeResponse(BaseModel):
    authorization_url: str
    reference: str
    access_code: str


class VerifyResponse(BaseModel):
    success: bool
    message: str
    reference: str
    plan_id: str
    expires_at: Optional[datetime] = None


@router.post("/initialize", response_model=InitializeResponse)
@limiter.limit("10/hour")
def initialize_payment(
    request: Request,
    req: InitializeRequest,
    account: Account = Depends(get_current_account),
):
    """Initialize a Paystack transaction and return the authorization URL."""
    plan = PREMIUM_PLANS.get(req.plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Invalid plan selected")

    if not PAYSTACK_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Payment gateway not configured")

    # Convert USD to GHS for Paystack (merchant account is Ghanaian)
    amount_ghs = plan["price"] * USD_TO_GHS
    amount_pesewas = int(amount_ghs * 100)
    reference = f"SV-{secrets.token_hex(8).upper()}"

    with httpx.Client(timeout=10.0) as client:
        resp = client.post(
            f"{PAYSTACK_BASE_URL}/transaction/initialize",
            headers={
                "Authorization": f"Bearer {PAYSTACK_SECRET_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "email": req.email,
                "amount": amount_pesewas,
                "reference": reference,
                "currency": PAYSTACK_CURRENCY,
                "metadata": {
                    "account_id": account.id,
                    "plan_id": req.plan_id,
                    "amount_usd": plan["price"],
                    "plan_name": plan["name"],
                },
            },
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


@router.post("/verify", response_model=VerifyResponse)
@limiter.limit("20/hour")
def verify_payment(
    request: Request,
    req: VerifyRequest,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """Verify a Paystack transaction and activate premium if successful."""
    plan = PREMIUM_PLANS.get(req.plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Invalid plan selected")

    if not PAYSTACK_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Payment gateway not configured")

    with httpx.Client(timeout=10.0) as client:
        resp = client.get(
            f"{PAYSTACK_BASE_URL}/transaction/verify/{req.reference}",
            headers={
                "Authorization": f"Bearer {PAYSTACK_SECRET_KEY}",
                "Content-Type": "application/json",
            },
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

    # Check transaction was successful
    if tx_data.get("status") != "success":
        return VerifyResponse(
            success=False,
            message=f"Payment status: {tx_data.get('status', 'unknown')}",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    # Check amount matches (in pesewas, converted from USD)
    expected_amount = int(plan["price"] * USD_TO_GHS * 100)
    if tx_data.get("amount") != expected_amount:
        return VerifyResponse(
            success=False,
            message="Amount mismatch",
            reference=req.reference,
            plan_id=req.plan_id,
        )

    # Check for duplicate — don't activate twice
    existing = db.query(Subscription).filter(
        Subscription.payment_ref == req.reference
    ).first()
    if existing:
        return VerifyResponse(
            success=True,
            message="Plan already activated",
            reference=req.reference,
            plan_id=req.plan_id,
            expires_at=existing.expires_at,
        )

    # Activate premium — use select_for_update style via immediate insert with unique check
    now = _now_utc()
    expires = now + timedelta(days=plan["days"])

    current_exp = _ensure_utc(account.premium_expires_at)
    if account.is_premium and current_exp and current_exp > now:
        new_expiry = current_exp + timedelta(days=plan["days"])
        max_expiry = now + timedelta(days=365)
        expires = min(new_expiry, max_expiry)

    sub = Subscription(
        account_id=account.id,
        plan=req.plan_id,
        days=plan["days"],
        amount_usd=plan["price"],
        status="active",
        expires_at=expires,
        payment_ref=req.reference,
    )
    db.add(sub)
    try:
        db.flush()  # Flush to trigger unique constraint check if any
    except Exception:
        db.rollback()
        existing = db.query(Subscription).filter(
            Subscription.payment_ref == req.reference
        ).first()
        if existing:
            return VerifyResponse(
                success=True,
                message="Plan already activated",
                reference=req.reference,
                plan_id=req.plan_id,
                expires_at=existing.expires_at,
            )
        raise

    account.is_premium = True
    account.premium_expires_at = expires
    db.commit()
    db.refresh(sub)

    return VerifyResponse(
        success=True,
        message=f"Plan activated for {plan['days']} days",
        reference=req.reference,
        plan_id=req.plan_id,
        expires_at=expires,
    )
