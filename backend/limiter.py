"""Shared rate limiter instance for all routes."""
from slowapi import Limiter, _rate_limit_exceeded_handler  # noqa: F401  (re-export)

from clientip import client_ip

# Key on the proxy-attested client IP (last X-Forwarded-For hop), NOT
# request.client — behind Render's router that would put every user in one
# shared bucket, letting 10 bad logins anywhere lock out everyone.
limiter = Limiter(key_func=client_ip)
