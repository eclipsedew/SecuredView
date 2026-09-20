"""Pydantic schemas for API request/response validation."""
import re
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field, field_validator


# ── Input sanitization helpers ───────────────────────────
def _sanitize_name(v: str) -> str:
    """Strip and limit display names — prevent XSS / injection."""
    v = v.strip()
    # Remove HTML tags
    v = re.sub(r"<[^>]+>", "", v)
    # Remove control characters
    v = re.sub(r"[\x00-\x1f\x7f]", "", v)
    return v[:64]


def _validate_email(v: str) -> str:
    """Basic email format validation."""
    v = v.strip().lower()
    if not re.fullmatch(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", v):
        raise ValueError("Invalid email format")
    return v


# ── Account ──────────────────────────────────────────────
class AccountCreate(BaseModel):
    pin: str = Field(..., min_length=4, max_length=4, description="4-digit PIN")
    device_id: str = Field(..., min_length=8, max_length=128, description="Unique device identifier")
    device_name: str = Field(default="Unknown Device", max_length=128)
    platform: str = Field(default="android", max_length=32)

    @field_validator("pin")
    @classmethod
    def pin_must_be_digits(cls, v):
        if not re.fullmatch(r"\d{4}", v):
            raise ValueError("PIN must be exactly 4 digits")
        return v

    @field_validator("device_id")
    @classmethod
    def device_id_alphanumeric(cls, v):
        if not re.fullmatch(r"[a-f0-9]{8,128}", v):
            raise ValueError("Device ID must be lowercase hex")
        return v

    @field_validator("platform")
    @classmethod
    def platform_valid(cls, v):
        allowed = {"android", "ios", "linux", "windows", "macos", "web"}
        if v.lower() not in allowed:
            raise ValueError(f"Platform must be one of: {', '.join(allowed)}")
        return v.lower()


class AccountLogin(BaseModel):
    account_id: str = Field(..., min_length=16, max_length=16)
    pin: str = Field(..., min_length=4, max_length=4)
    device_id: str = Field(..., min_length=8, max_length=128)
    device_name: str = Field(default="Unknown Device", max_length=128)
    platform: str = Field(default="android", max_length=32)

    @field_validator("pin")
    @classmethod
    def pin_must_be_digits(cls, v):
        if not re.fullmatch(r"\d{4}", v):
            raise ValueError("PIN must be exactly 4 digits")
        return v

    @field_validator("account_id")
    @classmethod
    def account_id_hex(cls, v):
        if not re.fullmatch(r"[a-f0-9]{16}", v):
            raise ValueError("Invalid account ID format")
        return v

    @field_validator("platform")
    @classmethod
    def platform_valid(cls, v):
        allowed = {"android", "ios", "linux", "windows", "macos", "web"}
        if v.lower() not in allowed:
            raise ValueError(f"Platform must be one of: {', '.join(allowed)}")
        return v.lower()


class AccountInfo(BaseModel):
    id: str
    display_name: str
    is_premium: bool
    premium_expires_at: Optional[datetime] = None
    device_count: int
    max_devices: int
    created_at: datetime

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    account_id: str
    is_premium: bool


# ── Device ───────────────────────────────────────────────
class DeviceInfo(BaseModel):
    id: str
    device_name: str
    platform: str
    registered_at: datetime
    last_seen: datetime
    is_active: bool

    class Config:
        from_attributes = True


# ── Server ───────────────────────────────────────────────
class ServerInfo(BaseModel):
    id: str
    name: str
    country: str
    country_code: str
    city: str
    ip_address: str
    port: int
    latitude: float
    longitude: float
    tier: str
    is_active: bool
    load_percent: float
    speed_mbps: int
    ping_ms: int

    class Config:
        from_attributes = True


class ServerPublic(BaseModel):
    """Server info without sensitive fields for unauthenticated users."""
    id: str
    name: str
    country: str
    country_code: str
    city: str
    latitude: float
    longitude: float
    tier: str
    is_active: bool
    speed_mbps: int
    ping_ms: int

    class Config:
        from_attributes = True


class ServerCreate(BaseModel):
    id: str = Field(..., min_length=3, max_length=32)
    name: str = Field(..., min_length=1, max_length=64)
    country: str = Field(..., min_length=1, max_length=64)
    country_code: str = Field(..., min_length=2, max_length=2)
    city: str = Field(default="", max_length=64)
    ip_address: str = Field(..., max_length=45)
    port: int = Field(default=2408, ge=1, le=65535)
    latitude: float = Field(default=0.0, ge=-90, le=90)
    longitude: float = Field(default=0.0, ge=-180, le=180)
    tier: str = Field(default="free")
    speed_mbps: int = Field(default=100, ge=1)
    ping_ms: int = Field(default=20, ge=0)

    @field_validator("tier")
    @classmethod
    def tier_must_be_valid(cls, v):
        if v not in ("free", "premium"):
            raise ValueError("tier must be 'free' or 'premium'")
        return v


class ServerUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=64)
    country: Optional[str] = Field(None, max_length=64)
    country_code: Optional[str] = Field(None, min_length=2, max_length=2)
    city: Optional[str] = Field(None, max_length=64)
    ip_address: Optional[str] = Field(None, max_length=45)
    port: Optional[int] = Field(None, ge=1, le=65535)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    tier: Optional[str] = None
    is_active: Optional[bool] = None
    load_percent: Optional[float] = Field(None, ge=0, le=100)
    speed_mbps: Optional[int] = Field(None, ge=1)
    ping_ms: Optional[int] = Field(None, ge=0)


class UpdateName(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)

    @field_validator("name")
    @classmethod
    def sanitize_name(cls, v):
        return _sanitize_name(v)


# ── Subscription / Premium ───────────────────────────────
class PlanInfo(BaseModel):
    id: str
    name: str
    days: int
    price: float
    max_devices: int


class PurchaseResponse(BaseModel):
    success: bool
    message: str
    subscription_id: Optional[int] = None
    expires_at: Optional[datetime] = None


class SubscriptionInfo(BaseModel):
    id: int
    plan: str
    days: int
    amount_usd: float
    status: str
    purchased_at: datetime
    expires_at: datetime

    class Config:
        from_attributes = True


# ── Stats ────────────────────────────────────────────────
class ServerStats(BaseModel):
    total_accounts: int
    total_premium_accounts: int
    total_devices: int
    total_active_devices: int
    total_servers: int
    free_servers: int
    premium_servers: int


# ── Admin ────────────────────────────────────────────────
class AdminLogin(BaseModel):
    username: str = Field(..., max_length=64)
    password: str = Field(..., max_length=128)
