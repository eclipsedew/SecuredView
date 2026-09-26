"""Database configuration and session management."""
import os
from sqlalchemy import create_engine, event, text, inspect
from sqlalchemy.orm import sessionmaker, DeclarativeBase

DB_PATH = os.path.join(os.path.dirname(__file__), "securevpn.db")

# Render/Postgres (or any DATABASE_URL) wins; local default stays SQLite.
DATABASE_URL = os.getenv("DATABASE_URL") or f"sqlite:///{DB_PATH}"
# Render sometimes injects postgres:// — SQLAlchemy wants postgresql://.
# SQLAlchemy >= 2.1 silently switched bare postgresql:// to the psycopg (v3)
# driver, but we ship psycopg2-binary; that mismatch crashed every deploy
# (ModuleNotFoundError: psycopg). Pin the driver into the URL explicitly.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql+psycopg2://" + DATABASE_URL[len("postgres://"):]
elif DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = "postgresql+psycopg2://" + DATABASE_URL[len("postgresql://"):]

_IS_SQLITE = DATABASE_URL.startswith("sqlite")

if _IS_SQLITE:
    engine = create_engine(
        DATABASE_URL, connect_args={"check_same_thread": False}
    )

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
else:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_recycle=300,
    )

    @event.listens_for(engine, "connect")
    def _set_pg_utc(dbapi_connection, connection_record):
        # Render Postgres runs in a non-UTC timezone by default; naive
        # datetime.now() values would drift against NOW()-based queries.
        cursor = dbapi_connection.cursor()
        cursor.execute("SET TIME ZONE 'UTC'")
        cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Columns added after first deploy — create_all does not ALTER existing tables.
_ACCOUNT_EXTRA_COLUMNS = [
    ("email", "VARCHAR(254)"),
    ("trial_started_at", "TIMESTAMP"),
    ("trial_ends_at", "TIMESTAMP"),
    ("is_trial", "BOOLEAN"),
    ("paystack_customer_code", "VARCHAR(64)"),
    ("paystack_authorization_code", "VARCHAR(64)"),
    ("paystack_authorization_reusable", "BOOLEAN"),
    ("paystack_subscription_code", "VARCHAR(64)"),
    ("billing_plan_id", "VARCHAR(32)"),
    ("billing_ready", "BOOLEAN"),
    ("last_billing_attempt_at", "TIMESTAMP"),
    ("next_autobill_at", "TIMESTAMP"),
    ("billing_failures", "INTEGER"),
    ("billing_stopped", "BOOLEAN"),
    ("billing_stop_reason", "VARCHAR(64)"),
    ("device_fingerprint", "VARCHAR(128)"),
    ("account_type", "VARCHAR(16) DEFAULT 'normal'"),
    ("is_admin", "BOOLEAN DEFAULT FALSE"),
    ("trial_eligible", "BOOLEAN DEFAULT TRUE"),
]


def _sqlite_col_type(sqltype: str) -> str:
    # SQLite is loose about types; keep the declared name.
    return sqltype


def _pg_col_type(sqltype: str) -> str:
    return sqltype


def migrate_schema():
    """Additive migrations for live DBs (Render Postgres / existing SQLite)."""
    insp = inspect(engine)
    type_fn = _pg_col_type if not _IS_SQLITE else _sqlite_col_type
    if "accounts" not in insp.get_table_names():
        return
    existing = {c["name"] for c in insp.get_columns("accounts")}
    with engine.begin() as conn:
        for name, sqltype in _ACCOUNT_EXTRA_COLUMNS:
            if name in existing:
                continue
            conn.execute(text(
                f'ALTER TABLE accounts ADD COLUMN {name} {type_fn(sqltype)}'
            ))
            print(f"migrated: accounts.{name}")
            if name == "account_type":
                # Every row that predates the admin dashboard is legacy —
                # they never get first-login trial arming or a type badge.
                conn.execute(text("UPDATE accounts SET account_type = 'legacy'"))
    # trial_claims created later than first deploy
    if "trial_claims" in insp.get_table_names():
        t_existing = {c["name"] for c in insp.get_columns("trial_claims")}
        if "fingerprint" not in t_existing:
            with engine.begin() as conn:
                conn.execute(text(
                    f'ALTER TABLE trial_claims ADD COLUMN fingerprint {type_fn("VARCHAR(128)")}'
                ))
                print("migrated: trial_claims.fingerprint")


def init_db():
    """Create all tables + additive migrations + seed the admin account(s)."""
    from models import (  # noqa
        Account, Device, Server, Subscription, TrialClaim,
        ADMIN_ACCOUNT_ID, ADMIN_ACCOUNT_PIN,
        ADMIN_ALT_ACCOUNT_ID, ADMIN_ALT_ACCOUNT_PIN,
    )
    Base.metadata.create_all(bind=engine)
    migrate_schema()
    seed_admin(ADMIN_ACCOUNT_ID, ADMIN_ACCOUNT_PIN)
    if ADMIN_ALT_ACCOUNT_ID and ADMIN_ALT_ACCOUNT_PIN:
        seed_admin(ADMIN_ALT_ACCOUNT_ID, ADMIN_ALT_ACCOUNT_PIN)


def seed_admin(account_id: str, pin) -> None:
    """Create or sync an admin account from env-configured credentials.

    - pin None (SECUREVPN_*_PIN not set) → nothing happens; an existing row
      keeps working, so an unset env can never lock you out.
    - row missing → create it (admin, unlimited premium until 2099).
    - row exists + pin set → rotate pin_hash when it no longer verifies.
      The env var is the ONLY reset path; the app has no reset flow.
    """
    if not pin:
        print(f"admin seed skipped ({account_id}): no pin in env")
        return
    from models import Account  # noqa
    from auth import hash_pin, verify_pin  # lazy: auth imports this module
    from datetime import datetime, timezone
    db = SessionLocal()
    try:
        acct = db.query(Account).filter(Account.id == account_id).first()
        if acct is None:
            db.add(Account(
                id=account_id,
                pin_hash=hash_pin(pin),
                display_name="Admin",
                is_admin=True,
                account_type="admin",
                is_premium=True,
                premium_expires_at=datetime(2099, 12, 31, tzinfo=timezone.utc),
            ))
            db.commit()
            print(f"seeded admin account {account_id}")
            return
        changed = False
        if not verify_pin(pin, acct.pin_hash):
            acct.pin_hash = hash_pin(pin)
            changed = True
        if not acct.is_admin:
            acct.is_admin = True
            changed = True
        if not acct.is_premium:
            acct.is_premium = True
            acct.premium_expires_at = datetime(2099, 12, 31, tzinfo=timezone.utc)
            changed = True
        if changed:
            db.commit()
            print(f"synced admin account {account_id}")
    finally:
        db.close()


def trial_ip_key(request) -> str:
    """Stable-enough IP hash for soft rate limits (not a hard identity).

    Uses the proxy-attested client IP (last X-Forwarded-For hop) — indexing
    position 0 lets a client spoof any bucket by prepending fake entries.
    """
    import hashlib
    from clientip import client_ip
    return hashlib.sha256(f"sv-trial:{client_ip(request)}".encode()).hexdigest()[:64]
