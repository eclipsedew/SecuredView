#!/usr/bin/env python3
"""Point meridianglobal.site API rewrites at a backend origin.

Default origin: current Cloudflare quick-tunnel URL.
Override with --origin https://xxx.onrender.com (Render) or ORIGIN env.
Run after cloudflared restarts (tunnel hostname changes every time).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path.home() / "Projects" / "meridian-global-education"
VERCEL_JSON = PROJECT / "vercel.json"
URL_FILE = Path(os.environ.get("URL_FILE", "/tmp/current_tunnel_url"))
TUN_OUT = Path(os.environ.get("TUN_OUT", "/tmp/cloudflared.out"))
API_PATHS = ("/api/", "/health", "/docs", "/openapi.json")


def origin_from_args() -> str:
    # --origin URL or ORIGIN env
    args = sys.argv[1:]
    if "--origin" in args:
        i = args.index("--origin")
        if i + 1 >= len(args):
            sys.exit("--origin requires a value")
        return args[i + 1].rstrip("/")
    if os.environ.get("ORIGIN"):
        return os.environ["ORIGIN"].rstrip("/")
    for candidate in (URL_FILE, TUN_OUT):
        if not candidate.exists():
            continue
        text = candidate.read_text(errors="ignore")
        m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", text)
        if m:
            return m.group(0).rstrip()
    sys.exit("no origin: pass --origin https://....onrender.com or start tunnel")


def main() -> None:
    origin = origin_from_args()
    data = json.loads(VERCEL_JSON.read_text())
    rewrites = []
    # /api/:path* needs the wildcard path segment
    rewrites.append(
        {
            "source": "/api/:path*",
            "destination": f"{origin}/api/:path*",
        }
    )
    for p in ("/health", "/docs", "/openapi.json"):
        rewrites.append({"source": p, "destination": f"{origin}{p}"})
    # Preserve any non-API rewrites already present
    existing = [
        r
        for r in data.get("rewrites", [])
        if r.get("source") not in {"/api/:path*", "/health", "/docs", "/openapi.json"}
    ]
    data["rewrites"] = existing + rewrites
    VERCEL_JSON.write_text(json.dumps(data, indent=2) + "\n")
    print(f"rewrites → {origin}")

    if "--deploy" in sys.argv:
        subprocess.run(
            ["vercel", "--prod", "--yes"],
            cwd=PROJECT,
            check=True,
        )
        print("deployed meridianglobal.site")


if __name__ == "__main__":
    main()
