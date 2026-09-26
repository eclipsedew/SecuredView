"""SecureVPN Backend - FastAPI application."""
import os
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from starlette.responses import (
    FileResponse,
    HTMLResponse,
    JSONResponse,
    PlainTextResponse,
    RedirectResponse,
    Response,
)

# Load .env file (local dev only — Render injects real env vars)
_env_file = Path(__file__).parent / ".env"
if _env_file.exists():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())
from database import init_db, SessionLocal
from models import Server
from routes import router as accounts_router
from routes.servers import router as servers_router
from routes.premium import router as premium_router
from routes.paystack import router as paystack_router
from routes.admin import router as admin_router
from routes.webhooks import router as webhooks_router
from limiter import limiter, _rate_limit_exceeded_handler

# Rate limiter — global

app = FastAPI(
    title="SecureVPN API",
    description="Backend API for SecuredView - Cloudflare WARP VPN client",
    version="1.0.0",
    # No public API surface — /docs, /redoc, /openapi.json would map every
    # endpoint (including admin) for anyone with a browser.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── Security middleware ──────────────────────────────────

# 1. API key middleware — only the official app can call the API
from middleware import ApiKeyMiddleware, APP_API_KEY
app.add_middleware(ApiKeyMiddleware)
# Never log key material (even a prefix) — log files are often shipped.
print("API key loaded")

# 2. CORS: explicit origins, no wildcard + credentials
ENVIRONMENT = os.getenv("ENVIRONMENT", "production")
ALLOWED_ORIGINS = [
    o.strip()
    for o in os.getenv(
        "ALLOWED_ORIGINS",
        "https://securedviewvpn.com,https://www.securedviewvpn.com,"
        "https://meridianglobal.site,https://www.meridianglobal.site,"
        "http://localhost,http://localhost:8080",
    ).split(",")
    if o.strip()
]

if ENVIRONMENT == "development":
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-Api-Key"],
    )

# 3. Request body size limit (1 MB max)
MAX_BODY_SIZE = 1 * 1024 * 1024  # 1 MB


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    transfer_encoding = (request.headers.get("transfer-encoding") or "").lower()
    if "chunked" in transfer_encoding and not content_length:
        # Chunked bodies bypass the size check above (no Content-Length) —
        # demand a declared length instead of reading unbounded.
        return JSONResponse(
            status_code=411,
            content={"detail": "Length Required"},
        )
    try:
        if content_length and int(content_length) > MAX_BODY_SIZE:
            return JSONResponse(
                status_code=413,
                content={"detail": "Request body too large (max 1 MB)"},
            )
    except (ValueError, TypeError):
        return JSONResponse(
            status_code=400,
            content={"detail": "Invalid Content-Length header"},
        )
    return await call_next(request)


# 4. Security headers
@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # HSTS: Render terminates TLS — force https for a year on this host.
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


# ── Routers ──────────────────────────────────────────────
app.include_router(accounts_router)
app.include_router(servers_router)
app.include_router(premium_router)
app.include_router(paystack_router)
app.include_router(admin_router)
app.include_router(webhooks_router)

# ── Website (served from service root; API stays under /api) ──
SITE_DIR = Path(__file__).parent / "static" / "site"
STATIC_DIR = Path(__file__).parent / "static"


def _site_html(filename: str) -> HTMLResponse:
    path = SITE_DIR / filename
    if not path.is_file():
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)
    return HTMLResponse(path.read_text(encoding="utf-8"))


def _redirect(to: str) -> RedirectResponse:
    return RedirectResponse(url=to, status_code=308)


# NOTE: site pages register GET+HEAD — plain @app.get returns 405 for HEAD,
# which some crawlers/link-checkers probe with before fetching.


