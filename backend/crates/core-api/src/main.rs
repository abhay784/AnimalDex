use anyhow::{Context, Result};
use core_api::{app, config::Config, state::AppState};
use shared::JwtKeys;
use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> Result<()> {
    let _ = dotenvy::from_filename("../../.env").or_else(|_| dotenvy::dotenv());
    shared::telemetry::init("core-api");

    let config = Config::from_env()?;

    let db = PgPoolOptions::new()
        .max_connections(20)
        .acquire_timeout(std::time::Duration::from_secs(5))
        .connect(&config.database_url)
        .await
        .context("could not connect to Postgres — is `docker compose up -d` running?")?;

    // Migrations run at boot rather than as a separate deploy step. At this size
    // that is a feature: there is no window where the code is newer than the
    // schema it expects.
    sqlx::migrate!("../../migrations")
        .run(&db)
        .await
        .context("migrations failed")?;

    // Redis is optional on purpose — see AppState. A cache outage should slow
    // the service down, not take it offline.
    let redis = match redis::Client::open(config.redis_url.clone()) {
        Ok(client) => match redis::aio::ConnectionManager::new(client).await {
            Ok(conn) => Some(conn),
            Err(e) => {
                tracing::warn!(error = %e, "Redis unavailable — caching and rate limiting disabled");
                None
            }
        },
        Err(e) => {
            tracing::warn!(error = %e, "Redis URL invalid — caching and rate limiting disabled");
            None
        }
    };

    let state = AppState { db, redis, jwt: JwtKeys::new(&config.jwt_secret) };
    let listener = tokio::net::TcpListener::bind(&config.listen_addr).await?;
    tracing::info!(addr = %config.listen_addr, "core-api listening");

    axum::serve(listener, app(state))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutting down");
}
