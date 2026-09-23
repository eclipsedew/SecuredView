"""JWT authentication and PIN hashing."""
import os
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt
from sqlalchemy.orm import Session
from database import get_db
from models import Account

# ── Secrets: REQUIRE environment variables in production ───
_env = os.getenv("ENVIRONMENT", "development")

_jwt_secret = os.getenv("SECUREVPN_JWT_SECRET")
if not _jwt_secret:
    if _env == "production":
        raise RuntimeError("SECUREVPN_JWT_SECRET env var is required in production")
    # Persist secret to file so it survives restarts
    _secret_file = os.path.join(os.path.dirname(__file__), ".jwt_secret")
    if os.path.exists(_secret_file):
        with open(_secret_file, "r") as f:
            _jwt_secret = f.read().strip()
    else:
        _jwt_secret = secrets.token_hex(32)
        with open(_secret_file, "w") as f:
            f.write(_jwt_secret)
        print(f"Generated new persistent JWT secret")

_admin_user = os.getenv("SECUREVPN_ADMIN_USER")
_admin_pass = os.getenv("SECUREVPN_ADMIN_PASS")
if not _admin_user or not _admin_pass:
    if _env == "production":
        raise RuntimeError("SECUREVPN_ADMIN_USER and SECUREVPN_ADMIN_PASS required in production")
    # Persist admin creds to file
    _admin_file = os.path.join(os.path.dirname(__file__), ".admin_creds")
    if os.path.exists(_admin_file):
        with open(_admin_file, "r") as f:
            parts = f.read().strip().split(":", 1)
            _admin_user = _admin_user or parts[0]
            _admin_pass = _admin_pass or parts[1]
    else:
        _admin_user = _admin_user or "admin"
        _admin_pass = _admin_pass or secrets.token_hex(12)
        with open(_admin_file, "w") as f:
            f.write(f"{_admin_user}:{_admin_pass}")
        print(f"Generated persistent admin creds")

SECRET_KEY = _jwt_secret
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_HOURS = 24  # Reduced from 72h

ADMIN_USERNAME = _admin_user
ADMIN_PASSWORD = _admin_pass

security = HTTPBearer(auto_error=False)

# ── Failed login tracking (in-memory) ─────────────────────
_failed_logins: dict[str, list[float]] = {}
MAX_LOGIN_ATTEMPTS = 5
LOGIN_LOCKOUT_SECONDS = 300  # 5 minutes


def _is_locked_out(account_id: str) -> bool:
    now = datetime.now(timezone.utc).timestamp()
    attempts = _failed_logins.get(account_id, [])
    # Prune old attempts
    attempts = [t for t in attempts if now - t < LOGIN_LOCKOUT_SECONDS]
    _failed_logins[account_id] = attempts
    return len(attempts) >= MAX_LOGIN_ATTEMPTS


def _record_failed_login(account_id: str):
    now = datetime.now(timezone.utc).timestamp()
    _failed_logins.setdefault(account_id, []).append(now)


def _clear_failed_logins(account_id: str):
    _failed_logins.pop(account_id, None)


# ── PIN hashing ───────────────────────────────────────────
def hash_pin(pin: str) -> str:
    """Hash a PIN with salt using SHA-256."""
    salt = secrets.token_hex(16)
    h = hashlib.sha256(f"{salt}:{pin}".encode()).hexdigest()
    return f"{salt}:{h}"


def verify_pin(plain_pin: str, stored: str) -> bool:
    """Verify a PIN against the salt:hash stored string."""
    try:
        salt, expected_hash = stored.split(":", 1)
        h = hashlib.sha256(f"{salt}:{plain_pin}".encode()).hexdigest()
        return secrets.compare_digest(h, expected_hash)
    except (ValueError, AttributeError):
        return False


# ── JWT ───────────────────────────────────────────────────
def create_access_token(account_id: str, expires_delta: Optional[timedelta] = None) -> str:
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(hours=ACCESS_TOKEN_EXPIRE_HOURS))
    payload = {"sub": account_id, "exp": expire}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> str:
    """Returns account_id from token, raises on failure."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    account_id: str = payload.get("sub")
    if account_id is None:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    # Account IDs are stored uppercase; old tokens may still carry lowercase
    if account_id != "__admin__":
        account_id = account_id.upper()
    return account_id


def get_current_account(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> Account:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    account_id = decode_token(credentials.credentials)
    if account_id == "__admin__":
        raise HTTPException(status_code=403, detail="Admin token cannot access user endpoints")
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return account


def require_auth_or_admin(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
):
    """Returns either an Account or a dict with is_admin=True."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    account_id = decode_token(credentials.credentials)
    if account_id == "__admin__":
        return {"is_admin": True}
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return account


def verify_admin(username: str, password: str) -> bool:
    return username == ADMIN_USERNAME and password == ADMIN_PASSWORD
