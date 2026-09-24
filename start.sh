# Start local SecuredView backend (+ optional Cloudflare tunnel).
# Production: securedviewvpn.com → Render (custom domain). Fallback: securedview-api.onrender.com.
# SKIP_VERCEL_SYNC defaults to 1 so start.sh never rewrites the domain to a tunnel.
set -u
BACKEND_DIR="${BACKEND_DIR:-$HOME/WarpVPN/backend}"
SKIP_VERCEL_SYNC="${SKIP_VERCEL_SYNC:-1}"  # production: domain already on Render
CF_BIN="${CF_BIN:-/tmp/cloudflared}"
TUN_OUT="${TUN_OUT:-/tmp/cloudflared.out}"
URL_FILE="${URL_FILE:-/tmp/current_tunnel_url}"

# Backend on :8080 only (skip ollama's :8000)
if ! curl -sf -m 2 http://127.0.0.1:8080/health >/dev/null; then
  echo "starting backend :8080"
  cd "$BACKEND_DIR" || exit 1
  # shellcheck disable=SC1091
  source venv/bin/activate
  setsid nohup python -m uvicorn main:app --host 0.0.0.0 --port 8080 \
    >>/tmp/backend.log 2>&1 < /dev/null &
  disown
  for i in $(seq 1 20); do
    sleep 1
    curl -sf -m 2 http://127.0.0.1:8080/health >/dev/null && break
  done
fi

# Optional local quick tunnel (dev only). Production does not need it.
if [ "${START_TUNNEL:-0}" = "1" ]; then
  if [ ! -x "$CF_BIN" ]; then
    mkdir -p "$(dirname "$CF_BIN")"
    if [ -x "$HOME/LabImplant/tools/tunnel/cloudflared" ]; then
      cp -f "$HOME/LabImplant/tools/tunnel/cloudflared" "$CF_BIN"
      chmod +x "$CF_BIN"
    else
      echo "cloudflared binary missing" >&2
      exit 1
    fi
  fi
  if pgrep -f "$CF_BIN tunnel" >/dev/null; then
    pkill -f "$CF_BIN tunnel" || true
    sleep 1
  fi
  : > "$TUN_OUT"
  echo "starting cloudflared → $TUN_OUT"
  setsid nohup "$CF_BIN" tunnel --url http://localhost:8080 --protocol http2 \
    >"$TUN_OUT" 2>&1 < /dev/null &
  disown
  TUN=""
  for i in $(seq 1 30); do
    sleep 2
    TUN=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUN_OUT" 2>/dev/null | head -1 || true)
    if [ -n "${TUN:-}" ]; then
      printf '%s\n' "$TUN" > "$URL_FILE"
      echo "TUNNEL=$TUN"
      curl -sf -m 10 "$TUN/health" && echo
      if [ "${SKIP_VERCEL_SYNC:-1}" = "0" ]; then
        python3 "$HOME/WarpVPN/scripts/sync_meridian_rewrite.py" --deploy || \
          echo "vercel rewrite sync failed (non-fatal)" >&2
      else
        echo "SKIP_VERCEL_SYNC=1 — meridianglobal.site stays optional; primary is securedviewvpn.com"
      fi
      exit 0
    fi
    if ! pgrep -f "$CF_BIN tunnel" >/dev/null; then
      echo "cloudflared exited early:" >&2
      tail -30 "$TUN_OUT" >&2
      exit 1
    fi
  done
  echo "timed out waiting for tunnel URL" >&2
  tail -40 "$TUN_OUT" >&2
  exit 1
fi

echo "backend only (START_TUNNEL=0). Production: securedviewvpn.com → Render."
exit 0
