#!/usr/bin/env bash
# End-to-end smoke test for core-api.
API=http://localhost:8080
pass=0; fail=0
j() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
check() { # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1));
  else echo "  FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

SUF=$RANDOM
echo "=== registration ==="
ALICE=$(curl -s -X POST $API/auth/register -H 'content-type: application/json' \
  -d "{\"handle\":\"alice$SUF\",\"email\":\"alice$SUF@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"Alice\"}")
A_ACCESS=$(echo "$ALICE" | j "['access_token']"); A_REFRESH=$(echo "$ALICE" | j "['refresh_token']")
A_ID=$(echo "$ALICE" | j "['user']['id']")
check "register returns access token" "$([ -n "$A_ACCESS" ] && echo yes)" "yes"

BOB=$(curl -s -X POST $API/auth/register -H 'content-type: application/json' \
  -d "{\"handle\":\"bob$SUF\",\"email\":\"bob$SUF@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"Bob\"}")
B_ACCESS=$(echo "$BOB" | j "['access_token']"); B_ID=$(echo "$BOB" | j "['user']['id']")

check "duplicate handle rejected" \
  "$(code -X POST $API/auth/register -H 'content-type: application/json' \
     -d "{\"handle\":\"alice$SUF\",\"email\":\"other$SUF@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"X\"}")" "409"
check "short password rejected" \
  "$(code -X POST $API/auth/register -H 'content-type: application/json' \
     -d "{\"handle\":\"zed$SUF\",\"email\":\"z$SUF@example.com\",\"password\":\"short\",\"display_name\":\"Z\"}")" "400"
check "bad handle charset rejected" \
  "$(code -X POST $API/auth/register -H 'content-type: application/json' \
     -d "{\"handle\":\"has spaces\",\"email\":\"q$SUF@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"Q\"}")" "400"

echo "=== access control ==="
check "/auth/me with token"    "$(code $API/auth/me -H "authorization: Bearer $A_ACCESS")" "200"
check "/auth/me without token" "$(code $API/auth/me)" "401"
check "/auth/me garbage token" "$(code $API/auth/me -H 'authorization: Bearer not.a.jwt')" "401"
check "wrong password"         "$(code -X POST $API/auth/login -H 'content-type: application/json' \
     -d "{\"handle\":\"alice$SUF\",\"password\":\"wrong-password-here\"}")" "401"
check "unknown user"           "$(code -X POST $API/auth/login -H 'content-type: application/json' \
     -d "{\"handle\":\"ghost$SUF\",\"password\":\"correct-horse-battery\"}")" "401"

echo "=== refresh rotation + reuse detection ==="
R1=$(curl -s -X POST $API/auth/refresh -H 'content-type: application/json' -d "{\"refresh_token\":\"$A_REFRESH\"}")
A_REFRESH2=$(echo "$R1" | j "['refresh_token']")
check "refresh returns a NEW token" "$([ -n "$A_REFRESH2" ] && [ "$A_REFRESH2" != "$A_REFRESH" ] && echo yes)" "yes"
check "rotated token works"         "$(code -X POST $API/auth/refresh -H 'content-type: application/json' -d "{\"refresh_token\":\"$A_REFRESH2\"}")" "200"
# The critical one: replaying the ORIGINAL (already consumed) token.
check "REUSE of consumed token rejected" \
  "$(code -X POST $API/auth/refresh -H 'content-type: application/json' -d "{\"refresh_token\":\"$A_REFRESH\"}")" "401"
# ...and that reuse must have burned the whole family, including the newest token.
R3=$(curl -s -X POST $API/auth/refresh -H 'content-type: application/json' -d "{\"refresh_token\":\"$A_REFRESH2\"}" -o /dev/null -w '%{http_code}')
check "REUSE revokes the entire family" "$R3" "401"

echo "=== catches + geo ==="
# Alice re-logs in after her family was burned.
ALICE2=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' \
  -d "{\"handle\":\"alice$SUF\",\"password\":\"correct-horse-battery\"}")
A_ACCESS=$(echo "$ALICE2" | j "['access_token']")
mk() { curl -s -o /dev/null -w '%{http_code}' -X POST $API/catches -H "authorization: Bearer $A_ACCESS" \
       -H 'content-type: application/json' -d "$1"; }
check "create catch (UCSD)" "$(mk '{"species_key":"squirrel","caught_at":"2026-09-01T10:00:00Z","lat":32.8801,"lng":-117.2340,"confidence":0.91}')" "200"
check "create catch (700m away)" "$(mk '{"species_key":"owl","caught_at":"2026-09-01T11:00:00Z","lat":32.8850,"lng":-117.2400}')" "200"
check "create catch (LA, 180km)" "$(mk '{"species_key":"frog","caught_at":"2026-09-01T12:00:00Z","lat":34.0522,"lng":-118.2437}')" "200"
check "catch with no location ok" "$(mk '{"species_key":"moth","caught_at":"2026-09-01T13:00:00Z"}')" "200"
check "half a coordinate rejected" "$(mk '{"species_key":"bee","caught_at":"2026-09-01T13:00:00Z","lat":32.0}')" "400"
check "out-of-range latitude rejected" "$(mk '{"species_key":"bee","caught_at":"2026-09-01T13:00:00Z","lat":991.0,"lng":0.0}')" "400"
check "catches require auth" "$(code $API/catches/me)" "401"

N=$(curl -s "$API/catches/nearby?lat=32.8801&lng=-117.2340&radius_m=2000" -H "authorization: Bearer $A_ACCESS")
check "nearby 2km returns 2 (excludes LA)" "$(echo "$N" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" "2"
NW=$(curl -s "$API/catches/nearby?lat=32.8801&lng=-117.2340&radius_m=999999999" -H "authorization: Bearer $A_ACCESS")
check "radius clamped to 50km (LA still excluded)" "$(echo "$NW" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" "2"

echo "=== friends authorization ==="
check "non-friend blocked from dex" "$(code $API/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "403"
check "bob requests alice" "$(code -X POST $API/friends/request -H "authorization: Bearer $B_ACCESS" \
   -H 'content-type: application/json' -d "{\"handle\":\"alice$SUF\"}")" "200"
check "still blocked while pending" "$(code $API/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "403"
check "requester cannot self-accept" "$(code -X POST $API/friends/$A_ID/accept -H "authorization: Bearer $B_ACCESS")" "404"
check "alice accepts" "$(code -X POST $API/friends/$B_ID/accept -H "authorization: Bearer $A_ACCESS")" "204"
check "friend CAN read dex now" "$(code $API/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "200"
D=$(curl -s $API/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")
check "dex shows 4 distinct species" "$(echo "$D" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" "4"
check "cannot befriend yourself" "$(code -X POST $API/friends/request -H "authorization: Bearer $A_ACCESS" \
   -H 'content-type: application/json' -d "{\"handle\":\"alice$SUF\"}")" "400"

echo "=== logout ==="
L=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' -d "{\"handle\":\"bob$SUF\",\"password\":\"correct-horse-battery\"}")
L_REFRESH=$(echo "$L" | j "['refresh_token']")
check "logout succeeds" "$(code -X POST $API/auth/logout -H 'content-type: application/json' -d "{\"refresh_token\":\"$L_REFRESH\"}")" "204"
check "revoked token cannot refresh" "$(code -X POST $API/auth/refresh -H 'content-type: application/json' -d "{\"refresh_token\":\"$L_REFRESH\"}")" "401"

echo
echo "======================================"
echo "  $pass passed, $fail failed"
echo "======================================"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
