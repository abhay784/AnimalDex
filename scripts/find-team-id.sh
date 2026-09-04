#!/usr/bin/env bash
# Print the Team ID(s) Xcode knows about, and offer to write one into
# Config/Signing.xcconfig.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/Config/Signing.xcconfig"

echo "Signing identities in your keychain:"
security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /' || true
echo

TEAMS=$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null || true)
if [ -z "$TEAMS" ]; then
  cat <<'EOF'
No Xcode account found.

  1. Open Xcode
  2. Settings (Cmd+,) > Accounts > "+" > Apple ID
  3. Sign in with any Apple ID — a free one is fine
  4. Re-run this script

EOF
  exit 1
fi

echo "Teams registered in Xcode:"
echo "$TEAMS" | grep -E 'teamID|teamName' | sed 's/^/  /'
echo

IDS=$(echo "$TEAMS" | grep -oE '"[A-Z0-9]{10}"' | tr -d '"' | sort -u)
COUNT=$(echo "$IDS" | grep -c . || true)

if [ "$COUNT" = "1" ]; then
  ID="$IDS"
  echo "Writing DEVELOPMENT_TEAM = $ID into Config/Signing.xcconfig"
  # BSD sed needs the empty backup arg.
  sed -i '' "s/^DEVELOPMENT_TEAM =.*/DEVELOPMENT_TEAM = $ID/" "$CONFIG"
  echo "Done. Now run: ./scripts/run-on-device.sh"
else
  echo "Multiple teams found. Put the right one in Config/Signing.xcconfig:"
  echo "$IDS" | sed 's/^/  /'
fi
