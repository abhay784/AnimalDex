#!/usr/bin/env bash
CORE=http://localhost:8080; MEDIA=http://localhost:8081
IMG=/Users/abhaykorlapati/AnimalDex/AnimalDex/Resources/dev_samples/sample_squirrel.jpg
pass=0; fail=0
j() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }
check(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }
code(){ curl -s -o /dev/null -w '%{http_code}' "$@"; }

S=$RANDOM
U=$(curl -s -X POST $CORE/auth/register -H 'content-type: application/json' \
  -d "{\"handle\":\"mm$S\",\"email\":\"mm$S@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"M\"}")
TOK=$(echo "$U" | j "['access_token']")
V=$(curl -s -X POST $CORE/auth/register -H 'content-type: application/json' \
  -d "{\"handle\":\"vv$S\",\"email\":\"vv$S@example.com\",\"password\":\"correct-horse-battery\",\"display_name\":\"V\"}")
TOK2=$(echo "$V" | j "['access_token']")

echo "=== validation before any bytes move ==="
check "auth required" "$(code -X POST $MEDIA/media/upload-url -H 'content-type: application/json' -d '{"content_type":"image/jpeg","byte_size":100}')" "401"
check "rejects non-image type" "$(code -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK" -H 'content-type: application/json' -d '{"content_type":"image/svg+xml","byte_size":100}')" "400"
check "rejects oversize declaration" "$(code -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK" -H 'content-type: application/json' -d '{"content_type":"image/jpeg","byte_size":99999999}')" "400"

echo "=== presigned upload round trip ==="
SIZE=$(stat -f%z "$IMG")
R=$(curl -s -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK" -H 'content-type: application/json' \
    -d "{\"content_type\":\"image/jpeg\",\"byte_size\":$SIZE}")
MID=$(echo "$R" | j "['media_id']"); URL=$(echo "$R" | j "['upload_url']")
check "issued a media id" "$([ -n "$MID" ] && echo yes)" "yes"
check "upload URL points at MinIO, not us" "$(echo "$URL" | grep -c 'localhost:9100')" "1"

# The client PUTs straight to object storage - bytes never touch our API.
PUT=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$URL" -H 'content-type: image/jpeg' --data-binary "@$IMG")
check "direct PUT to storage" "$PUT" "200"

check "another user cannot complete it" "$(code -X POST $MEDIA/media/$MID/complete -H "authorization: Bearer $TOK2")" "403"
C=$(curl -s -X POST $MEDIA/media/$MID/complete -H "authorization: Bearer $TOK")
check "owner completes" "$(echo "$C" | j "['status']")" "ready"
check "size re-derived from storage, not trusted" "$(echo "$C" | j "['byte_size']")" "$SIZE"

echo "=== thumbnail worker ==="
sleep 3
T=$(curl -s -o /dev/null -w '%{http_code}' -L "$MEDIA/media/$MID" -H "authorization: Bearer $TOK")
check "media fetch redirects and resolves" "$T" "200"

echo "=== claimed vs actual content type ==="
# Ask for a JPEG URL, then upload something that is not a JPEG.
R2=$(curl -s -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK" -H 'content-type: application/json' \
     -d '{"content_type":"image/jpeg","byte_size":20}')
MID2=$(echo "$R2" | j "['media_id']"); URL2=$(echo "$R2" | j "['upload_url']")
curl -s -o /dev/null -X PUT "$URL2" -H 'content-type: text/plain' --data-binary 'not an image at all'
check "lying about content type is caught at complete" "$(code -X POST $MEDIA/media/$MID2/complete -H "authorization: Bearer $TOK")" "400"

echo "=== rate limiting (30/min) ==="
LAST=""
for i in $(seq 1 33); do
  LAST=$(code -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK2" -H 'content-type: application/json' -d '{"content_type":"image/jpeg","byte_size":1000}')
done
check "33rd request is rate limited" "$LAST" "429"
RA=$(curl -s -D- -o /dev/null -X POST $MEDIA/media/upload-url -H "authorization: Bearer $TOK2" -H 'content-type: application/json' -d '{"content_type":"image/jpeg","byte_size":1000}' | grep -ci 'retry-after')
check "429 carries Retry-After" "$RA" "1"

echo; echo "  $pass passed, $fail failed"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
