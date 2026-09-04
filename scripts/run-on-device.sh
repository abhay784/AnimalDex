#!/usr/bin/env bash
# Build AnimalDex and install it on a connected iPhone.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM=$(grep '^DEVELOPMENT_TEAM' Config/Signing.xcconfig | sed 's/.*=[[:space:]]*//')
if [ -z "$TEAM" ]; then
  echo "No DEVELOPMENT_TEAM set. Run ./scripts/find-team-id.sh first."
  exit 1
fi

echo "==> Looking for a connected device"
TMP=$(mktemp -t animaldex-devices)
xcrun devicectl list devices --json-output "$TMP" >/dev/null 2>&1 || true

# Parse the JSON rather than scraping the table: column widths truncate long
# device names and shift the identifier, which makes regex on the table fragile.
read -r UDID NAME OSVER <<<"$(python3 - "$TMP" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    props = d.get("deviceProperties", {})
    hw = d.get("hardwareProperties", {})
    # Only paired-and-available iOS hardware can be installed to.
    if hw.get("platform") not in ("iOS",):
        continue
    state = d.get("connectionProperties", {}).get("tunnelState", "")
    if state == "unavailable":
        continue
    print(d.get("identifier", ""),
          (props.get("name") or "iPhone").replace(" ", "_"),
          props.get("osVersionNumber", "?"))
    break
PY
)"
rm -f "$TMP"

if [ -z "${UDID:-}" ]; then
  cat <<'EOF'
No device found. Checklist:

  - iPhone connected by USB and UNLOCKED
  - "Trust This Computer" accepted on the phone
  - Developer Mode on: Settings > Privacy & Security > Developer Mode,
    toggle on, then restart the phone.
    (That menu entry only appears after a development build has been attempted
    against the device, so if you don't see it yet, plug in and re-run this.)
  - iOS 17.0 or later — this app's deployment target

Raw device list for reference:
EOF
  xcrun devicectl list devices 2>&1 | sed 's/^/  /'
  exit 1
fi

echo "  ${NAME//_/ }  (iOS $OSVER)  $UDID"

case "$OSVER" in
  1[0-6].*|[0-9].*)
    echo
    echo "WARNING: this device runs iOS $OSVER but AnimalDex targets iOS 17.0+."
    echo "The install will fail. Lower IPHONEOS_DEPLOYMENT_TARGET in project.yml to proceed."
    ;;
esac

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building for device (team $TEAM)"
# -allowProvisioningUpdates lets Xcode register the device with your team and
# create the certificate + profile on demand. On a free account this is what
# mints the 7-day profile.
if ! xcodebuild -scheme AnimalDex \
      -destination "id=$UDID" \
      -configuration Debug \
      -allowProvisioningUpdates \
      build 2>&1 | tee /tmp/animaldex-build.log | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'; then
  true
fi

if ! grep -q "BUILD SUCCEEDED" /tmp/animaldex-build.log; then
  echo
  echo "Build failed — full log at /tmp/animaldex-build.log"
  exit 1
fi

APP=$(find ~/Library/Developer/Xcode/DerivedData -name 'AnimalDex.app' -path '*Debug-iphoneos*' -print -quit 2>/dev/null)
if [ -z "$APP" ]; then
  echo "Build succeeded but no device .app was found. Log: /tmp/animaldex-build.log"
  exit 1
fi

echo "==> Installing to ${NAME//_/ }"
xcrun devicectl device install app --device "$UDID" "$APP"

cat <<'EOF'

Installed.

First launch will be blocked by iOS until you trust the certificate:
  Settings > General > VPN & Device Management > (your Apple ID) > Trust

Then open AnimalDex. To see what the recognizer is actually doing:
  TRAINER tab > DEVELOPER > SHOW RECOGNITION OVERLAY

The overlay header must read VISION.BUILTIN.V1 on a device.
EOF
