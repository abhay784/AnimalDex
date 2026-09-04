#!/usr/bin/env bash
# End-to-end smoke test for the AnimalDex backend.
#
# Payloads are always assigned to a variable before use. Inlining them as
# "$(post "{\"a\":1}")" makes bash mis-handle the nested quoting and silently
# hands the function fragments of the JSON instead of the whole document.
CORE=${CORE:-http://localhost:8080}
MEDIA=${MEDIA:-http://localhost:8081}
pass=0; fail=0
j(){ python3 -c "import sys,json;print(json.load(sys.stdin)$1)" 2>/dev/null; }
len(){ python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null; }
check(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1));
         else echo "  FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }
code(){ curl -s -o /dev/null -w '%{http_code}' "$@"; }
post(){ curl -s -o /dev/null -w '%{http_code}' -X POST "$1" -H 'content-type: application/json' -d "$2"; }
auth_post(){ curl -s -o /dev/null -w '%{http_code}' -X POST "$1" -H "authorization: Bearer $2" -H 'content-type: application/json' -d "$3"; }

S=$RANDOM$$
reg(){ # reg <handle>
  local body="{\"handle\":\"$1\",\"email\":\"$1@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"$1\"}"
  curl -s -X POST $CORE/auth/register -H 'content-type: application/json' -d "$body"
}

echo "=== registration ==="
ALICE=$(reg "alice$S"); A_ACCESS=$(echo "$ALICE" | j "['access_token']")
A_REFRESH=$(echo "$ALICE" | j "['refresh_token']"); A_ID=$(echo "$ALICE" | j "['user']['id']")
BOB=$(reg "bob$S"); B_ACCESS=$(echo "$BOB" | j "['access_token']"); B_ID=$(echo "$BOB" | j "['user']['id']")
check "register returns access token" "$([ -n "$A_ACCESS" ] && echo yes)" "yes"

DUP="{\"handle\":\"alice$S\",\"email\":\"other$S@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"X\"}"
check "duplicate handle rejected" "$(post $CORE/auth/register "$DUP")" "409"
SHORT="{\"handle\":\"zed$S\",\"email\":\"z$S@example.com\",\"password\":\"short\",\"display_name\":\"Z\"}"
check "short password rejected" "$(post $CORE/auth/register "$SHORT")" "400"
BADH="{\"handle\":\"has spaces\",\"email\":\"q$S@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"Q\"}"
check "bad handle charset rejected" "$(post $CORE/auth/register "$BADH")" "400"

echo "=== access control ==="
check "/auth/me with token"    "$(code $CORE/auth/me -H "authorization: Bearer $A_ACCESS")" "200"
check "/auth/me without token" "$(code $CORE/auth/me)" "401"
check "/auth/me garbage token" "$(code $CORE/auth/me -H 'authorization: Bearer not.a.jwt')" "401"
WRONG="{\"handle\":\"alice$S\",\"password\":\"definitely-not-it\"}"
check "wrong password" "$(post $CORE/auth/login "$WRONG")" "401"
GHOST="{\"handle\":\"ghost$S\",\"password\":\"correct-horse-battery\"}"
check "unknown user"   "$(post $CORE/auth/login "$GHOST")" "401"

echo "=== refresh rotation + reuse detection ==="
R1BODY="{\"refresh_token\":\"$A_REFRESH\"}"
R1=$(curl -s -X POST $CORE/auth/refresh -H 'content-type: application/json' -d "$R1BODY")
A_REFRESH2=$(echo "$R1" | j "['refresh_token']")
check "refresh issues a NEW token" "$([ -n "$A_REFRESH2" ] && [ "$A_REFRESH2" != "$A_REFRESH" ] && echo yes)" "yes"
R2BODY="{\"refresh_token\":\"$A_REFRESH2\"}"
check "rotated token works" "$(post $CORE/auth/refresh "$R2BODY")" "200"
check "REUSE of consumed token rejected" "$(post $CORE/auth/refresh "$R1BODY")" "401"
check "REUSE revokes the whole family"   "$(post $CORE/auth/refresh "$R2BODY")" "401"

echo "=== catches + geo ==="
# Its own patch of empty ocean per run, so absolute counts are not polluted by
# earlier runs sharing this database.
LAT=$(python3 -c "import random;print(round(random.uniform(-40,-10),4))")
LNG=$(python3 -c "import random;print(round(random.uniform(-140,-110),4))")
LAT_NEAR=$(python3 -c "print(round($LAT + 0.0045, 4))")   # ~500m north
LAT_FAR=$(python3 -c "print(round($LAT + 2.0, 4))")       # ~220km north

RELOGIN="{\"handle\":\"alice$S\",\"password\":\"correct-horse-battery\"}"
A_ACCESS=$(curl -s -X POST $CORE/auth/login -H 'content-type: application/json' -d "$RELOGIN" | j "['access_token']")

C1="{\"species_key\":\"squirrel\",\"caught_at\":\"2026-09-01T10:00:00Z\",\"lat\":$LAT,\"lng\":$LNG,\"confidence\":0.91}"
C2="{\"species_key\":\"owl\",\"caught_at\":\"2026-09-01T11:00:00Z\",\"lat\":$LAT_NEAR,\"lng\":$LNG}"
C3="{\"species_key\":\"frog\",\"caught_at\":\"2026-09-01T12:00:00Z\",\"lat\":$LAT_FAR,\"lng\":$LNG}"
C4="{\"species_key\":\"moth\",\"caught_at\":\"2026-09-01T13:00:00Z\"}"
BAD1='{"species_key":"bee","caught_at":"2026-09-01T13:00:00Z","lat":32.0}'
BAD2='{"species_key":"bee","caught_at":"2026-09-01T13:00:00Z","lat":991.0,"lng":0.0}'

check "create catch"                  "$(auth_post $CORE/catches "$A_ACCESS" "$C1")" "200"
check "create catch 500m away"        "$(auth_post $CORE/catches "$A_ACCESS" "$C2")" "200"
check "create catch 220km away"       "$(auth_post $CORE/catches "$A_ACCESS" "$C3")" "200"
check "catch with no location ok"     "$(auth_post $CORE/catches "$A_ACCESS" "$C4")" "200"
check "half a coordinate rejected"    "$(auth_post $CORE/catches "$A_ACCESS" "$BAD1")" "400"
check "out-of-range latitude rejected" "$(auth_post $CORE/catches "$A_ACCESS" "$BAD2")" "400"
check "catches require auth"          "$(code $CORE/catches/me)" "401"

N=$(curl -s "$CORE/catches/nearby?lat=$LAT&lng=$LNG&radius_m=2000" -H "authorization: Bearer $A_ACCESS")
check "nearby 2km returns 2 (far one excluded)" "$(echo "$N" | len)" "2"
NW=$(curl -s "$CORE/catches/nearby?lat=$LAT&lng=$LNG&radius_m=999999999" -H "authorization: Bearer $A_ACCESS")
check "radius clamped to 50km (220km still excluded)" "$(echo "$NW" | len)" "2"

# A new catch must be visible immediately despite the 30s geo cache TTL.
C5="{\"species_key\":\"snail\",\"caught_at\":\"2026-09-01T14:00:00Z\",\"lat\":$LAT,\"lng\":$LNG}"
auth_post $CORE/catches "$A_ACCESS" "$C5" > /dev/null
N2=$(curl -s "$CORE/catches/nearby?lat=$LAT&lng=$LNG&radius_m=2000" -H "authorization: Bearer $A_ACCESS")
check "geo cache invalidated on write" "$(echo "$N2" | len)" "3"

echo "=== friends authorization ==="
check "non-friend blocked from dex" "$(code $CORE/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "403"
FREQ="{\"handle\":\"alice$S\"}"
check "bob requests alice" "$(auth_post $CORE/friends/request "$B_ACCESS" "$FREQ")" "200"
check "still blocked while pending" "$(code $CORE/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "403"
check "requester cannot self-accept" "$(code -X POST $CORE/friends/$A_ID/accept -H "authorization: Bearer $B_ACCESS")" "404"
check "alice accepts" "$(code -X POST $CORE/friends/$B_ID/accept -H "authorization: Bearer $A_ACCESS")" "204"
check "friend can now read dex" "$(code $CORE/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")" "200"
D=$(curl -s $CORE/friends/$A_ID/dex -H "authorization: Bearer $B_ACCESS")
check "dex shows 5 distinct species" "$(echo "$D" | len)" "5"
SELF="{\"handle\":\"alice$S\"}"
check "cannot befriend yourself" "$(auth_post $CORE/friends/request "$A_ACCESS" "$SELF")" "400"

echo "=== logout ==="
LOGIN2="{\"handle\":\"bob$S\",\"password\":\"correct-horse-battery\"}"
L_REFRESH=$(curl -s -X POST $CORE/auth/login -H 'content-type: application/json' -d "$LOGIN2" | j "['refresh_token']")
LBODY="{\"refresh_token\":\"$L_REFRESH\"}"
check "logout succeeds" "$(post $CORE/auth/logout "$LBODY")" "204"
check "revoked token cannot refresh" "$(post $CORE/auth/refresh "$LBODY")" "401"

echo
echo "  $pass passed, $fail failed"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
