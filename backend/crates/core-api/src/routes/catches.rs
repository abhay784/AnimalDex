use axum::extract::{Path, Query, State};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use shared::{ApiError, ApiResult};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/catches", post(create))
        .route("/catches/me", get(list_mine))
        .route("/catches/nearby", get(nearby))
        .route("/catches/{id}", delete(remove))
}

#[derive(Debug, Deserialize)]
pub struct CreateCatch {
    pub species_key: String,
    pub caught_at: DateTime<Utc>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub confidence: Option<f32>,
    pub media_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct CatchView {
    pub id: Uuid,
    pub user_id: Uuid,
    pub handle: String,
    pub species_key: String,
    pub caught_at: DateTime<Utc>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub media_id: Option<Uuid>,
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateCatch>,
) -> ApiResult<Json<CatchView>> {
    if body.species_key.is_empty() || body.species_key.len() > 64 {
        return Err(ApiError::BadRequest("species_key must be 1-64 characters".into()));
    }
    // Coordinates are validated here *and* by CHECK constraints in the schema.
    // The duplication is deliberate: this returns a useful 400, the constraint
    // guarantees no other code path can ever bypass it.
    if body.lat.is_some() != body.lng.is_some() {
        return Err(ApiError::BadRequest("lat and lng must be provided together".into()));
    }
    if let (Some(lat), Some(lng)) = (body.lat, body.lng) {
        if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lng) {
            return Err(ApiError::BadRequest("coordinates out of range".into()));
        }
    }

    // A caller must own the media they attach, or one user could staple another
    // user's photo to their own catch.
    if let Some(media_id) = body.media_id {
        let owned = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM media_objects WHERE id = $1 AND owner_id = $2)",
            media_id,
            user.id
        )
        .fetch_one(&state.db)
        .await?
        .unwrap_or(false);

        if !owned {
            return Err(ApiError::Forbidden("That media does not belong to you.".into()));
        }
    }

    let row = sqlx::query!(
        r#"
        INSERT INTO catches (user_id, species_key, caught_at, lat, lng, confidence, media_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, user_id, species_key, caught_at, lat, lng, media_id
        "#,
        user.id,
        body.species_key,
        body.caught_at,
        body.lat,
        body.lng,
        body.confidence,
        body.media_id,
    )
    .fetch_one(&state.db)
    .await?;

    crate::routes::invalidate_user_cache(&state, user.id).await;

    Ok(Json(CatchView {
        id: row.id,
        user_id: row.user_id,
        handle: user.handle,
        species_key: row.species_key,
        caught_at: row.caught_at,
        lat: row.lat,
        lng: row.lng,
        media_id: row.media_id,
    }))
}

async fn list_mine(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<Vec<CatchView>>> {
    let rows = sqlx::query!(
        r#"
        SELECT c.id, c.user_id, u.handle, c.species_key, c.caught_at, c.lat, c.lng, c.media_id
        FROM catches c
        JOIN users u ON u.id = c.user_id
        WHERE c.user_id = $1
        ORDER BY c.caught_at DESC
        LIMIT 500
        "#,
        user.id
    )
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| CatchView {
                id: r.id,
                user_id: r.user_id,
                handle: r.handle,
                species_key: r.species_key,
                caught_at: r.caught_at,
                lat: r.lat,
                lng: r.lng,
                media_id: r.media_id,
            })
            .collect(),
    ))
}

#[derive(Debug, Deserialize)]
pub struct NearbyQuery {
    pub lat: f64,
    pub lng: f64,
    #[serde(default = "default_radius")]
    pub radius_m: f64,
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_radius() -> f64 { 5_000.0 }
fn default_limit() -> i64 { 100 }

const MAX_RADIUS_M: f64 = 50_000.0;
const MAX_LIMIT: i64 = 200;

/// Community sightings within a radius.
///
/// Radius and limit are clamped rather than trusted. An uncapped `radius_m`
/// turns this endpoint into "select every catch on Earth, sorted by distance",
/// which is a trivially cheap request to make and an expensive one to serve.
async fn nearby(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<NearbyQuery>,
) -> ApiResult<Json<Vec<CatchView>>> {
    if !(-90.0..=90.0).contains(&q.lat) || !(-180.0..=180.0).contains(&q.lng) {
        return Err(ApiError::BadRequest("coordinates out of range".into()));
    }
    let radius = q.radius_m.clamp(1.0, MAX_RADIUS_M);
    let limit = q.limit.clamp(1, MAX_LIMIT);

    let rows = sqlx::query!(
        r#"
        SELECT c.id, c.user_id, u.handle, c.species_key, c.caught_at, c.lat, c.lng, c.media_id
        FROM catches c
        JOIN users u ON u.id = c.user_id
        WHERE c.location IS NOT NULL
          AND ST_DWithin(c.location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
        ORDER BY c.location <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        LIMIT $4
        "#,
        q.lat,
        q.lng,
        radius,
        limit,
    )
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| CatchView {
                id: r.id,
                user_id: r.user_id,
                handle: r.handle,
                species_key: r.species_key,
                caught_at: r.caught_at,
                lat: r.lat,
                lng: r.lng,
                media_id: r.media_id,
            })
            .collect(),
    ))
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<axum::http::StatusCode> {
    // Ownership is part of the WHERE clause, not a separate check. A read-then-
    // delete would be racy and, worse, would need a second code path that could
    // forget the predicate.
    let result = sqlx::query!("DELETE FROM catches WHERE id = $1 AND user_id = $2", id, user.id)
        .execute(&state.db)
        .await?;

    if result.rows_affected() == 0 {
        // Deliberately not distinguishing "does not exist" from "not yours":
        // that difference is an enumeration oracle for other users' catch ids.
        return Err(ApiError::NotFound("catch"));
    }
    crate::routes::invalidate_user_cache(&state, user.id).await;
    Ok(axum::http::StatusCode::NO_CONTENT)
}
