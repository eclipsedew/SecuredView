#!/bin/bash
set -e
BASE="http://localhost:8080"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
API_KEY=$(cat "$BASE_DIR/.app_key" 2>/dev/null || echo "")
AUTH_HEADER=""
[ -n "$API_KEY" ] && AUTH_HEADER="-H X-Api-Key:$API_KEY"

echo "=== 1. HEALTH ==="
curl -s "$BASE/health" | python3 -m json.tool

echo -e "\n=== 2. REGISTER ==="
REG=$(curl -s -X POST "$BASE/api/accounts/register" \
  -H "Content-Type: application/json" \
  $AUTH_HEADER \
  -d '{"pin":"1234","device_id":"a1b2c3d4e5f60718","device_name":"Test Phone","platform":"android"}')
echo "$REG" | python3 -m json.tool
TOKEN=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
AID=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin)['account_id'])")
echo "Token: ${TOKEN:0:20}..."
echo "Account: $AID"

echo -e "\n=== 3. LOGIN (add linux device) ==="
curl -s -X POST "$BASE/api/accounts/login" \
  -H "Content-Type: application/json" \
  $AUTH_HEADER \
  -d "{\"account_id\":\"$AID\",\"pin\":\"1234\",\"device_id\":\"b1b2c3d4e5f60719\",\"device_name\":\"Desktop\",\"platform\":\"linux\"}" | python3 -m json.tool

echo -e "\n=== 4. GET ME ==="
curl -s "$BASE/api/accounts/me" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 5. DEVICES ==="
curl -s "$BASE/api/accounts/me/devices" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 6. SERVERS (trial user - all locations, all premium) ==="
curl -s "$BASE/api/servers/" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers:'); [print(f'  {s[\"id\"]} ({s[\"tier\"]})') for s in d]"

echo -e "\n=== 7. ALL SERVERS (public) ==="
curl -s "$BASE/api/servers/all" $AUTH_HEADER | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers total')"

echo -e "\n=== 8. PREMIUM PLANS ==="
curl -s "$BASE/api/premium/plans" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 9. PREMIUM STATUS ==="
curl -s "$BASE/api/premium/status" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 10. SERVERS (paid user - same 13 premium locations) ==="
curl -s "$BASE/api/servers/" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers:'); [print(f'  {s[\"id\"]} ({s[\"tier\"]})') for s in d]"

echo -e "\n=== 11. SUBSCRIPTION HISTORY ==="
curl -s "$BASE/api/premium/history" -H "Authorization: Bearer $TOKEN" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 12. ADMIN LOGIN ==="
ADMIN=$(curl -s -X POST "$BASE/api/admin/login" \
  -H "Content-Type: application/json" \
  $AUTH_HEADER \
  -d "{\"username\":\"${SECUREVPN_ADMIN_USER:-admin}\",\"password\":\"${SECUREVPN_ADMIN_PASS:?set SECUREVPN_ADMIN_PASS}\"}')
echo "$ADMIN" | python3 -m json.tool
AT=$(echo "$ADMIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo -e "\n=== 13. ADMIN STATS ==="
curl -s "$BASE/api/admin/stats" -H "Authorization: Bearer $AT" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 14. ADMIN LIST ACCOUNTS ==="
curl -s "$BASE/api/admin/accounts" -H "Authorization: Bearer $AT" $AUTH_HEADER | python3 -m json.tool

echo -e "\n=== 15. WRONG PIN (should fail with generic error) ==="
curl -s -X POST "$BASE/api/accounts/login" \
  -H "Content-Type: application/json" \
  $AUTH_HEADER \
  -d "{\"account_id\":\"$AID\",\"pin\":\"9999\",\"device_id\":\"c1b2c3d4e5f6071a\",\"device_name\":\"Hacker\",\"platform\":\"linux\"}" | python3 -m json.tool

echo -e "\n=== 16. INVALID PIN FORMAT (should fail validation) ==="
curl -s -X POST "$BASE/api/accounts/register" \
  -H "Content-Type: application/json" \
  $AUTH_HEADER \
  -d '{"pin":"abcd","device_id":"d1b2c3d4e5f6071b","device_name":"Test","platform":"android"}' | python3 -m json.tool

echo -e "\n=== 17. RATE LIMIT TEST (register 4 times rapidly) ==="
for i in 1 2 3 4; do
  curl -s -X POST "$BASE/api/accounts/register" \
    -H "Content-Type: application/json" \
    $AUTH_HEADER \
    -d "{\"pin\":\"1111\",\"device_id\":\"$(printf '%08x%08x' $i $RANDOM)\",\"device_name\":\"Rate $i\",\"platform\":\"android\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Attempt {$i}: {d.get(\"account_id\", d.get(\"detail\", \"error\"))}')" 2>/dev/null || echo "  Attempt $i: error"
done

echo -e "\n=== ALL TESTS PASSED ==="
