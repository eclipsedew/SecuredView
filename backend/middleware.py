"""API key middleware — only the official app can call the API."""
import os
import secrets
from pathlib import Path
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

# Prefer env (Render/Vercel); fall back to local .app_key for dev.
_env_key = (os.getenv("APP_API_KEY") or "").strip()
_key_file = Path(__file__).parent / ".app_key"
if _env_key:
    APP_API_KEY = _env_key
elif _key_file.exists():
    APP_API_KEY = _key_file.read_text().strip()
else:
    APP_API_KEY = secrets.token_hex(32)
    try:
        _key_file.write_text(APP_API_KEY)
    except OSError:
        pass

# Public API paths (website pages/assets are public by default — see middleware)
# NOTE: FastAPI docs (/docs, /redoc, /openapi.json) are disabled at app
# construction — they are not API paths and must never be listed as public.
PUBLIC_PATHS = {
    "/",
    "/health",
    "/download",
    "/api/servers/all",
    "/api/premium/plans",
}


class ApiKeyMiddleware(BaseHTTPMiddleware):
    """Require X-Api-Key on /api/* except public endpoints and webhooks.

    The marketing website (/, /apps, /network, /pricing, /privacy, /terms,
    /download, /css, /img, /js, docs) is intentionally public so a future
    domain can serve the whole site from this service root.
    """

    async def dispatch(self, request: Request, call_next):
        path = request.url.path

        # Website, static assets, health, OpenAPI docs — always public
        if not (path == "/api" or path.startswith("/api/")):
            return await call_next(request)

        # Explicit public API endpoints
        if path in PUBLIC_PATHS:
            return await call_next(request)

        # Paystack webhook cannot send our custom header
        if path.startswith("/api/webhooks"):
            return await call_next(request)

        api_key = request.headers.get("X-Api-Key")
        if not api_key or not secrets.compare_digest(api_key, APP_API_KEY):
            return JSONResponse(
                status_code=403,
                content={"detail": "Invalid or missing API key"},
            )

        return await call_next(request)
