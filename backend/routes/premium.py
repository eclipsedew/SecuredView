"""Premium subscription and purchase routes."""
import secrets
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Subscription, PREMIUM_PLANS
from schemas import PlanInfo, PurchaseRequest, PurchaseResponse, SubscriptionInfo
from auth import get_current_account

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


@router.post("/purchase", response_model=PurchaseResponse)
def purchase_premium(
    req: PurchaseRequest,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    plan = PREMIUM_PLANS.get(req.plan_id)
    if not plan:
        raise HTTPException(status_code=400, detail="Invalid plan selected")

    now = _now_utc()
    expires = now + timedelta(days=plan["days"])

    # If already premium, extend from current expiry (cap at 1 year)
    current_exp = _ensure_utc(account.premium_expires_at)
    if account.is_premium and current_exp and current_exp > now:
        new_expiry = current_exp + timedelta(days=plan["days"])
        # Cap at 1 year from now
        max_expiry = now + timedelta(days=365)
        expires = min(new_expiry, max_expiry)

    sub = Subscription(
        account_id=account.id,
        plan=req.plan_id,
        days=plan["days"],
        amount_usd=plan["price"],
        status="active",
        expires_at=expires,
        payment_ref=f"SIM-{secrets.token_hex(8).upper()}",
    )
    db.add(sub)
    account.is_premium = True
    account.premium_expires_at = expires
    db.commit()
    db.refresh(sub)

    return PurchaseResponse(
        success=True,
        message=f"Plan activated for {plan['days']} days",
        subscription_id=sub.id,
        expires_at=expires,
    )


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
