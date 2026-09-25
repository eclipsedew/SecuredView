"""Paystack webhooks — successful one-time plan payments only.

No auto-renew, no charge.failed auto-stop (nothing auto-charges).
Signature verified with HMAC-SHA512 of the raw body using PAYSTACK_SECRET_KEY.
"""
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from database import get_db
from models import Account, Subscription, PREMIUM_PLANS
from billing import ensure_utc, now_utc

router = APIRouter(prefix="/api/webhooks", tags=["webhooks"])

PAYSTACK_SECRET_KEY = os.getenv("PAYSTACK_SECRET_KEY", "")


def _verify_signature(raw: bytes, signature: str | None) -> None:
    env = os.getenv("ENVIRONMENT", "production")
    if not PAYSTACK_SECRET_KEY:
        # Fail closed in production — unsigned webhooks are forgeable.
        # Local/dev only may skip when secret is intentionally unset.
        if env == "development":
            return
        raise HTTPException(status_code=503, detail="Webhook secret not configured")
    if not signature:
        raise HTTPException(status_code=401, detail="Missing x-paystack-signature")
    expected = hmac.new(
        PAYSTACK_SECRET_KEY.encode(), raw, hashlib.sha512
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")


def _find_account(db: Session, data: dict[str, Any]) -> Account | None:
    meta = data.get("metadata") or {}
    account_id = meta.get("account_id")
    if account_id:
        acc = db.query(Account).filter(Account.id == str(account_id).upper()).first()
        if acc:
            return acc
    customer = data.get("customer") or {}
    code = customer.get("customer_code")
    if code:
        return db.query(Account).filter(Account.paystack_customer_code == code).first()
    ref = data.get("reference")
    if ref:
        sub = db.query(Subscription).filter(Subscription.payment_ref == ref).first()
        if sub:
            return db.query(Account).filter(Account.id == sub.account_id).first()
    return None


def _activate_from_plan(db: Session, account: Account, plan_id: str, ref: str) -> None:
    plan = PREMIUM_PLANS.get(plan_id)
    if not plan:
        return
    if db.query(Subscription).filter(Subscription.payment_ref == ref).first():
        return
    now = now_utc()
    expires = now + timedelta(days=plan["days"])
    current = ensure_utc(account.premium_expires_at)
    if account.is_premium and current and current > now:
        expires = min(current + timedelta(days=plan["days"]), now + timedelta(days=365))
    db.add(Subscription(
        account_id=account.id,
        plan=plan_id,
        days=plan["days"],
        amount_usd=plan["price"],
        status="active",
        expires_at=expires,
        payment_ref=ref,
    ))
    account.is_premium = True
    account.is_trial = False
    account.account_type = "premium"
    account.premium_expires_at = expires
    account.next_autobill_at = None
    account.billing_ready = False


@router.post("/paystack")
async def paystack_webhook(request: Request, db: Session = Depends(get_db)):
    raw = await request.body()
    _verify_signature(raw, request.headers.get("x-paystack-signature"))

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    event = body.get("event") or ""
    data = body.get("data") or {}

    if event == "charge.success":
        ref = data.get("reference") or ""
        account = _find_account(db, data)
        if account and ref:
            meta = data.get("metadata") or {}
            plan_id = meta.get("plan_id") or account.billing_plan_id
            # Amount + currency must match the plan (GHS pesewas)
            from models import PAYSTACK_CURRENCY, USD_TO_GHS
            plan = PREMIUM_PLANS.get(plan_id or "")
            if plan:
                expected = int(plan["price"] * USD_TO_GHS * 100)
                amount = data.get("amount")
                currency = data.get("currency")
                if amount is not None and int(amount) != expected:
                    return {"status": "ignored", "reason": "amount_mismatch"}
                if currency and currency != PAYSTACK_CURRENCY:
                    return {"status": "ignored", "reason": "currency_mismatch"}
            customer = data.get("customer") or {}
            if customer.get("customer_code"):
                account.paystack_customer_code = customer["customer_code"]
            if customer.get("email"):
                account.email = customer["email"]
            # Never persist card auth — one-time payments only
            account.paystack_authorization_code = None
            account.paystack_authorization_reusable = False
            account.billing_ready = False
            account.next_autobill_at = None
            if plan_id:
                _activate_from_plan(db, account, plan_id, ref)
            db.commit()
        return {"status": "ok"}

    if event in ("subscription.create", "subscription.enable", "subscription.disable",
                 "subscription.not_renew", "invoice.payment_failed", "invoice.payment_success"):
        # No auto-renew product — ignore recurring lifecycle events
        return {"status": "ignored", "event": event}

    return {"status": "ignored", "event": event}
