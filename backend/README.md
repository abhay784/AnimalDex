# AnimalDex backend

Two Rust/Axum services behind Postgres+PostGIS, Redis and S3-compatible storage.

| Service | Port | Responsibility |
|---|---|---|
| `core-api` | 8080 | auth, users, friends, catches, geo search |
| `media-svc` | 8081 | presigned uploads, thumbnail pipeline |

The split follows a real boundary rather than being decomposition for its own
sake: image decoding is CPU-bound and scales completely differently from JSON
CRUD, and photo bytes should never traverse an API process at all. Everything
else stays in one service, because splitting `auth` from `friends` would buy
network hops and distributed-failure modes in exchange for nothing.

## Running

```bash
docker compose up -d          # postgres+postgis, redis, minio
cp .env.example .env          # then set a real JWT_SECRET
cargo run -p core-api         # :8080
cargo run -p media-svc        # :8081
./scripts/smoke.sh            # 33 end-to-end checks
./scripts/media_smoke.sh      # 13 upload-pipeline checks
```

Host ports are non-default (Postgres **5434**, Redis **6380**, MinIO **9100**)
so the stack never collides with other projects on the same machine.

## Design notes

**Spatial data without a PostGIS codec.** `catches` stores plain `lat`/`lng`
doubles plus a `GENERATED ALWAYS AS ... STORED` `geography(Point,4326)` column
with a GIST index. Queries filter on the spatial column (`ST_DWithin`) but always
select back `f64`s, so `sqlx` never decodes PostGIS binary geometry and `geozero`
is not a dependency. Postgres rejects direct writes to the generated column, so
it cannot drift from its source coordinates.

**Friendships cannot duplicate.** One row per *pair*, primary-keyed on
`(user_low, user_high)` with `CHECK (user_low < user_high)`, plus `requested_by`
to preserve direction. The usual `(user_id, friend_id)` shape allows the same
friendship to exist twice in mirrored rows; here it is structurally impossible
rather than something application code must remember to check.

**Refresh rotation with reuse detection.** Refresh tokens are opaque 256-bit
values stored as SHA-256. Each refresh consumes one and issues another in the
same family, inside a transaction. Presenting an already-consumed token is
treated as proof of theft and revokes the entire family. Rotation alone would
only mean whoever refreshes second gets an error, with no signal anything was
wrong.

**Timing-safe login.** When a handle does not exist, login still verifies the
password against a dummy Argon2 hash, so a missing account and a wrong password
take the same wall-clock time.

**Presigned URLs are not a trust boundary.** The client PUTs directly to object
storage, so what it *declared* when requesting the URL proves nothing. On
`complete`, content type and byte size are re-derived from the object store via
HEAD, and anything outside the allowlist is marked `failed`.

**Redis fails open.** It backs caching and rate limiting — cost and nuisance
guards, not correctness or authorization — so an outage makes the service slower
and more permissive rather than broken. A limiter protecting authentication
should fail *closed* instead; the trade differs with what is being protected.

**Geo cache invalidation by version counter.** Precisely invalidating a spatial
cache is hard: a new catch invalidates every cached radius whose circle contains
it, which cannot be enumerated without scanning. Instead `geo:version` is stamped
into every cache key and `INCR`ed on write, making all existing entries
unreachable at once while orphans expire on their own TTL.

**Blocking Redis commands get their own connection.** The thumbnail worker's
`BLPOP` holds a connection for its timeout. Sharing the multiplexed
`ConnectionManager` with the request path made presigned-URL issuance take ~5s
per request; a dedicated connection brought it to ~12ms.

## Known gaps

- `media_objects` rows can linger in `pending` when a client requests an upload
  URL and never uploads. A periodic sweep should mark or delete them.
- No CI pipeline or tracing/metrics export yet — deliberately out of scope.
- Thumbnail failures are logged and dropped rather than retried with backoff.
