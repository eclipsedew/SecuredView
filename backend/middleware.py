"""API key middleware — only the official app can call the API."""
import os
import secrets
from pathlib import Path
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

# Load app key from file (persists across restarts)
_key_file = Path(__file__).parent / ".app_key"
if _key_file.exists():
    APP_API_KEY = _key_file.read_text().strip()
else:
    APP_API_KEY = secrets.token_hex(32)
    _key_file.write_text(APP_API_KEY)

# Paths that don't require API key (public)
PUBLIC_PATHS = {
    "/",
    "/health",
    "/docs",
    "/openapi.json",
    "/redoc",
    "/api/servers/all",
}


class ApiKeyMiddleware(BaseHTTPMiddleware):
    """Validates X-Api-Key header on all requests except public paths."""

    async def dispatch(self, request: Request, call_next):
        path = request.url.path

        # Skip API key check for public paths
        if path in PUBLIC_PATHS or path.startswith("/docs") or path.startswith("/openapi") or path.startswith("/redoc"):
            return await call_next(request)

        # Skip for Paystack webhook (Paystack can't send our custom header)
        if path.startswith("/api/webhooks"):
            return await call_next(request)

        # Check API key
        api_key = request.headers.get("X-Api-Key")
        if not api_key or not secrets.compare_digest(api_key, APP_API_KEY):
            return JSONResponse(
                status_code=403,
                content={"detail": "Invalid or missing API key"},
            )

        return await call_next(request)