@app.api_route("/", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_home():
    """Marketing home page (domain root when a custom domain is attached)."""
    return _site_html("index.html")


@app.api_route("/health", methods=["GET", "HEAD"])
@limiter.exempt
def health():
    return {"status": "ok"}


@app.api_route("/apps", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/apps.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_apps():
    return _site_html("apps.html")


@app.api_route("/network", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/network.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_network():
    return _site_html("network.html")


@app.api_route("/pricing", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/free", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/free.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_pricing():
    return _site_html("free.html")


@app.api_route("/privacy", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/privacy.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_privacy():
    return _site_html("privacy.html")


@app.api_route("/terms", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/terms.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def site_terms():
    return _site_html("terms.html")


# CN-reachable download page (Vercel is often RST/reset from mainland China)
@app.api_route("/download", response_class=HTMLResponse, methods=["GET", "HEAD"])
@app.api_route("/download.html", response_class=HTMLResponse, methods=["GET", "HEAD"])
@limiter.exempt
def download_page():
    path = STATIC_DIR / "download.html"
    if not path.exists():
        return HTMLResponse("<h1>Download</h1><p>See GitHub releases</p>", status_code=200)
    return HTMLResponse(path.read_text(encoding="utf-8"))


@app.api_route("/index.html", methods=["GET", "HEAD"])
@limiter.exempt
def site_index_alias():
    return _redirect("/")


# ── Crawler discovery: robots / sitemap / llms / IndexNow ─────────
# Without these, search engines (and ChatGPT search, which rides on Bing)
# have no way to discover or prioritise the site.


def _static_text(rel: str) -> str:
    return (STATIC_DIR / rel).read_text(encoding="utf-8")


@app.api_route("/robots.txt", methods=["GET", "HEAD"], response_class=PlainTextResponse)
@limiter.exempt
def robots_txt():
    return _static_text("robots.txt")


@app.api_route("/sitemap.xml", methods=["GET", "HEAD"])
@limiter.exempt
def sitemap_xml():
    return Response(content=_static_text("sitemap.xml"), media_type="application/xml")


@app.api_route("/llms.txt", methods=["GET", "HEAD"], response_class=PlainTextResponse)
@limiter.exempt
def llms_txt():
    return _static_text("llms.txt")


# Bing Webmaster Tools "XML File" ownership check — file downloaded from Bing,
# must be served from the exact path /BingSiteAuth.xml at the site root.
@app.api_route("/BingSiteAuth.xml", methods=["GET", "HEAD"])
@limiter.exempt
def bing_site_auth():
    return Response(
        content=_static_text("BingSiteAuth.xml"), media_type="application/xml"
    )


@app.api_route(
    "/.well-known/indexnow-key.txt", methods=["GET", "HEAD"], response_class=PlainTextResponse
)
@limiter.exempt
def indexnow_key():
    return _static_text(".well-known/indexnow-key.txt").strip()


# IndexNow Option 1 (docs: "strongly recommended"): key file at the host ROOT.
# keyLocation under /.well-known/ scopes submitted URLs to that path prefix
# only -> submissions for / /apps /pricing... got 422. Must stay LAST so
# specific .txt routes (robots.txt) win the match.
@app.api_route("/{root_key}.txt", methods=["GET", "HEAD"], response_class=PlainTextResponse)
@limiter.exempt
def indexnow_root_key(root_key: str):
    key = _static_text(".well-known/indexnow-key.txt").strip()
    if root_key != key:
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)
    return key


# ── Binary downloads (same host as the site — GitHub asset CDN is GFW-blocked) ──
DOWNLOAD_DIR = STATIC_DIR / "downloads"
DOWNLOAD_FILES = {
    "app-release.apk": "application/vnd.android.package-archive",
    "SecuredView-Windows.zip": "application/zip",
    "SecuredView-Linux.tar.gz": "application/gzip",
}


@app.api_route("/dl/{filename}", methods=["GET", "HEAD"])
@limiter.exempt
def download_binary(filename: str):
    """Serve release binaries from Render.

    GitHub redirects assets to release-assets.githubusercontent.com
    (Azure), which the GFW DNS-pollutes / RSTs from mainland China.
    """
    media = DOWNLOAD_FILES.get(filename)
    if media is None:
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)
    path = DOWNLOAD_DIR / filename
    if not path.is_file():
        return HTMLResponse("<h1>404 Not Found</h1>", status_code=404)
    return FileResponse(
        path,
        media_type=media,
        filename=filename,
        headers={
            "Cache-Control": "public, max-age=86400",
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


# Static site assets (css / img / js)
if (SITE_DIR / "css").is_dir():
    app.mount("/css", StaticFiles(directory=SITE_DIR / "css"), name="css")
if (SITE_DIR / "img").is_dir():
    app.mount("/img", StaticFiles(directory=SITE_DIR / "img"), name="img")
if (SITE_DIR / "js").is_dir():
    app.mount("/js", StaticFiles(directory=SITE_DIR / "js"), name="js")


# ── Seed accounts/devices/subscriptions from seed.json ───
# First boot on an empty Render Postgres: import the exported SQLite snapshot.
import json as _json
from datetime import datetime as _dt
from models import Account, Device, Subscription
from database import SessionLocal as _SeedSession


def _parse_dt(value):
    if value is None or value == "":
        return None
    if isinstance(value, _dt):
        return value
    try:
        return _dt.fromisoformat(str(value))
    except ValueError:
        return None


def seed_from_snapshot():
    """First boot on empty DB: import accounts snapshot.

    Sources (first match): SEED_DATA env (JSON or base64(JSON), for Render), else seed.json (local).
    """
    data = None
    raw_env = os.getenv("SEED_DATA", "").strip()
    if raw_env:
        try:
            data = _json.loads(raw_env)
        except ValueError:
            import base64 as _b64
            try:
                data = _json.loads(_b64.b64decode(raw_env).decode("utf-8"))
            except Exception as e:
                print(f"SEED_DATA invalid (need JSON or base64 JSON): {e}")
                return
    else:
        seed_path = Path(__file__).parent / "seed.json"
        if not seed_path.exists():
            return
        data = _json.loads(seed_path.read_text())
    db = _SeedSession()
    try:
        if db.query(Account).count() > 0:
            return
        for a in data.get("accounts", []):
            db.add(Account(
                id=a["id"],
                pin_hash=a["pin_hash"],
                display_name=a.get("display_name") or "User",
                created_at=_parse_dt(a.get("created_at")),
                is_premium=bool(a.get("is_premium")),
                premium_expires_at=_parse_dt(a.get("premium_expires_at")),
                # Snapshot rows predate the dashboard — they are legacy: no
                # first-login trial arming and no free-tier revival path.
                account_type="legacy",
                trial_eligible=False,
            ))
        db.flush()
        for d in data.get("devices", []):
            db.add(Device(
                account_id=d["account_id"],
                device_id=d["device_id"],
                device_name=d.get("device_name") or "Unknown Device",
                platform=d.get("platform") or "android",
                registered_at=_parse_dt(d.get("registered_at")),
                last_seen=_parse_dt(d.get("last_seen")),
                is_active=bool(d.get("is_active", True)),
            ))
        for s in data.get("subscriptions", []):
            db.add(Subscription(
                account_id=s["account_id"],
                plan=s["plan"],
                days=int(s["days"]),
                amount_usd=float(s["amount_usd"]),
                status=s.get("status") or "active",
                purchased_at=_parse_dt(s.get("purchased_at")),
                expires_at=_parse_dt(s.get("expires_at")),
                payment_ref=s.get("payment_ref"),
            ))
        # servers are seeded by seed_servers() if missing; skip snapshot copy
        db.commit()
        print(f"Seeded snapshot: {len(data.get('accounts', []))} accounts, "
              f"{len(data.get('devices', []))} devices, "
              f"{len(data.get('subscriptions', []))} subscriptions")
    except Exception as e:
        db.rollback()
        print(f"seed_from_snapshot skipped: {e}")
    finally:
        db.close()


# ── Seed servers on first run ────────────────────────────
SEED_SERVERS = [
    {"id": "us-east", "name": "US East", "country": "United States", "country_code": "US", "city": "New York",
     "ip_address": "162.159.192.1", "latitude": 40.7128, "longitude": -74.0060, "tier": "premium", "speed_mbps": 150, "ping_ms": 15},
    {"id": "us-west", "name": "US West", "country": "United States", "country_code": "US", "city": "San Francisco",
     "ip_address": "162.159.193.1", "latitude": 37.7749, "longitude": -122.4194, "tier": "premium", "speed_mbps": 180, "ping_ms": 25},
    {"id": "uk-london", "name": "UK London", "country": "United Kingdom", "country_code": "GB", "city": "London",
     "ip_address": "162.159.194.1", "latitude": 51.5074, "longitude": -0.1278, "tier": "premium", "speed_mbps": 140, "ping_ms": 30},
    {"id": "de-frankfurt", "name": "Germany Frankfurt", "country": "Germany", "country_code": "DE", "city": "Frankfurt",
     "ip_address": "162.159.195.1", "latitude": 50.1109, "longitude": 8.6821, "tier": "premium", "speed_mbps": 160, "ping_ms": 20},
    {"id": "jp-tokyo", "name": "Japan Tokyo", "country": "Japan", "country_code": "JP", "city": "Tokyo",
     "ip_address": "162.159.196.1", "latitude": 35.6762, "longitude": 139.6503, "tier": "premium", "speed_mbps": 170, "ping_ms": 35},
    {"id": "sg-singapore", "name": "Singapore", "country": "Singapore", "country_code": "SG", "city": "Singapore",
     "ip_address": "162.159.197.1", "latitude": 1.3521, "longitude": 103.8198, "tier": "premium", "speed_mbps": 190, "ping_ms": 10},
    {"id": "au-sydney", "name": "Australia Sydney", "country": "Australia", "country_code": "AU", "city": "Sydney",
     "ip_address": "162.159.198.1", "latitude": -33.8688, "longitude": 151.2093, "tier": "premium", "speed_mbps": 130, "ping_ms": 40},
    {"id": "br-saopaulo", "name": "Brazil Sao Paulo", "country": "Brazil", "country_code": "BR", "city": "Sao Paulo",
     "ip_address": "162.159.199.1", "latitude": -23.5505, "longitude": -46.6333, "tier": "premium", "speed_mbps": 110, "ping_ms": 50},
    {"id": "in-mumbai", "name": "India Mumbai", "country": "India", "country_code": "IN", "city": "Mumbai",
     "ip_address": "162.159.200.1", "latitude": 19.0760, "longitude": 72.8777, "tier": "premium", "speed_mbps": 120, "ping_ms": 45},
    {"id": "ca-toronto", "name": "Canada Toronto", "country": "Canada", "country_code": "CA", "city": "Toronto",
     "ip_address": "162.159.201.1", "latitude": 43.6532, "longitude": -79.3832, "tier": "premium", "speed_mbps": 140, "ping_ms": 30},
    {"id": "nl-amsterdam", "name": "Netherlands Amsterdam", "country": "Netherlands", "country_code": "NL", "city": "Amsterdam",
     "ip_address": "162.159.202.1", "latitude": 52.3676, "longitude": 4.9041, "tier": "premium", "speed_mbps": 150, "ping_ms": 25},
    {"id": "kr-seoul", "name": "South Korea Seoul", "country": "South Korea", "country_code": "KR", "city": "Seoul",
     "ip_address": "162.159.203.1", "latitude": 37.5665, "longitude": 126.9780, "tier": "premium", "speed_mbps": 160, "ping_ms": 30},
    {"id": "fr-paris", "name": "France Paris", "country": "France", "country_code": "FR", "city": "Paris",
     "ip_address": "162.159.204.1", "latitude": 48.8566, "longitude": 2.3522, "tier": "premium", "speed_mbps": 150, "ping_ms": 25},
]


def seed_servers():
    db = SessionLocal()
    try:
        count = db.query(Server).count()
        if count == 0:
            for s in SEED_SERVERS:
                db.add(Server(**s))
            db.commit()
            print(f"Seeded {len(SEED_SERVERS)} servers")
        # Product rule: no free tier — force every active server to premium
        free = db.query(Server).filter(Server.tier != "premium").all()
        if free:
            for s in free:
                s.tier = "premium"
            db.commit()
            print(f"Upgraded {len(free)} servers to premium (no free tier)")
        # Ensure the full 13-location catalog exists
        existing = {s.id for s in db.query(Server).all()}
        for s in SEED_SERVERS:
            if s["id"] not in existing:
                db.add(Server(**s))
                print(f"Added missing server {s['id']}")
        db.commit()
    finally:
        db.close()


@app.on_event("startup")
def startup():
    init_db()
    seed_from_snapshot()
    seed_servers()
    # Periodic exact-clock trial expiry (no charging)
    def _trial_sweep_loop():
        import time
        while True:
            try:
                time.sleep(60)
                from billing import sweep_due_accounts
                db = SessionLocal()
                try:
                    n = sweep_due_accounts(db)
                    if n:
                        print(f"trial sweep: expired {n}")
                finally:
                    db.close()
            except Exception as e:
                print(f"trial sweep error: {e}")

    import threading
    threading.Thread(target=_trial_sweep_loop, daemon=True, name="trial-sweep").start()
    print("SecureVPN API ready")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
