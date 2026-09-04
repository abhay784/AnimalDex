.PHONY: up down migrate run-api run-media test smoke fmt clippy

up:            ## start Postgres+PostGIS, Redis and MinIO
	docker compose up -d

down:
	docker compose down

migrate:
	sqlx migrate run --source migrations

run-api:
	cargo run -p core-api

run-media:
	cargo run -p media-svc

test:
	cargo test --workspace

smoke:         ## end-to-end; both services must be running
	./scripts/smoke.sh && ./scripts/media_smoke.sh

prepare:       ## refresh the offline query cache after changing SQL
	cargo sqlx prepare --workspace -- --all-targets

fmt:
	cargo fmt --all

clippy:
	cargo clippy --workspace --all-targets -- -D warnings
