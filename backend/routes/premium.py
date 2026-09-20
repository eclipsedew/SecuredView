"""Premium subscription routes — Paystack ONLY. No simulated purchases."""
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address
from database import get_db
from models import Account, Subscription, PREMIUM_PLANS
from schemas import PlanInfo, PurchaseResponse, SubscriptionInfo
from auth import get_current_account

router = APIRouter(prefix="/api/premium", tags=["premium"])
limiter = Limiter(key_func=get_remote_address)


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
        "expires_at": account.premium_expires_at,
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
    return subs
