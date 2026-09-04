# Running AnimalDex on a physical iPhone

The Simulator cannot verify the thing that matters most. It has no camera, and
Apple's Vision classifier does not work there — it fails to create a Core ML
context, and if you pin it to the CPU it silently returns a **constant** result
(every photo classified as `night_sky: 0.49`). So the app substitutes
`ScriptedRecognizer` in Simulator builds.

Device builds compile that file out entirely and use `VisionBuiltinRecognizer`
against the real camera. Running on hardware is the only way to know Track A
actually works.

---

## Status

| Step | State |
|---|---|
| Apple ID signed into Xcode | ✅ done — `Abhay Korlapati (Personal Team)`, `AT33H6TMUA` |
| Team ID written to `Config/Signing.xcconfig` | ✅ done, by `./scripts/find-team-id.sh` |
| Apple Development certificate | ✅ created automatically on the first build attempt |
| **Xcode version** | ❌ **blocked — see below** |
| Device paired | ❌ blocked — needs the Xcode update first |
| Provisioning profile | ❌ needs a paired device to generate |

## Currently blocking: Xcode is too old for this iPhone

This Mac has **Xcode 16.4**, whose newest iOS SDK is **18.5**. The connected
iPhone (`Abhay's iPhone`) runs **iOS 26.6.1**. Xcode cannot build for a device
running an iOS newer than what it ships an SDK for, and there is no partial
"platform support" package that bridges an 8-major-version gap — only Xcode
itself updates that far.

**This needs Xcode 26.x**, downloaded via the App Store (already opened to the
Xcode listing) or from developer.apple.com/download with your Apple ID.

Before starting the download:

- **Check free space.** This Mac has ~31GB free. A current Xcode plus its
  default iOS platform and simulators can approach that during install (the
  installer needs working room beyond the final size). If the update stalls or
  fails, free up space first — old simulator runtimes
  (`xcrun simctl list runtimes`, `xcrun simctl runtime delete <id>`) and stale
  DerivedData (`~/Library/Developer/Xcode/DerivedData`) are the usual easy wins.
- It is a large download and will take a while on typical home internet.
- **After it installs**, run:
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
  (a new Xcode install doesn't become the active one automatically), then
  re-run `./scripts/run-on-device.sh`.

Everything below this point is already done and does not need to be repeated —
signing into Xcode again would be harmless but is not necessary.

## On the phone

1. Connect by USB, unlock, tap **Trust This Computer**
2. **Settings → Privacy & Security → Developer Mode** → on → restart the phone
   - This entry only appears after a development build has been attempted, so if
     it is missing, run the install once first and then look again.
3. Needs **iOS 17.0 or later** (the app's deployment target)

## Install

```bash
./scripts/run-on-device.sh
```

First launch will be blocked by iOS until you trust the certificate:
**Settings → General → VPN & Device Management → (your Apple ID) → Trust**

### Free-account limits worth knowing

- The provisioning profile **expires after 7 days**. The app stops launching and
  you re-run the install script. Nothing is lost — the dex is on-device.
- At most **3** such apps installed at once.
- If Xcode says the bundle identifier is unavailable, change the suffix in
  `Config/Signing.xcconfig`.

---

## Verifying that Vision works

Turn on the recognition overlay: **TRAINER tab → DEVELOPER → SHOW RECOGNITION
OVERLAY**. The scanner then shows live labels straight from the model, colour
coded:

| Dot | Meaning |
|---|---|
| green | catchable — resolves to a dex entry |
| yellow | umbrella label (`bird`, `mammal`) — gates, never catches |
| red | food-context veto — catch blocked |
| blue | zoo / aquarium context |
| grey | not a creature label |

The header shows which recognizer is live. **On a device it must read
`VISION.BUILTIN.V1`.** If it says `SCRIPTED.SIMULATOR`, you are looking at a
Simulator build.

### Reading the result

- **Green dot, high confidence, banner appears** — working.
- **Green dot but no banner** — the model sees it, confidence is under the 0.5
  threshold. That is the flicker `RecognitionGate.decide(from:)` is meant to
  smooth; the HUD is showing you exactly the signal you are designing against.
- **Only yellow dots** — a creature is present but unidentified at species level.
  Expected behaviour: get closer, fill more of the frame.
- **`frames` not increasing** — the capture session never started. Check the
  camera permission prompt was accepted.
- **`no labels above 0.10`** — the model ran and found nothing it recognises.

Good subjects to start with: a dog or cat, a pigeon or sparrow, a houseplant
with a spider on it, a squirrel. Fill the frame — the classifier is far less
confident on a small subject in a wide scene.

---

## Talking to the backend from a phone

Not required to test recognition. The dex works fully offline with no account.

If you do want sign-in and sharing: on a phone `localhost` is *the phone*, so
point it at this Mac. **TRAINER tab → DEVELOPER → SERVER HOST**, enter:

```
192.168.1.95
```

Both must be on the same Wi-Fi, and the backend must be running
(`cd backend && docker compose up -d`, then `cargo run -p core-api` and
`cargo run -p media-svc`). `NSAllowsLocalNetworking` in Info.plist already
permits plain HTTP to LAN addresses.
