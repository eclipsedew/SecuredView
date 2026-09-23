"""Database configuration and session management."""
import os
from sqlalchemy import create_engine, event, text, inspect
from sqlalchemy.orm import sessionmaker, DeclarativeBase

DB_PATH = os.path.join(os.path.dirname(__file__), "securevpn.db")

# Render/Postgres (or any DATABASE_URL) wins; local default stays SQLite.
DATABASE_URL = os.getenv("DATABASE_URL") or f"sqlite:///{DB_PATH}"
# Render sometimes injects postgres:// — SQLAlchemy wants postgresql://
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql://" + DATABASE_URL[len("postgres://"):]

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
    """Create all tables + additive migrations."""
    from models import Account, Device, Server, Subscription, TrialClaim  # noqa
    Base.metadata.create_all(bind=engine)
    migrate_schema()


def trial_ip_key(request) -> str:
    """Stable-enough IP hash for soft rate limits (not a hard identity)."""
    import hashlib
    ip = "unknown"
    if request is not None:
        ip = request.client.host if request.client else "unknown"
        fwd = request.headers.get("x-forwarded-for", "")
        if fwd:
            ip = fwd.split(",")[0].strip()
    return hashlib.sha256(f"sv-trial:{ip}".encode()).hexdigest()[:64]
