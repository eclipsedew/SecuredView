"""Premium subscription routes — Paystack ONLY. No simulated purchases."""
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Subscription, PREMIUM_PLANS
from schemas import PlanInfo, PurchaseResponse, SubscriptionInfo
from auth import get_current_account
from limiter import limiter

router = APIRouter(prefix="/api/premium", tags=["premium"])


def _now_utc():
    return datetime.now(timezone.utc)


def _ensure_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


@router.get("/plans", response_model=list[PlanInfo])
def list_plans():
    return [
        PlanInfo(id=k, name=v["name"], days=v["days"], price=v["price"], max_devices=v["max_devices"])
        for k, v in PREMIUM_PLANS.items()
    ]


# ⚠️ SIMULATED PURCHASE REMOVED — Use /api/paystack/initialize + /api/paystack/verify
# The old /purchase endpoint was a critical security hole (free premium bypass)


@router.get("/status")
def premium_status(account: Account = Depends(get_current_account)):
    now = _now_utc()
    exp = _ensure_utc(account.premium_expires_at)
    is_active = account.is_premium and exp and exp > now
    remaining = None
    if is_active:
        remaining = (exp - now).total_seconds()
    return {
        "is_premium": is_active,
        "expires_at": exp,
        "remaining_seconds": remaining,
    }


@router.get("/history", response_model=list[SubscriptionInfo])
def subscription_history(
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    subs = db.query(Subscription).filter(
        Subscription.account_id == account.id
    ).order_by(Subscription.purchased_at.desc()).all()

    now = datetime.now(timezone.utc)
    result = []
    for sub in subs:
        exp = sub.expires_at
        if exp and exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        real_status = "active" if exp and exp > now else "expired"
        result.append(SubscriptionInfo(
            id=sub.id,
            plan=sub.plan,
            days=sub.days,
            amount_usd=sub.amount_usd,
            status=real_status,
            purchased_at=sub.purchased_at,
            expires_at=sub.expires_at,
        ))
    return result
