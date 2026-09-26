"""Client IP resolution that works behind Render's reverse proxy.

uvicorn's proxy-headers only trust loopback peers, so on Render
``request.client`` is the shared router IP (every user in one bucket).
Render's edge appends the real client IP to ``X-Forwarded-For`` — take the
LAST hop (written by the proxy, unspoofable from outside) and never index 0
(clients can prepend fake entries).
"""


def client_ip(request) -> str:
    if request is None:
        return "unknown"
    xff = request.headers.get("x-forwarded-for") or ""
    if xff:
        last = xff.split(",")[-1].strip()
        if last:
            return last
    xr = (request.headers.get("x-real-ip") or "").strip()
    if xr:
        return xr
    try:
        return request.client.host if request.client else "unknown"
    except Exception:
        return "unknown"
