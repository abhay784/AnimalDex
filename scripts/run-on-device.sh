#!/usr/bin/env bash
# Build AnimalDex and install it on a connected iPhone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM=$(grep '^DEVELOPMENT_TEAM' Config/Signing.xcconfig | sed 's/.*=[[:space:]]*//')
if [ -z "$TEAM" ]; then
  echo "No DEVELOPMENT_TEAM set. Run ./scripts/find-team-id.sh first."
  exit 1
fi

echo "==> Looking for a connected device"
DEVICES=$(xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone|ipad' || true)
if [ -z "$DEVICES" ]; then
  cat <<'EOF'
No device found. Checklist:

  - iPhone connected by USB (Wi-Fi pairing works too, once paired over USB)
  - Unlocked, and "Trust This Computer" accepted
  - Developer Mode on: Settings > Privacy & Security > Developer Mode,
    toggle on, then restart the phone. This only appears after a development
    build has been attempted once, so if you don't see it, keep going.
  - iOS 17.0 or later (the app's deployment target)

EOF
  exit 1
fi
echo "$DEVICES" | sed 's/^/  /'

UDID=$(echo "$DEVICES" | head -1 | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}' | head -1)
if [ -z "$UDID" ]; then
  echo "Could not parse a device identifier. Run 'xcrun devicectl list devices' and pass it manually."
  exit 1
fi

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building for device (team $TEAM)"
xcodebuild -scheme AnimalDex \
  -destination "id=$UDID" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E 'error:|warning: .*signing|BUILD' || true

APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'AnimalDex.app' -path '*Debug-iphoneos*' -print -quit 2>/dev/null)
if [ -z "$APP" ]; then
  echo "Build did not produce a device .app. See the errors above."
  exit 1
fi

echo "==> Installing"
xcrun devicectl device install app --device "$UDID" "$APP"

cat <<'EOF'

Installed. On the phone, the first launch will be blocked until you trust the
certificate:

  Settings > General > VPN & Device Management > (your Apple ID) > Trust

Then open AnimalDex and point it at an animal.
EOF
