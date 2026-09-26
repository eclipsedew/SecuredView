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
# Keyed "<account>@<ip>": a hostile client can otherwise lock a victim out of
# their own account just by sending the victim's account id with bad PINs.
_failed_logins: dict[str, list[float]] = {}
MAX_LOGIN_ATTEMPTS = 5
LOGIN_LOCKOUT_SECONDS = 300  # 5 minutes


def _is_locked_out(key: str) -> bool:
    now = datetime.now(timezone.utc).timestamp()
    attempts = _failed_logins.get(key, [])
    # Prune old attempts
    attempts = [t for t in attempts if now - t < LOGIN_LOCKOUT_SECONDS]
    if attempts:
        _failed_logins[key] = attempts
    else:
        _failed_logins.pop(key, None)
    return len(attempts) >= MAX_LOGIN_ATTEMPTS


def _record_failed_login(key: str):
    now = datetime.now(timezone.utc).timestamp()
    _failed_logins.setdefault(key, []).append(now)
    if len(_failed_logins) > 10000:
        # Memory cap: drop expired entries everywhere.
        for k in list(_failed_logins):
            live = [t for t in _failed_logins[k] if now - t < LOGIN_LOCKOUT_SECONDS]
            if live:
                _failed_logins[k] = live
            else:
                _failed_logins.pop(k, None)


def _clear_failed_logins(key: str):
    _failed_logins.pop(key, None)


# ── PIN hashing ───────────────────────────────────────────
_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2 ** 14, 8, 1
_SCRYPT_MAXMEM = 64 * 1024 * 1024


def hash_pin(pin: str) -> str:
    """Hash a PIN with salt using scrypt (format: scrypt$n$r$p$salt$dk).

    The previous scheme was a single unsalted-cost SHA-256 — offline brute
    force of the 4-digit space is instant. Old hashes keep verifying and are
    transparently upgraded on the next successful login.
    """
    salt = secrets.token_hex(16)
    dk = hashlib.scrypt(
        pin.encode(), salt=bytes.fromhex(salt),
        n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32, maxmem=_SCRYPT_MAXMEM,
    )
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt}${dk.hex()}"


def is_modern_pin_hash(stored: str) -> bool:
    return isinstance(stored, str) and stored.startswith("scrypt$")


def verify_pin(plain_pin: str, stored: str) -> bool:
    """Verify a PIN; understands both current scrypt and legacy sha256 hashes."""
    try:
        if is_modern_pin_hash(stored):
            _, n, r, p, salt_hex, hash_hex = stored.split("$")
            dk = hashlib.scrypt(
                plain_pin.encode(), salt=bytes.fromhex(salt_hex),
                n=int(n), r=int(r), p=int(p),
                dklen=len(bytes.fromhex(hash_hex)), maxmem=_SCRYPT_MAXMEM,
            )
            return secrets.compare_digest(dk.hex(), hash_hex)
        salt, expected_hash = stored.split(":", 1)
        h = hashlib.sha256(f"{salt}:{plain_pin}".encode()).hexdigest()
        return secrets.compare_digest(h, expected_hash)
    except (ValueError, AttributeError, TypeError, OverflowError):
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
    # compare_digest: non-constant-time == leaks credential prefix length.
    return (
        secrets.compare_digest(username or "", ADMIN_USERNAME or "")
        and secrets.compare_digest(password or "", ADMIN_PASSWORD or "")
    )
