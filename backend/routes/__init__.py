"""Account management routes."""
import re
import secrets
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
from models import Account, Device, FREE_MAX_DEVICES, PREMIUM_MAX_DEVICES
from schemas import (
    AccountCreate, AccountLogin, AccountInfo, TokenResponse, DeviceInfo, UpdateName
)
from auth import (
    hash_pin, verify_pin, create_access_token, get_current_account,
    _is_locked_out, _record_failed_login, _clear_failed_logins
)
from datetime import datetime, timezone
from limiter import limiter

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
    if account.is_premium and account.premium_expires_at:
        exp = account.premium_expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp > datetime.now(timezone.utc):
            return PREMIUM_MAX_DEVICES
    return FREE_MAX_DEVICES


@router.post("/register", response_model=TokenResponse)
@limiter.limit("3/hour")
def register(request: Request, req: AccountCreate, db: Session = Depends(get_db)):
    """Create a new account with a 4-digit PIN."""
    # Check if device is already registered to another account
    existing_device = db.query(Device).filter(
        Device.device_id == req.device_id,
        Device.is_active == True,
    ).first()
    if existing_device:
        raise HTTPException(
            status_code=409,
            detail="Device is already registered to another account",
        )

    device = Device(
        device_id=req.device_id,
        device_name=req.device_name[:128] if req.device_name and req.device_name != 'unknown' else _generate_device_name(),
        platform=req.platform[:PLATFORM_MAX_LENGTH],
    )
    account = Account(
        pin_hash=hash_pin(req.pin),
        display_name="User",
    )
    db.add(account)
    db.flush()
    device.account_id = account.id
    db.add(device)
    db.commit()
    db.refresh(account)

    token = create_access_token(account.id)
    return TokenResponse(
        access_token=token,
        account_id=account.id,
        is_premium=account.is_premium,
    )


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
def login(request: Request, req: AccountLogin, db: Session = Depends(get_db)):
    """Login with account ID + PIN."""
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

    # Check device limit
    max_devs = _max_devices(account)

    # Check if this device is already registered (by device_id)
    existing = db.query(Device).filter(
        Device.account_id == account.id,
        Device.device_id == req.device_id,
    ).first()

    if existing:
        existing.last_seen = datetime.now(timezone.utc)
        existing.is_active = True
        existing.device_name = req.device_name[:128]
        existing.platform = req.platform[:PLATFORM_MAX_LENGTH]
    else:
        # Re-check device limit within same query to avoid race condition
        active_count = db.query(Device).filter(
            Device.account_id == account.id,
            Device.is_active == True,
        ).count()
        if active_count >= max_devs:
            raise HTTPException(
                status_code=403,
                detail="Device limit reached",
            )

        # Check if device is already registered to another account
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

    now = datetime.now(timezone.utc)
    exp = account.premium_expires_at
    if exp and exp.tzinfo is None:
        exp = exp.replace(tzinfo=timezone.utc)
    premium_active = account.is_premium and exp and exp > now

    token = create_access_token(account.id)
    return TokenResponse(
        access_token=token,
        account_id=account.id,
        is_premium=premium_active,
    )


@router.get("/me", response_model=AccountInfo)
def get_me(account: Account = Depends(get_current_account), db: Session = Depends(get_db)):
    """Get current account info."""
    device_count = db.query(Device).filter(
        Device.account_id == account.id,
        Device.is_active == True,
    ).count()
    now = datetime.now(timezone.utc)
    exp = account.premium_expires_at
    if exp and exp.tzinfo is None:
        exp = exp.replace(tzinfo=timezone.utc)
    premium_active = account.is_premium and exp and exp > now

    return AccountInfo(
        id=account.id,
        display_name=account.display_name,
        is_premium=premium_active,
        premium_expires_at=account.premium_expires_at,
        device_count=device_count,
        max_devices=_max_devices(account),
        created_at=account.created_at,
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
