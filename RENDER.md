# Render deploy — SecuredView backend (DONE)

Production is **Render** for the whole site + API. Primary host is the custom domain **`https://securedviewvpn.com`** (Cloudflare-fronted, reachable from mainland CN). `meridianglobal.site` (Vercel) is legacy fallback only.

| Item | Value |
|------|--------|
| Primary URL | **https://securedviewvpn.com** (custom domain on Render) |
| Web service | `securedview-api` → https://securedview-api.onrender.com (still enabled as fallback) |
| Service ID | `srv-dapuotnlk1mc73cvu53g` |
| Custom domains | apex `securedviewvpn.com` + `www` (auto-pair), status must be **verified** |
| Postgres | `securedview-db` (free, v17, Oregon) → id `dpg-dapunbhsrm7s73atpv80-a` |
| DB expires | **2026-10-23** (free 30 days + grace) — recreate/switch to Neon before then |
| Owner | `tea-dapoo1ou01pc73de3mu0` (My Workspace) |
| API key file | `~/.render_api_key` (chmod 600; also `/tmp/render_api_key` — may be wiped) |
| Snapshot of IDs | `.render_deploy` (gitignored) |

## Custom domain DNS (Namecheap)

Nameservers already `dns1/dns2.registrar-servers.com`. In **Domain → Manage → Advanced DNS**:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A | `@` | `216.24.57.1` | 1 min |
| CNAME | `www` | `securedview-api.onrender.com` | 1 min |

Remove any existing A/AAAA for `@`, CNAME/redirect/parking for `www`, and **all AAAA** records. Then verify:

```bash
RENDER_KEY=$(cat ~/.render_api_key)
curl -X POST -H "Authorization: Bearer $RENDER_KEY" \
  "https://api.render.com/v1/services/srv-dapuotnlk1mc73cvu53g/custom-domains/securedviewvpn.com/verify"
curl -X POST -H "Authorization: Bearer $RENDER_KEY" \
  "https://api.render.com/v1/services/srv-dapuotnlk1mc73cvu53g/custom-domains/www.securedviewvpn.com/verify"
# list → verificationStatus should become "verified" after DNS propagates
```

Render issues TLS automatically after verify. App `apiBases` prefers `https://securedviewvpn.com`.

## Legacy Vercel rewrites (optional)

```bash
python3 ~/WarpVPN/scripts/sync_meridian_rewrite.py \
  --origin https://securedview-api.onrender.com \
  --deploy
```

Only needed if you still want `meridianglobal.site` as a CORS/API fallback. Mainland CN often RSTs Vercel — do not make it primary.

## Env vars already on the service

| Key | Source |
|-----|--------|
| `APP_API_KEY` | matches Flutter (`backend/.app_key`) |
| `SECUREVPN_JWT_SECRET` / admin user+pass | local `.jwt_secret` / `.admin_creds` |
| `PAYSTACK_*` | local `backend/.env` |
| `SEED_DATA` | base64 of `backend/seed.json` (one-time first boot) |
| `DATABASE_URL` | Render Postgres **internal** connection string |
| `ALLOWED_ORIGINS` | securedviewvpn.com + www + meridianglobal + localhost |
| `ENVIRONMENT=production`, `PYTHON_VERSION=3.12.8` | fixed |

Verified after first boot: **26 accounts**, 25 devices, 9 servers, admin login 200, `/api/premium/plans` 200.

## Local tunnel (optional only)

`start.sh` still brings up `:8080` + quick tunnel for offline/dev. **Production does not need it.** Do not re-run `sync_meridian_rewrite` with a tunnel origin unless you intentionally abandon Render.

## Notes

- Free Render Postgres **expires ~30 days** after create (`expiresAt` above). Migrate `DATABASE_URL` to Neon free (or recreate + reseed via `SEED_DATA`) before expiry.
- Free web service has **no disk** — always use `DATABASE_URL`, never SQLite, on Render.
- From mainland China, prefer `https://securedviewvpn.com` (Render + Cloudflare). `meridianglobal.site` (Vercel) may be reset; `*.onrender.com` also works but is not the public brand URL.
- Rebuild service payload: see git history / prior `POST /services` flow with `type: web_service`, `envSpecificDetails`, and **real values** on every envVar (no `sync:false`).

## Manual dashboard

- Service: https://dashboard.render.com/web/srv-dapuotnlk1mc73cvu53g  
- Database: https://dashboard.render.com/d/dpg-dapunbhsrm7s73atpv80-a  
