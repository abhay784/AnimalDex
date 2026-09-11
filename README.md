# AnimalDex

AnimalDex is an iPhone wildlife journal with a creature scanner, local-first Dex,
private sighting map, optional sharing, and trainer accounts. It pairs a SwiftUI
iOS app with a Rust/Axum backend for authentication, friends, catches, and photo
uploads.

## What it does

- Scan and identify nearby wildlife, then register it in a personal Dex.
- Keep catches on-device by default; location and sharing are opt-in.
- Sign in to share selected sightings, browse the community map, and compare
  Dexes with friends.
- Use short-lived access tokens plus rotated refresh tokens for account sessions.

## Project layout

| Path | Purpose |
| --- | --- |
| `AnimalDex/` | SwiftUI iOS application |
| `backend/crates/core-api/` | Auth, friends, catches, and geo search service |
| `backend/crates/media-svc/` | Presigned photo-upload and thumbnail service |
| `backend/migrations/` | Postgres/PostGIS schema migrations |
| `AnimalDexTests/`, `AnimalDexUITests/` | Unit and UI tests |
| `ml/` | Recognition-model training and evaluation tools |

## Requirements

- Xcode and XcodeGen
- Rust toolchain (`cargo`)
- Docker Desktop
- An iPhone running iOS 17 or newer for camera and on-device Vision testing

## Run the backend

```bash
cd backend
cp .env.example .env
docker compose up -d
cargo run -p core-api
```

In a second terminal, start the media service when testing photo sharing:

```bash
cd backend
cargo run -p media-svc
```

The local services use these ports:

| Service | Address |
| --- | --- |
| Core API | `http://localhost:8080` |
| Media API | `http://localhost:8081` |
| Postgres/PostGIS | `localhost:5434` |
| Redis | `localhost:6380` |
| MinIO API / console | `localhost:9100` / `localhost:9101` |

Confirm the core API is running with:

```bash
curl http://localhost:8080/health
```

## Build the iOS app

Generate the Xcode project and open it:

```bash
xcodegen generate
open AnimalDex.xcodeproj
```

For an iPhone, connect and unlock the device, enable Developer Mode, then run:

```bash
./scripts/run-on-device.sh
```

See [DEVICE.md](DEVICE.md) for signing, installation, camera-recognition, and
device troubleshooting details.

## Sign-in on a physical iPhone

The Simulator can reach a backend at `localhost`. On a physical iPhone,
`localhost` refers to the phone, not the Mac.

1. Keep the Mac and iPhone on the same Wi-Fi network.
2. Start the backend as above.
3. In AnimalDex, open **TRAINER → DEVELOPER → SERVER HOST**.
4. Enter your Mac's LAN address, for example `192.168.1.95`, then submit the
   field.
5. Sign in or create a trainer account.

Check the address from the Mac with `ipconfig getifaddr en0`. If connection
fails, first open `http://<mac-lan-ip>:8080/health` from another device on the
same network.

## Tests

Run backend unit tests:

```bash
cd backend
cargo test --workspace
```

With both backend services running, run the end-to-end smoke tests:

```bash
cd backend
./scripts/smoke.sh
./scripts/media_smoke.sh
```

The iOS integration test registers a trainer, signs out and back in, records a
catch, and shares it. It automatically skips when the core API is unavailable.

## Security notes

Refresh tokens are stored in the iOS Keychain. Access tokens remain in memory,
and refresh-token rotation revokes a token family if a consumed token is reused.
Do not commit `backend/.env`; replace its development JWT secret and storage
credentials before any non-local deployment.
