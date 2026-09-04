use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/health", get(health))
        .route("/health/ready", get(ready))
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
    service: &'static str,
}

/// Liveness: is the process up. Deliberately touches nothing else, so a database
/// blip cannot make an orchestrator kill an otherwise healthy process.
async fn health() -> Json<Health> {
    Json(Health { status: "ok", service: "core-api" })
}

#[derive(Serialize)]
struct Readiness {
    status: &'static str,
    database: bool,
    redis: bool,
}

/// Readiness: can this instance actually serve traffic. Redis being down is
/// reported but not disqualifying — it only backs caching and rate limiting.
async fn ready(State(state): State<AppState>) -> (axum::http::StatusCode, Json<Readiness>) {
    let database = sqlx::query_scalar!("SELECT 1")
        .fetch_one(&state.db)
        .await
        .is_ok();

    let redis = match state.redis.clone() {
        Some(mut conn) => redis::cmd("PING")
            .query_async::<String>(&mut conn)
            .await
            .is_ok(),
        None => false,
    };

    let code = if database {
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::SERVICE_UNAVAILABLE
    };
    (code, Json(Readiness { status: if database { "ready" } else { "degraded" }, database, redis }))
}
