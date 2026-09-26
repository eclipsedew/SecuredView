"""Admin routes for managing accounts, servers, and stats."""
import secrets as _secrets
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import func
from database import get_db
from models import Account, Device, Server, Subscription, FREE_MAX_DEVICES, PREMIUM_MAX_DEVICES
from schemas import (
    ServerStats, AdminLogin, TokenResponse, AccountInfo,
    FingerprintPurgeRequest, AdminAccountCreate,
)
from models import TrialClaim
from auth import verify_admin, create_access_token, require_auth_or_admin, hash_pin
from limiter import limiter

router = APIRouter(prefix="/api/admin", tags=["admin"])


class PremiumGrant(BaseModel):
    """Grant body. Neither field set = unlimited free premium (2099-12-31)."""
    days: Optional[int] = Field(default=None, ge=1, le=36500)
    expires_at: Optional[str] = None  # ISO-8601 datetime


def _max_devices(account: Account) -> int:
    if account.is_admin:
        return 999
    if account.is_premium and account.premium_expires_at:
        exp = account.premium_expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp > datetime.now(timezone.utc):
            return PREMIUM_MAX_DEVICES
    return FREE_MAX_DEVICES


def _require_admin(auth=Depends(require_auth_or_admin)):
    """Admin = seeded admin app account (is_admin) or legacy __admin__ token."""
    if isinstance(auth, dict) and auth.get("is_admin"):
        return auth
    if isinstance(auth, Account) and auth.is_admin:
        return auth
    raise HTTPException(status_code=403, detail="Admin access required")


def _account_info(acc: Account, db: Session) -> AccountInfo:
    device_count = db.query(func.count(Device.id)).filter(
        Device.account_id == acc.id, Device.is_active == True
    ).scalar()
    device_ids = [
        r[0] for r in db.query(Device.device_id)
        .filter(Device.account_id == acc.id).all()
    ]
    return AccountInfo(
        id=acc.id,
        display_name=acc.display_name,
        is_premium=acc.is_premium,
        premium_expires_at=acc.premium_expires_at,
        device_count=device_count,
        max_devices=_max_devices(acc),
        created_at=acc.created_at,
        is_trial=bool(acc.is_trial),
        trial_started_at=acc.trial_started_at,
        trial_ends_at=acc.trial_ends_at,
        billing_ready=bool(acc.billing_ready),
        device_fingerprint=acc.device_fingerprint,
        device_ids=device_ids,
        is_admin=bool(acc.is_admin),
        account_type=acc.account_type or "normal",
    )


# Admin login brute-force tracking — keyed "<username>@<ip>" so an attacker
# cannot lock the admin out of the dashboard by spraying bad passwords from
# their own machine (they only lock their own key).
_admin_failed_logins: dict[str, list[float]] = {}
ADMIN_MAX_ATTEMPTS = 5
ADMIN_LOCKOUT_SECONDS = 600  # 10 minutes


def _admin_is_locked_out(key: str) -> bool:
    now = datetime.now(timezone.utc).timestamp()
    attempts = _admin_failed_logins.get(key, [])
    attempts = [t for t in attempts if now - t < ADMIN_LOCKOUT_SECONDS]
    if attempts:
        _admin_failed_logins[key] = attempts
    else:
        _admin_failed_logins.pop(key, None)
    return len(attempts) >= ADMIN_MAX_ATTEMPTS


def _admin_record_failed(key: str):
    now = datetime.now(timezone.utc).timestamp()
    _admin_failed_logins.setdefault(key, []).append(now)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
def admin_login(request: Request, req: AdminLogin):
    """Admin login with brute-force protection."""
    from clientip import client_ip
    _lock = f"{req.username}@{client_ip(request)}"
    if _admin_is_locked_out(_lock):
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")

    if not verify_admin(req.username, req.password):
        _admin_record_failed(_lock)
        raise HTTPException(status_code=401, detail="Invalid admin credentials")

    # Clear on success
    _admin_failed_logins.pop(_lock, None)
    token = create_access_token("__admin__")
    return TokenResponse(
        access_token=token,
        account_id="__admin__",
        is_premium=True,
    )


