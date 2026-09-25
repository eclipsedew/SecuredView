"""Account management routes."""
import re
import secrets
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db, trial_ip_key
from models import (
    Account, Device, TrialClaim, FREE_MAX_DEVICES, PREMIUM_MAX_DEVICES,
    TRIAL_DAYS, TRIAL_IP_PER_DAY, SPECIAL_TRIAL_DAYS,
)
from schemas import (
    AccountCreate, AccountLogin, AccountInfo, TokenResponse, DeviceInfo, UpdateName
)
from auth import (
    hash_pin, verify_pin, create_access_token, get_current_account,
    _is_locked_out, _record_failed_login, _clear_failed_logins
)
from datetime import datetime, timedelta, timezone
from limiter import limiter
from billing import (
    ensure_utc, run_due_billing, start_trial_from_creation,
)

router = APIRouter(prefix="/api/accounts", tags=["accounts"])

PLATFORM_MAX_LENGTH = 32

# Fun device names
_ADJECTIVES = [
    'Smooth', 'Sleepy', 'Swift', 'Bold', 'Calm', 'Clever', 'Crazy', 'Dizzy',
    'Eager', 'Fierce', 'Gentle', 'Happy', 'Jolly', 'Keen', 'Lucky', 'Mighty',
    'Noble', 'Proud', 'Quick', 'Rapid', 'Sharp', 'Sly', 'Wild', 'Witty',
]
_ANIMALS = [
    'Bat', 'Bear', 'Cat', 'Crab', 'Croc', 'Duck', 'Fox', 'Hawk',
    'Lynx', 'Mole', 'Owl', 'Puma', 'Raven', 'Seal', 'Viper', 'Wolf',
]

def _generate_device_name():
    return f"{secrets.choice(_ADJECTIVES)} {secrets.choice(_ANIMALS)}"


def _max_devices(account: Account) -> int:
    if account.is_admin:
        return 999  # the admin's own devices are never capped
    if account.is_premium and account.premium_expires_at:
        exp = account.premium_expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp > datetime.now(timezone.utc):
            return PREMIUM_MAX_DEVICES
    return FREE_MAX_DEVICES


def _ensure_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _premium_active(account: Account) -> bool:
    now = datetime.now(timezone.utc)
    exp = _ensure_utc(account.premium_expires_at)
    return bool(account.is_premium and exp and exp > now)


def _try_grant_trial(db: Session, account: Account, device_key: str, ip_key: str,
                     fingerprint: str | None = None, email: str | None = None) -> bool:
    """One free trial per hardware fingerprint (or device_id fallback) — forever.

    Trial clock is EXACT: started_at = account.created_at,
    ends_at = created_at + TRIAL_DAYS. After that → no access until paid plan.
    Returns True if this registration received a new trial.
    """
    keys = [device_key]
    if fingerprint:
        keys.append(fingerprint)
    claimed = db.query(TrialClaim).filter(TrialClaim.device_key.in_(keys)).first()
    if not claimed and fingerprint:
        claimed = db.query(TrialClaim).filter(TrialClaim.fingerprint == fingerprint).first()
    if claimed:
        return False

    day_ago = datetime.now(timezone.utc) - timedelta(days=1)
    recent = 0
    for row in db.query(TrialClaim).filter(TrialClaim.ip_key == ip_key).all():
        at = row.claimed_at
        if at is None:
            continue
        if at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        if at >= day_ago:
            recent += 1
    if recent >= TRIAL_IP_PER_DAY:
        return False

    ends = start_trial_from_creation(db, account)
    db.add(TrialClaim(
        device_key=device_key,
        ip_key=ip_key,
        account_id=account.id,
        email=email,
        fingerprint=fingerprint,
        claimed_at=ensure_utc(account.trial_started_at) or datetime.now(timezone.utc),
    ))
    _ = ends
    return True


