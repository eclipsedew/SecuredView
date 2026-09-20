"""Admin routes for managing accounts, servers, and stats."""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from database import get_db
from models import Account, Device, Server, Subscription
from schemas import ServerStats, AdminLogin, TokenResponse, AccountInfo
from auth import verify_admin, create_access_token, require_auth_or_admin

router = APIRouter(prefix="/api/admin", tags=["admin"])


def _require_admin(auth=Depends(require_auth_or_admin)):
    """Ensure the caller is an admin."""
    if isinstance(auth, dict) and auth.get("is_admin"):
        return auth
    raise HTTPException(status_code=403, detail="Admin access required")


@router.post("/login", response_model=TokenResponse)
def admin_login(req: AdminLogin):
    """Admin login (uses a separate admin credential, not a regular account)."""
    if not verify_admin(req.username, req.password):
        raise HTTPException(status_code=401, detail="Invalid admin credentials")
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
    """List all accounts."""
    accounts = db.query(Account).order_by(Account.created_at.desc()).all()
    result = []
    for acc in accounts:
        device_count = db.query(func.count(Device.id)).filter(
            Device.account_id == acc.id, Device.is_active == True
        ).scalar()
        result.append(AccountInfo(
            id=acc.id,
            display_name=acc.display_name,
            is_premium=acc.is_premium,
            premium_expires_at=acc.premium_expires_at,
            device_count=device_count,
            max_devices=2,
            created_at=acc.created_at,
        ))
    return result


@router.get("/accounts/{account_id}", response_model=AccountInfo)
def get_account(
    account_id: str,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    acc = db.query(Account).filter(Account.id == account_id).first()
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    device_count = db.query(func.count(Device.id)).filter(
        Device.account_id == acc.id, Device.is_active == True
    ).scalar()
    return AccountInfo(
        id=acc.id,
        display_name=acc.display_name,
        is_premium=acc.is_premium,
        premium_expires_at=acc.premium_expires_at,
        device_count=device_count,
        max_devices=2,
        created_at=acc.created_at,
    )


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: str,
    _=Depends(_require_admin),
    db: Session = Depends(get_db),
):
    """Delete an account and all its data."""
    acc = db.query(Account).filter(Account.id == account_id).first()
    if not acc:
        raise HTTPException(status_code=404, detail="Account not found")
    db.delete(acc)
    db.commit()
    return {"message": f"Account {account_id} deleted"}
