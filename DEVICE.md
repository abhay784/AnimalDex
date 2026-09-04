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

## What only you can do

The Mac has **no Apple ID signed into Xcode**, no signing certificate, and no
provisioning profiles. That step needs your credentials.

1. Open **Xcode**
2. **Settings** (⌘,) → **Accounts** → **+** → **Apple ID**
3. Sign in. **A free Apple ID is fine** — no paid developer account needed.

Then, back in the terminal:

```bash
./scripts/find-team-id.sh
```

It reads the Team ID Xcode registered and writes it into
`Config/Signing.xcconfig`. Until that line is filled in, a device build fails
with *"Signing for AnimalDex requires a development team"* — which is expected,
not a bug.

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