@router.post("/register", response_model=TokenResponse)
@limiter.limit("20/hour")
def register(request: Request, req: AccountCreate, db: Session = Depends(get_db)):
    """Create account + 3-day trial clock from exact creation time. No email required."""
    existing_device = db.query(Device).filter(
        Device.device_id == req.device_id,
        Device.is_active == True,
    ).first()
    if existing_device:
        raise HTTPException(
            status_code=409,
            detail="Device is already registered to another account",
        )

    ip_key = trial_ip_key(request)
    device = Device(
        device_id=req.device_id,
        device_name=req.device_name[:128] if req.device_name and req.device_name != 'unknown' else _generate_device_name(),
        platform=req.platform[:PLATFORM_MAX_LENGTH],
    )
    account = Account(
        pin_hash=hash_pin(req.pin),
        display_name="User",
        device_fingerprint=req.fingerprint,
    )
    db.add(account)
    db.flush()
    device.account_id = account.id
    db.add(device)

    # Trial requires hardware fingerprint — bare random device_ids cannot farm trials.
    if not req.fingerprint:
        db.commit()
        db.refresh(account)
        token = create_access_token(account.id)
        return TokenResponse(
            access_token=token,
            account_id=account.id,
            is_premium=False,
            is_trial=False,
            trial_ends_at=None,
            next_autobill_at=None,
            billing_ready=False,
        )

    claim_key = req.fingerprint or req.device_id
    granted = _try_grant_trial(
        db, account, claim_key, ip_key,
        fingerprint=req.fingerprint,
    )
    # Also claim under raw device_id if fingerprint was the key (both must block)
    if granted and req.fingerprint and req.fingerprint != req.device_id:
        db.add(TrialClaim(
            device_key=req.device_id,
            ip_key=ip_key,
            account_id=account.id,
            fingerprint=req.fingerprint,
            claimed_at=ensure_utc(account.trial_started_at) or datetime.now(timezone.utc),
        ))
    db.commit()
    db.refresh(account)

    token = create_access_token(account.id)
    return TokenResponse(
        access_token=token,
        account_id=account.id,
        is_premium=bool(account.is_premium),
        is_trial=bool(account.is_trial),
        trial_ends_at=ensure_utc(account.trial_ends_at),
        next_autobill_at=None,  # no auto-charge — user subscribes after trial
        billing_ready=False,
    )


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
def login(request: Request, req: AccountLogin, db: Session = Depends(get_db)):
    """Login with account ID + PIN. Runs due auto-bill before returning status."""
    if _is_locked_out(req.account_id):
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")

    account = db.query(Account).filter(Account.id == req.account_id).first()
    if not account:
        _record_failed_login(req.account_id)
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not verify_pin(req.pin, account.pin_hash):
        _record_failed_login(req.account_id)
        raise HTTPException(status_code=401, detail="Invalid credentials")

    _clear_failed_logins(req.account_id)

    # Exact-clock: trial/paid end → access cut (no charge, no free tier)
    try:
        run_due_billing(db, account)
        db.commit()
    except Exception:
        db.rollback()

    # Admin-created trial accounts (normal=3d, special=15d): arm the trial
    # clock on FIRST login — days don't burn while the account sits unused.
    if (
        account.account_type in ("normal", "special")
        and not account.is_trial
        and not account.is_premium
        and not account.trial_started_at
    ):
        trial_days = TRIAL_DAYS if account.account_type == "normal" else SPECIAL_TRIAL_DAYS
        _now = datetime.now(timezone.utc)
        account.trial_started_at = _now
        account.trial_ends_at = _now + timedelta(days=trial_days)
        account.is_trial = True
        account.is_premium = True
        account.premium_expires_at = account.trial_ends_at
        db.commit()
        db.refresh(account)

    max_devs = _max_devices(account)

    existing = db.query(Device).filter(
        Device.account_id == account.id,
        Device.device_id == req.device_id,
    ).first()

    if existing:
        existing.last_seen = datetime.now(timezone.utc)
        existing.is_active = True
        if req.device_name:
            existing.device_name = req.device_name[:128]
        existing.platform = req.platform[:PLATFORM_MAX_LENGTH]
        if req.fingerprint and not account.device_fingerprint:
            account.device_fingerprint = req.fingerprint
    else:
        active_count = db.query(Device).filter(
            Device.account_id == account.id,
            Device.is_active == True,
        ).count()
        if active_count >= max_devs:
            raise HTTPException(
                status_code=403,
                detail="Device limit reached",
            )

        other_account_device = db.query(Device).filter(
            Device.device_id == req.device_id,
            Device.is_active == True,
            Device.account_id != account.id,
        ).first()
        if other_account_device:
            raise HTTPException(
                status_code=409,
                detail="Device is already registered to another account",
            )

        device = Device(
            account_id=account.id,
            device_id=req.device_id,
            device_name=_generate_device_name(),
            platform=req.platform[:PLATFORM_MAX_LENGTH],
        )
        db.add(device)

    db.commit()
    db.refresh(account)

    active = bool(account.is_premium and (
        ensure_utc(account.premium_expires_at) or datetime.min.replace(tzinfo=timezone.utc)
    ) > datetime.now(timezone.utc))

    token = create_access_token(account.id)
    return TokenResponse(
        access_token=token,
        account_id=account.id,
        is_premium=active,
        is_trial=bool(account.is_trial and active),
        trial_ends_at=ensure_utc(account.trial_ends_at),
        next_autobill_at=None,
        billing_ready=bool(account.billing_ready),
        is_admin=bool(account.is_admin),
    )