@router.get("/stats", response_model=ServerStats)
def get_stats(
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Get platform-wide statistics."""
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    total_accounts = db.query(func.count(Account.id)).scalar()
    total_premium = db.query(func.count(Account.id)).filter(
        Account.is_premium == True,
        Account.premium_expires_at > now_naive,
    ).scalar()
    total_devices = db.query(func.count(Device.id)).scalar()
    active_devices = db.query(func.count(Device.id)).filter(Device.is_active == True).scalar()
    total_servers = db.query(func.count(Server.id)).scalar()
    free_servers = db.query(func.count(Server.id)).filter(Server.tier == "free", Server.is_active == True).scalar()
    premium_servers = db.query(func.count(Server.id)).filter(Server.tier == "premium", Server.is_active == True).scalar()

    return ServerStats(
        total_accounts=total_accounts,
        total_premium_accounts=total_premium,
        total_devices=total_devices,
        total_active_devices=active_devices,
        total_servers=total_servers,
        free_servers=free_servers,
        premium_servers=premium_servers,
    )


@router.get("/accounts", response_model=list[AccountInfo])
def list_accounts(
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """List user accounts (the admin row itself is excluded)."""
    accounts = (
        db.query(Account)
        .filter(Account.is_admin != True)
        .order_by(Account.created_at.desc())
        .all()
    )
    return [_account_info(acc, db) for acc in accounts]


@router.get("/accounts/{account_id}", response_model=AccountInfo)
def get_account(
    account_id: str,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    acc = db.query(Account).filter(Account.id == account_id.upper()).first()
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    return _account_info(acc, db)


@router.post("/accounts")
def create_account(
    req: AdminAccountCreate,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Create a user account from the admin dashboard.

    - normal: 3-day trial, clock starts on the account's first login
    - special: 15-day trial, clock starts on first login
    - premium: admin chooses the number of days, active immediately
    """
    if req.account_type == "premium" and not req.days:
        raise HTTPException(status_code=400, detail="days is required for premium accounts")

    pin = req.pin or f"{_secrets.randbelow(10000):04d}"
    now = datetime.now(timezone.utc)
    acc = Account(
        pin_hash=hash_pin(pin),
        display_name=(req.display_name or "User")[:64],
        account_type=req.account_type,
    )
    if req.account_type == "premium":
        acc.is_premium = True
        acc.is_trial = False
        acc.premium_expires_at = now + timedelta(days=req.days)
    db.add(acc)
    db.flush()

    if req.account_type == "premium":
        db.add(Subscription(
            account_id=acc.id,
            plan="premium_90",
            days=req.days,
            amount_usd=0.0,
            status="active",
            expires_at=acc.premium_expires_at,
            payment_ref=f"admin-create-{acc.id}-{int(now.timestamp())}",
        ))
    db.commit()
    db.refresh(acc)

    info = _account_info(acc, db)
    return {
        "account_id": acc.id,
        "pin": pin,
        "account_type": acc.account_type,
        "info": info.model_dump(mode="json"),
        "note": (
            f"Premium active for {req.days} days"
            if acc.account_type == "premium"
            else f"{req.account_type.capitalize()} trial "
                 f"({'3' if acc.account_type == 'normal' else '15'} days) "
                 f"starts at first login"
        ),
    }


@router.post("/accounts/{account_id}/premium")
def grant_premium(
    account_id: str,
    payload: Optional[PremiumGrant] = None,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Grant premium to an account. Default: unlimited free premium until 2099.

    Clears the trial clock and autobill state so the account never expires
    or auto-charges. Writes an amount=0 Subscription row so premium history
    renders in the app.
    """
    acc = db.query(Account).filter(Account.id == account_id.upper()).first()
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")

    now = datetime.now(timezone.utc)
    exp: datetime
    if payload and payload.days:
        # Extend from now, or stack on remaining active premium time
        current = acc.premium_expires_at
        if current is not None and current.tzinfo is None:
            current = current.replace(tzinfo=timezone.utc)
        base = current if (acc.is_premium and current and current > now) else now
        exp = base + timedelta(days=payload.days)
    elif payload and payload.expires_at:
        try:
            exp = datetime.fromisoformat(payload.expires_at)
        except ValueError:
            raise HTTPException(status_code=400, detail="expires_at must be ISO-8601")
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
    else:
        exp = datetime(2099, 12, 31, tzinfo=timezone.utc)

    if exp <= now:
        raise HTTPException(status_code=400, detail="expiry must be in the future")

    acc.is_premium = True
    acc.is_trial = False
    acc.premium_expires_at = exp
    acc.trial_started_at = None
    acc.trial_ends_at = None
    acc.next_autobill_at = None

    db.add(Subscription(
        account_id=acc.id,
        plan="premium_90",
        days=max(1, (exp - now).days),
        amount_usd=0.0,
        status="active",
        expires_at=exp,
        payment_ref=f"admin-{acc.id}-{int(now.timestamp())}",
    ))
    db.commit()
    return {
        "account_id": acc.id,
        "is_premium": True,
        "premium_expires_at": exp.isoformat(),
    }


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: str,
    purge_fingerprint: bool = False,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Delete an account and devices.

    Default: trial_claims rows are kept forever (blocks delete→recreate trial farm).
    With ?purge_fingerprint=true: also delete trial_claims and clear the hardware
    fingerprint so the physical device can claim a fresh trial.
    """
    acc = db.query(Account).filter(Account.id == account_id.upper()).first()
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    if acc.is_admin:
        raise HTTPException(status_code=400, detail="The admin account cannot be deleted")
    fp = acc.device_fingerprint
    if purge_fingerprint:
        # Full wipe for this hardware: claims by account / fingerprint / device_id
        device_ids = [d.device_id for d in list(acc.devices)]
        claim_ids = {
            r[0] for r in db.query(TrialClaim.id).filter(TrialClaim.account_id == acc.id).all()
        }
        if fp:
            claim_ids |= {
                r[0] for r in db.query(TrialClaim.id).filter(
                    (TrialClaim.fingerprint == fp) | (TrialClaim.device_key == fp)
                ).all()
            }
        if device_ids:
            claim_ids |= {
                r[0] for r in db.query(TrialClaim.id).filter(
                    TrialClaim.device_key.in_(device_ids)
                ).all()
            }
        if claim_ids:
            db.query(TrialClaim).filter(TrialClaim.id.in_(claim_ids)).delete(
                synchronize_session=False
            )
        if fp:
            db.query(Account).filter(Account.device_fingerprint == fp).update(
                {Account.device_fingerprint: None}, synchronize_session=False
            )
        db.delete(acc)
        db.commit()
        return {
            "message": f"Account {account_id} deleted",
            "purged_fingerprint": fp,
            "purged": True,
            "trial_claims_deleted": len(claim_ids),
        }
    # Orphan trial claims (no FK) so the device cannot claim again
    db.query(TrialClaim).filter(TrialClaim.account_id == acc.id).update(
        {TrialClaim.account_id: None}
    )
    db.delete(acc)
    db.commit()
    return {"message": f"Account {account_id} deleted", "purged": False}


@router.post("/fingerprints/purge")
def purge_fingerprint(
    req: FingerprintPurgeRequest,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Clear a hardware fingerprint and all accounts/trial claims bound to it.

    Use for ops: wipe a test device so it can register a fresh trial.
    """
    fp = req.fingerprint.strip().lower()
    fp_raw = req.fingerprint.strip()
    accounts = db.query(Account).filter(Account.device_fingerprint == fp).all()
    if not accounts:
        accounts = db.query(Account).filter(Account.device_fingerprint == fp_raw).all()
        fp_stored = fp_raw
    else:
        fp_stored = fp

    account_ids = [a.id for a in accounts]
    device_keys: list[str] = []
    for a in accounts:
        device_keys.extend([d.device_id for d in a.devices])

    # Collect claim IDs first — union().delete() is not portable
    claim_ids: set[int] = set()
    for q in (
        db.query(TrialClaim.id).filter(TrialClaim.fingerprint.in_([fp, fp_raw])),
        db.query(TrialClaim.id).filter(TrialClaim.device_key.in_([fp, fp_raw])),
    ):
        claim_ids |= {r[0] for r in q.all()}
    if account_ids:
        claim_ids |= {
            r[0] for r in db.query(TrialClaim.id)
            .filter(TrialClaim.account_id.in_(account_ids)).all()
        }
    if device_keys:
        claim_ids |= {
            r[0] for r in db.query(TrialClaim.id)
            .filter(TrialClaim.device_key.in_(device_keys)).all()
        }
    claims_deleted = 0
    if claim_ids:
        claims_deleted = db.query(TrialClaim).filter(
            TrialClaim.id.in_(claim_ids)
        ).delete(synchronize_session=False)

    accounts_deleted = 0
    if req.delete_accounts:
        for a in accounts:
            db.delete(a)  # cascades devices + subscriptions
            accounts_deleted += 1
    else:
        db.query(Account).filter(Account.device_fingerprint.in_([fp, fp_raw])).update(
            {Account.device_fingerprint: None}, synchronize_session=False
        )

    db.commit()
    return {
        "fingerprint": fp_stored,
        "accounts_deleted": accounts_deleted,
        "account_ids": account_ids,
        "trial_claims_deleted": claims_deleted,
        "device_keys": device_keys,
    }


@router.get("/fingerprints")
def list_fingerprints(
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """List distinct hardware fingerprints with linked accounts / trial claims."""
    rows = (
        db.query(
            Account.device_fingerprint,
            func.count(Account.id),
            func.min(Account.created_at),
        )
        .filter(Account.device_fingerprint.isnot(None))
        .group_by(Account.device_fingerprint)
        .all()
    )
    out = []
    for fp, n, created in rows:
        acc_ids = [
            r[0] for r in db.query(Account.id).filter(Account.device_fingerprint == fp).all()
        ]
        claim_filters = [(TrialClaim.fingerprint == fp), (TrialClaim.device_key == fp)]
        if acc_ids:
            claim_filters.append(TrialClaim.account_id.in_(acc_ids))
        claim_count = (
            db.query(func.count(TrialClaim.id)).filter(*claim_filters).scalar()
        )
        out.append({
            "fingerprint": fp,
            "account_count": n,
            "account_ids": acc_ids,
            "trial_claim_count": claim_count,
            "first_seen": created,
        })
    return out
