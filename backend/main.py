"""SecureVPN Backend - FastAPI application."""
import os
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# Load .env file
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

# Rate limiter
limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="SecureVPN API",
    description="Backend API for SecureVPN - Cloudflare WARP VPN client",
    version="1.0.0",
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS: explicit origins, no wildcard + credentials
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost,http://localhost:8080").split(",")

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
        allow_headers=["Authorization", "Content-Type"],
    )

app.include_router(accounts_router)
app.include_router(servers_router)
app.include_router(premium_router)
app.include_router(paystack_router)
app.include_router(admin_router)


@app.get("/")
@limiter.exempt
def root():
    return {"name": "SecureVPN API", "version": "1.0.0", "status": "running"}


@app.get("/health")
@limiter.exempt
def health():
    return {"status": "ok"}


# Seed servers on first run
SEED_SERVERS = [
    {"id": "us-east", "name": "US East", "country": "United States", "country_code": "US", "city": "New York",
     "ip_address": "162.159.192.1", "latitude": 40.7128, "longitude": -74.0060, "tier": "free", "speed_mbps": 150, "ping_ms": 15},
    {"id": "us-west", "name": "US West", "country": "United States", "country_code": "US", "city": "San Francisco",
     "ip_address": "162.159.193.1", "latitude": 37.7749, "longitude": -122.4194, "tier": "premium", "speed_mbps": 180, "ping_ms": 25},
    {"id": "uk-london", "name": "UK London", "country": "United Kingdom", "country_code": "GB", "city": "London",
     "ip_address": "162.159.194.1", "latitude": 51.5074, "longitude": -0.1278, "tier": "premium", "speed_mbps": 140, "ping_ms": 30},
    {"id": "de-frankfurt", "name": "Germany Frankfurt", "country": "Germany", "country_code": "DE", "city": "Frankfurt",
     "ip_address": "162.159.195.1", "latitude": 50.1109, "longitude": 8.6821, "tier": "premium", "speed_mbps": 160, "ping_ms": 20},
    {"id": "jp-tokyo", "name": "Japan Tokyo", "country": "Japan", "country_code": "JP", "city": "Tokyo",
     "ip_address": "162.159.196.1", "latitude": 35.6762, "longitude": 139.6503, "tier": "free", "speed_mbps": 170, "ping_ms": 35},
    {"id": "sg-singapore", "name": "Singapore", "country": "Singapore", "country_code": "SG", "city": "Singapore",
     "ip_address": "162.159.197.1", "latitude": 1.3521, "longitude": 103.8198, "tier": "premium", "speed_mbps": 190, "ping_ms": 10},
    {"id": "au-sydney", "name": "Australia Sydney", "country": "Australia", "country_code": "AU", "city": "Sydney",
     "ip_address": "162.159.198.1", "latitude": -33.8688, "longitude": 151.2093, "tier": "premium", "speed_mbps": 130, "ping_ms": 40},
    {"id": "br-saopaulo", "name": "Brazil Sao Paulo", "country": "Brazil", "country_code": "BR", "city": "Sao Paulo",
     "ip_address": "162.159.199.1", "latitude": -23.5505, "longitude": -46.6333, "tier": "premium", "speed_mbps": 110, "ping_ms": 50},
    {"id": "in-mumbai", "name": "India Mumbai", "country": "India", "country_code": "IN", "city": "Mumbai",
     "ip_address": "162.159.200.1", "latitude": 19.0760, "longitude": 72.8777, "tier": "premium", "speed_mbps": 120, "ping_ms": 45},
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
    finally:
        db.close()


@app.on_event("startup")
def startup():
    init_db()
    seed_servers()
    print("SecureVPN API ready")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
