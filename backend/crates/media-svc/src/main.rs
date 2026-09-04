//! Media service — presigned uploads and thumbnailing.
//!
//! Split from `core-api` along a real boundary rather than for its own sake:
//! image decoding is CPU-bound with completely different scaling characteristics
//! from JSON CRUD, and photo bytes should never traverse an API process at all.

mod ratelimit;
mod routes;
mod state;
mod storage;
mod worker;

use anyhow::{Context, Result};
use axum::Router;
use shared::JwtKeys;
use sqlx::postgres::PgPoolOptions;
use state::AppState;
use storage::Storage;

#[tokio::main]
async fn main() -> Result<()> {
    let _ = dotenvy::from_filename("../../.env").or_else(|_| dotenvy::dotenv());
    shared::telemetry::init("media-svc");

    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL must be set")?;
    let jwt_secret = std::env::var("JWT_SECRET").context("JWT_SECRET must be set")?;
    let addr = std::env::var("MEDIA_SVC_ADDR").unwrap_or_else(|_| "0.0.0.0:8081".into());

    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
        .context("could not connect to Postgres")?;

    let http = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    let storage = Storage::from_env()?;
    storage
        .ensure_bucket(&http)
        .await
        .context("could not reach object storage — is MinIO running?")?;

    let redis_url = std::env::var("REDIS_URL")?;
    let redis_client = redis::Client::open(redis_url).ok();
    let redis = match &redis_client {
        Some(client) => redis::aio::ConnectionManager::new(client.clone()).await.ok(),
        None => None,
    };
    if redis.is_none() {
        tracing::warn!("Redis unavailable — thumbnails and rate limiting disabled");
    }

    let state = AppState { db, redis, jwt: JwtKeys::new(&jwt_secret), storage, http };

    // The worker shares this process for now, but gets a genuinely separate
    // Redis connection: its BLPOP would otherwise block the multiplexed
    // connection every request-path command also uses. Extracting it into its
    // own deployment later means moving this spawn, not restructuring anything.
    if let Some(client) = redis_client {
        match client.get_multiplexed_async_connection().await {
            Ok(conn) => {
                tokio::spawn(worker::run(state.clone(), conn));
            }
            Err(e) => tracing::warn!(error = %e, "thumbnail worker could not connect to Redis"),
        }
    }

    let app = Router::new()
        .merge(routes::routes())
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "media-svc listening");
    axum::serve(listener, app).await?;
    Ok(())
}