@router.get("/me", response_model=AccountInfo)
def get_me(account: Account = Depends(get_current_account), db: Session = Depends(get_db)):
    """Get current account info (enforces exact trial clock)."""
    try:
        run_due_billing(db, account)
        db.commit()
    except Exception:
        db.rollback()
        db.refresh(account)

    device_count = db.query(Device).filter(
        Device.account_id == account.id,
        Device.is_active == True,
    ).count()
    now = datetime.now(timezone.utc)
    exp = ensure_utc(account.premium_expires_at)
    premium_active = bool(account.is_premium and exp and exp > now)

    return AccountInfo(
        id=account.id,
        display_name=account.display_name,
        is_premium=premium_active,
        premium_expires_at=exp,
        device_count=device_count,
        max_devices=_max_devices(account),
        created_at=account.created_at,
        is_trial=bool(account.is_trial and premium_active),
        trial_started_at=ensure_utc(account.trial_started_at),
        trial_ends_at=ensure_utc(account.trial_ends_at),
        billing_ready=bool(account.billing_ready),
        is_admin=bool(account.is_admin),
        account_type=account.account_type or "normal",
    )


@router.get("/me/devices", response_model=list[DeviceInfo])
def get_devices(
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """List all devices on this account."""
    devices = db.query(Device).filter(
        Device.account_id == account.id
    ).order_by(Device.registered_at.desc()).all()
    return [DeviceInfo(
        id=d.device_id,
        device_name=d.device_name,
        platform=d.platform,
        registered_at=d.registered_at,
        last_seen=d.last_seen,
        is_active=d.is_active,
    ) for d in devices]


@router.delete("/me/devices/{device_id}")
def remove_device(
    device_id: str,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    """Remove a device from the account.
    Note: The JWT token remains valid until expiry (24h). The device
    will be unable to re-register or login after removal.
    TrialClaim for this device is intentionally left in place.
    """
    device = db.query(Device).filter(
        Device.device_id == device_id,
        Device.account_id == account.id,
    ).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    db.delete(device)
    db.commit()
    return {"message": "Device removed"}


@router.put("/me/name")
def update_name(
    body: UpdateName,
    account: Account = Depends(get_current_account),
    db: Session = Depends(get_db),
):
    account.display_name = body.name.strip()[:64]
    db.commit()
    return {"message": "Name updated"}
