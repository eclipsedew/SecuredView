# Render environment (paste into Dashboard → Environment)

Required after Blueprint deploy (Environment tab of `securedview-api`):

| Key | Value |
| --- | --- |
| `PAYSTACK_SECRET_KEY` | from local `backend/.env` |
| `PAYSTACK_PUBLIC_KEY` | from local `backend/.env` |
| `SEED_DATA` | base64 of `backend/seed.json` (one-time first boot). Generate: `base64 -w0 backend/seed.json` |

Already set by `render.yaml` (do not paste secrets into git):

- `APP_API_KEY` (matches the Flutter app)
- `SECUREVPN_JWT_SECRET` (generated)
- `SECUREVPN_ADMIN_USER` / `SECUREVPN_ADMIN_PASS` (generated — copy from Dashboard)
- `ENVIRONMENT=production`
- `DATABASE_URL` (from Render Postgres)

## First deploy

1. Render → **New +** → **Blueprint** → connect `eclipsedew/SecuredView`
2. Render reads `render.yaml` → creates web service + free Postgres
3. Set `PAYSTACK_*` and `SEED_DATA` env vars (see above)
4. Deploy → note service URL `https://securedview-api-xxxx.onrender.com`
5. Point the education site at it:

```bash
python3 ~/WarpVPN/scripts/sync_meridian_rewrite.py \
  --origin https://securedview-api-xxxx.onrender.com \
  --deploy
```

App keeps using `https://meridianglobal.site` — no Flutter change.

## Notes

- Free Render Postgres **expires after 30 days** (14-day grace). For a permanent free DB, replace `DATABASE_URL` with a Neon/Supabase free Postgres URL (same env key).
- Free web services have no persistent disk — SQLite on Render will not survive restarts. Always use `DATABASE_URL`.
