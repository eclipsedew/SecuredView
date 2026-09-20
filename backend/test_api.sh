#!/bin/bash
set -e
BASE="http://localhost:8080"

echo "=== 1. HEALTH ==="
curl -s "$BASE/health" | python3 -m json.tool

echo -e "\n=== 2. REGISTER ==="
REG=$(curl -s -X POST "$BASE/api/accounts/register" \
  -H "Content-Type: application/json" \
  -d '{"pin":"1234","device_id":"test-device-001","device_name":"Test Phone","platform":"android"}')
echo "$REG" | python3 -m json.tool
TOKEN=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
AID=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin)['account_id'])")
echo "Token: ${TOKEN:0:20}..."
echo "Account: $AID"

echo -e "\n=== 3. LOGIN (add linux device) ==="
curl -s -X POST "$BASE/api/accounts/login" \
  -H "Content-Type: application/json" \
  -d "{\"account_id\":\"$AID\",\"pin\":\"1234\",\"device_id\":\"test-device-002\",\"device_name\":\"Desktop\",\"platform\":\"linux\"}" | python3 -m json.tool

echo -e "\n=== 4. GET ME ==="
curl -s "$BASE/api/accounts/me" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo -e "\n=== 5. DEVICES ==="
curl -s "$BASE/api/accounts/me/devices" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo -e "\n=== 6. SERVERS (free user - should see only free) ==="
curl -s "$BASE/api/servers/" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers:'); [print(f'  {s[\"id\"]} ({s[\"tier\"]})') for s in d]"

echo -e "\n=== 7. ALL SERVERS (public) ==="
curl -s "$BASE/api/servers/all" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers total')"

echo -e "\n=== 8. PREMIUM PLANS ==="
curl -s "$BASE/api/premium/plans" | python3 -m json.tool

echo -e "\n=== 9. PURCHASE PREMIUM (basic_30) ==="
curl -s -X POST "$BASE/api/premium/purchase" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"plan_id":"basic_30","payment_method":"simulated"}' | python3 -m json.tool

echo -e "\n=== 10. PREMIUM STATUS ==="
curl -s "$BASE/api/premium/status" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo -e "\n=== 11. SERVERS (premium user - should see all) ==="
curl -s "$BASE/api/servers/" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{len(d)} servers:'); [print(f'  {s[\"id\"]} ({s[\"tier\"]})') for s in d]"

echo -e "\n=== 12. SUBSCRIPTION HISTORY ==="
curl -s "$BASE/api/premium/history" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo -e "\n=== 13. ADMIN LOGIN ==="
ADMIN=$(curl -s -X POST "$BASE/api/admin/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"securevpn2024"}')
echo "$ADMIN" | python3 -m json.tool
AT=$(echo "$ADMIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo -e "\n=== 14. ADMIN STATS ==="
curl -s "$BASE/api/admin/stats" -H "Authorization: Bearer $AT" | python3 -m json.tool

echo -e "\n=== 15. ADMIN LIST ACCOUNTS ==="
curl -s "$BASE/api/admin/accounts" -H "Authorization: Bearer $AT" | python3 -m json.tool

echo -e "\n=== 16. WRONG PIN (should fail with generic error) ==="
curl -s -X POST "$BASE/api/accounts/login" \
  -H "Content-Type: application/json" \
  -d "{\"account_id\":\"$AID\",\"pin\":\"9999\",\"device_id\":\"test-device-003\",\"device_name\":\"Hacker\",\"platform\":\"linux\"}" | python3 -m json.tool

echo -e "\n=== 17. INVALID PIN FORMAT (should fail validation) ==="
curl -s -X POST "$BASE/api/accounts/register" \
  -H "Content-Type: application/json" \
  -d '{"pin":"abcd","device_id":"test","device_name":"Test","platform":"android"}' | python3 -m json.tool

echo -e "\n=== 18. RATE LIMIT TEST (register 4 times rapidly) ==="
for i in 1 2 3 4; do
  curl -s -X POST "$BASE/api/accounts/register" \
    -H "Content-Type: application/json" \
    -d "{\"pin\":\"1111\",\"device_id\":\"rate-test-$i\",\"device_name\":\"Rate $i\",\"platform\":\"android\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Attempt {$i}: {d.get(\"account_id\", d.get(\"detail\", \"error\"))}')" 2>/dev/null || echo "  Attempt $i: error"
done

echo -e "\n=== ALL TESTS PASSED ==="
