"""Paystack payment integration routes."""
import os
import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Subscription, PREMIUM_PLANS
from auth import get_current_account
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timedelta, timezone
import secrets

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
    email: str


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
async def initialize_payment(
    req: InitializeRequest,
    account: Account = Depends(get_current_account),
):
    """Initialize a Paystack transaction and return the authorization URL."""
    plan = PREMIUM_PLANS.get(req.plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Invalid plan selected")

    if not PAYSTACK_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Payment gateway not configured")

    # Amount in kobo (Paystack uses the smallest currency unit)
    # USD amounts: convert to cents
    amount_kobo = int(plan["price"] * 100)
    reference = f"SV-{secrets.token_hex(8).upper()}"

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{PAYSTACK_BASE_URL}/transaction/initialize",
            headers={
                "Authorization": f"Bearer {PAYSTACK_SECRET_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "email": req.email,
                "amount": amount_kobo,
                "reference": reference,
                "currency": "USD",
                "plan": req.plan_id,
                "metadata": {
                    "account_id": account.id,
                    "plan_id": req.plan_id,
                    "custom_fields": [
                        {
                            "display_name": "Account ID",
                            "variable_name": "account_id",
                            "value": account.id,
                        }
                    ],
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
    reference: str
    plan_id: str


@router.post("/verify", response_model=VerifyResponse)
async def verify_payment(
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

    async with httpx.AsyncClient() as client:
        resp = await client.get(
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

    # Check amount matches
    expected_amount = int(plan["price"] * 100)
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

    # Activate premium
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
