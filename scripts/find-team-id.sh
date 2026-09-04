#!/usr/bin/env bash
# Find the Team ID Xcode registered for your Apple ID and write it into
# Config/Signing.xcconfig.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/Config/Signing.xcconfig"

PREFS=$(defaults read com.apple.dt.Xcode 2>/dev/null || true)

if [ -z "$PREFS" ]; then
  cat <<'EOF'
Xcode has no preferences yet — it may never have been opened.

  1. Open Xcode
  2. Settings (Cmd+,) > Accounts > "+" > Apple ID
  3. Sign in (a free Apple ID is fine)
  4. Re-run this script
EOF
  exit 1
fi

# Xcode has used more than one key for this over the years:
#   IDEProvisioningTeams            (older)
#   IDEProvisioningTeamByIdentifier (current)
# Rather than guess, pull every teamID/teamName pair out of the prefs dump.
TEAM_BLOCK=$(echo "$PREFS" | grep -A2 -E 'teamID' | grep -E 'teamID|teamName|isFreeProvisioningTeam' || true)

if [ -z "$TEAM_BLOCK" ]; then
  cat <<'EOF'
No development team found in Xcode's preferences.

Signing in under Accounts is what creates this. If you have signed in and still
see this, open Xcode > Settings > Accounts and confirm your Apple ID is listed
with a team beneath it.
EOF
  exit 1
fi

echo "Teams Xcode knows about:"
echo "$TEAM_BLOCK" | sed 's/^/  /'
echo

IDS=$(echo "$PREFS" | grep -E 'teamID' | grep -oE '[A-Z0-9]{10}' | sort -u)
COUNT=$(printf '%s\n' "$IDS" | grep -c . || true)

if [ "$COUNT" -eq 0 ]; then
  echo "Could not parse a Team ID. Open Config/Signing.xcconfig and set it by hand."
  exit 1
elif [ "$COUNT" -gt 1 ]; then
  echo "More than one team found. Put the one you want in Config/Signing.xcconfig:"
  printf '%s\n' "$IDS" | sed 's/^/  /'
  exit 1
fi

sed -i '' "s/^DEVELOPMENT_TEAM =.*/DEVELOPMENT_TEAM = $IDS/" "$CONFIG"
echo "Wrote DEVELOPMENT_TEAM = $IDS into Config/Signing.xcconfig"
echo

# Signing in does NOT create a signing certificate. Xcode creates one the first
# time it actually signs something, which is why a fresh account shows zero
# identities here and that is not an error.
CERTS=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Development" || true)
if [ "$CERTS" -eq 0 ]; then
  cat <<'EOF'
Note: you have no Apple Development certificate yet. That is expected — signing
into Xcode does not create one. It gets created automatically on the first
device build, which is why run-on-device.sh passes -allowProvisioningUpdates.

Connect your iPhone, then run:  ./scripts/run-on-device.sh
EOF
else
  echo "Apple Development certificate present. Next: ./scripts/run-on-device.sh"
fi
