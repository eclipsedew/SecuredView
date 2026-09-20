"""SQLAlchemy database models."""
import uuid
import secrets
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Text
)
from sqlalchemy.orm import relationship
from database import Base


def gen_account_id():
    """Generate a 16-char hex account ID."""
    return secrets.token_hex(8)


class Account(Base):
    __tablename__ = "accounts"

    id = Column(String(16), primary_key=True, default=gen_account_id)
    pin_hash = Column(String(128), nullable=False)
    display_name = Column(String(64), default="User")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    is_premium = Column(Boolean, default=False)
    premium_expires_at = Column(DateTime, nullable=True)

    devices = relationship("Device", back_populates="account", cascade="all, delete-orphan")
    subscriptions = relationship("Subscription", back_populates="account", cascade="all, delete-orphan")


class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(String(16), ForeignKey("accounts.id"), nullable=False)
    device_id = Column(String(128), nullable=False, index=True)  # Client-generated UUID
    device_name = Column(String(128), default="Unknown Device")
    platform = Column(String(32), default="android")
    registered_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    last_seen = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    is_active = Column(Boolean, default=True)

    account = relationship("Account", back_populates="devices")


class Server(Base):
    __tablename__ = "servers"

    id = Column(String(32), primary_key=True)
    name = Column(String(64), nullable=False)
    country = Column(String(64), nullable=False)
    country_code = Column(String(2), nullable=False)
    city = Column(String(64), default="")
    ip_address = Column(String(45), nullable=False)
    port = Column(Integer, default=2408)
    latitude = Column(Float, default=0.0)
    longitude = Column(Float, default=0.0)
    tier = Column(String(16), default="free")
    is_active = Column(Boolean, default=True)
    load_percent = Column(Float, default=0.0)
    speed_mbps = Column(Integer, default=100)
    ping_ms = Column(Integer, default=20)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    account_id = Column(String(16), ForeignKey("accounts.id"), nullable=False)
    plan = Column(String(32), nullable=False)
    days = Column(Integer, nullable=False)
    amount_usd = Column(Float, nullable=False)
    status = Column(String(16), default="active")
    purchased_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    expires_at = Column(DateTime, nullable=False)
    payment_ref = Column(String(64), nullable=True)

    account = relationship("Account", back_populates="subscriptions")


# Premium plans config (prices displayed in USD)
PREMIUM_PLANS = {
    "basic_30": {"name": "Basic", "days": 30, "price": 3.99, "max_devices": 3},
    "standard_60": {"name": "Standard", "days": 60, "price": 7.00, "max_devices": 3},
    "premium_90": {"name": "Premium", "days": 90, "price": 13.00, "max_devices": 3},
}

# Currency for Paystack (must match merchant account)
PAYSTACK_CURRENCY = "GHS"

# Approximate USD to GHS rate (update periodically or use an API)
USD_TO_GHS = 11.65

FREE_MAX_DEVICES = 1
PREMIUM_MAX_DEVICES = 3
