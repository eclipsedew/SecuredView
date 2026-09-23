# Render deploy — SecuredView backend (DONE)

Production origin behind `meridianglobal.site` is **Render**, not a quick tunnel.

| Item | Value |
|------|--------|
| Web service | `securedview-api` → **https://securedview-api.onrender.com** |
| Service ID | `srv-dapuotnlk1mc73cvu53g` |
| Postgres | `securedview-db` (free, v17, Oregon) → id `dpg-dapunbhsrm7s73atpv80-a` |
| DB expires | **2026-10-23** (free 30 days + grace) — recreate/switch to Neon before then |
| Owner | `tea-dapoo1ou01pc73de3mu0` (My Workspace) |
| API key file | `~/.render_api_key` (chmod 600; also `/tmp/render_api_key` — may be wiped) |
| Snapshot of IDs | `.render_deploy` (gitignored) |

## Domain cutover (stable — no more tunnel URL churn)

```bash
python3 ~/WarpVPN/scripts/sync_meridian_rewrite.py \
  --origin https://securedview-api.onrender.com \
  --deploy
```

Vercel `meridian-global-education` rewrites:

- `/api/:path*` → `https://securedview-api.onrender.com/api/:path*`
- `/health`, `/docs`, `/openapi.json` → same host

App keeps `https://meridianglobal.site` — **no Flutter change**.

## Env vars already on the service

| Key | Source |
|-----|--------|
| `APP_API_KEY` | matches Flutter (`backend/.app_key`) |
| `SECUREVPN_JWT_SECRET` / admin user+pass | local `.jwt_secret` / `.admin_creds` |
| `PAYSTACK_*` | local `backend/.env` |
| `SEED_DATA` | base64 of `backend/seed.json` (one-time first boot) |
| `DATABASE_URL` | Render Postgres **internal** connection string |
| `ALLOWED_ORIGINS` | meridianglobal.site + localhost |
| `ENVIRONMENT=production`, `PYTHON_VERSION=3.12.8` | fixed |

Verified after first boot: **26 accounts**, 25 devices, 9 servers, admin login 200, `/api/premium/plans` 200.

## Local tunnel (optional only)

`start.sh` still brings up `:8080` + quick tunnel for offline/dev. **Production does not need it.** Do not re-run `sync_meridian_rewrite` with a tunnel origin unless you intentionally abandon Render.

## Notes

- Free Render Postgres **expires ~30 days** after create (`expiresAt` above). Migrate `DATABASE_URL` to Neon free (or recreate + reseed via `SEED_DATA`) before expiry.
- Free web service has **no disk** — always use `DATABASE_URL`, never SQLite, on Render.
- From mainland China, `meridianglobal.site` (Vercel edge) may be reset/blocked on this machine; direct `*.onrender.com` and non-CN networks work.
- Rebuild service payload: see git history / prior `POST /services` flow with `type: web_service`, `envSpecificDetails`, and **real values** on every envVar (no `sync:false`).

## Manual dashboard

- Service: https://dashboard.render.com/web/srv-dapuotnlk1mc73cvu53g  
- Database: https://dashboard.render.com/d/dpg-dapunbhsrm7s73atpv80-a  
