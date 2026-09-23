"""Trial clock — exact UTC timeline from account creation (server-authoritative).

  trial_started_at = created_at
  trial_ends_at    = created_at + TRIAL_DAYS
  after that       → no server access until the user buys a plan (no free tier)

Device clock is never trusted for entitlement. Clients only display remaining
time; the backend returns is_premium / remaining_seconds on every status check.

No card on file, no auto-charge. Paystack is only used when the user
explicitly opens checkout; we never store card details (hosted page only).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from models import Account, TRIAL_DAYS


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def ensure_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def trial_end_from_created(created_at: Optional[datetime]) -> datetime:
    """Exact trial end: creation moment + TRIAL_DAYS (UTC)."""
    started = ensure_utc(created_at) or now_utc()
    return started + timedelta(days=TRIAL_DAYS)


def start_trial_from_creation(db: Session, account: Account) -> datetime:
    """Arm the trial clock to the account's exact creation datetime."""
    started = ensure_utc(account.created_at) or now_utc()
    ends = trial_end_from_created(account.created_at)
    account.trial_started_at = started
    account.trial_ends_at = ends
    account.is_trial = True
    account.is_premium = True
    account.premium_expires_at = ends
    db.flush()
    return ends


def apply_trial_clock(db: Session, account: Account) -> bool:
    """Expire trial → no access when the exact end time has passed.

    Returns True if access was cut (is_premium / is_trial cleared).
    There is no free server tier after this — user must subscribe.
    """
    now = now_utc()
    exp = ensure_utc(account.premium_expires_at)
    ends = ensure_utc(account.trial_ends_at)

    # Paid (non-trial) period still active?
    if account.is_premium and not account.is_trial and exp and exp > now:
        return False

    # Trial still inside window?
    if account.is_trial and ends and ends > now and exp and exp > now:
        return False

    # Window closed (or never had an end) → no paid access (manual subscribe)
    changed = bool(account.is_trial or account.is_premium)
    if changed:
        account.is_trial = False
        account.is_premium = False
        # Keep historical trial_ends_at; clear live access
        if exp and exp > now:
            account.premium_expires_at = now
        db.flush()
        return True

    # Non-trial paid expiry (manual subscribe period ended)
    if account.is_premium and exp and exp <= now:
        account.is_premium = False
        db.flush()
        return True
    return False


def run_due_billing(db: Session, account: Account) -> Optional[dict]:
    """Clock-only enforcement (name kept for call sites).

    Trial ends → access stops (no free servers). Paid period ends → access stops.
    Never charges a card.
    """
    cut = apply_trial_clock(db, account)
    if cut:
                return {"ok": False, "message": "trial ended — subscribe to continue", "cut": True}
    return None


def sweep_due_accounts(db: Session, limit: int = 100) -> int:
    """Expire any trial/premium past its exact end datetime."""
    now = now_utc()
    rows = (
        db.query(Account)
        .filter(Account.is_trial.is_(True) | Account.is_premium.is_(True))
        .limit(limit)
        .all()
    )
    handled = 0
    for acc in rows:
        if apply_trial_clock(db, acc):
            handled += 1
    try:
        db.commit()
    except Exception:
        db.rollback()
    return handled
