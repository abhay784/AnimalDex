use axum::extract::{Path, State};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use shared::{ApiError, ApiResult};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/friends", get(list))
        .route("/friends/request", post(request))
        .route("/friends/{id}/accept", post(accept))
        .route("/friends/{id}/decline", post(decline))
        .route("/friends/{id}", delete(remove))
        .route("/friends/{id}/dex", get(friend_dex))
}

/// The pair key, in the canonical order the schema requires.
///
/// Every friendship query goes through this, which is what makes the
/// `CHECK (user_low < user_high)` constraint tractable instead of a nuisance.
fn pair(a: Uuid, b: Uuid) -> (Uuid, Uuid) {
    if a < b { (a, b) } else { (b, a) }
}

#[derive(Debug, Deserialize)]
pub struct FriendRequest {
    pub handle: String,
}

#[derive(Debug, Serialize)]
pub struct FriendView {
    pub id: Uuid,
    pub handle: String,
    pub display_name: String,
    pub status: String,
    /// True when the *other* party sent the request and we owe them an answer.
    pub incoming: bool,
    pub species_count: i64,
}

async fn request(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<FriendRequest>,
) -> ApiResult<Json<FriendView>> {
    let target = sqlx::query!(
        "SELECT id, handle, display_name FROM users WHERE handle = $1",
        body.handle
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("user"))?;

    if target.id == user.id {
        return Err(ApiError::BadRequest("You cannot befriend yourself.".into()));
    }

    let (low, high) = pair(user.id, target.id);

    // ON CONFLICT DO NOTHING makes a duplicate request idempotent rather than an
    // error — and, importantly, means re-requesting cannot reset a friendship
    // someone already declined or blocked.
    let inserted = sqlx::query!(
        r#"
        INSERT INTO friendships (user_low, user_high, requested_by)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_low, user_high) DO NOTHING
        RETURNING status::text AS "status!"
        "#,
        low,
        high,
        user.id
    )
    .fetch_optional(&state.db)
    .await?;

    let status = match inserted {
        Some(row) => row.status,
        None => sqlx::query_scalar!(
            r#"SELECT status::text AS "status!" FROM friendships WHERE user_low = $1 AND user_high = $2"#,
            low,
            high
        )
        .fetch_one(&state.db)
        .await?,
    };

    Ok(Json(FriendView {
        id: target.id,
        handle: target.handle,
        display_name: target.display_name,
        status,
        incoming: false,
        species_count: 0,
    }))
}

async fn accept(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other): Path<Uuid>,
) -> ApiResult<axum::http::StatusCode> {
    let (low, high) = pair(user.id, other);

    // `requested_by <> $3` is the load-bearing clause: without it you could
    // accept your own outgoing request and befriend anyone unilaterally.
    let result = sqlx::query!(
        r#"
        UPDATE friendships
        SET status = 'accepted', responded_at = now()
        WHERE user_low = $1 AND user_high = $2
          AND status = 'pending'
          AND requested_by <> $3
        "#,
        low,
        high,
        user.id
    )
    .execute(&state.db)
    .await?;

    if result.rows_affected() == 0 {
        return Err(ApiError::NotFound("friend request"));
    }
    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn decline(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other): Path<Uuid>,
) -> ApiResult<axum::http::StatusCode> {
    let (low, high) = pair(user.id, other);
    let result = sqlx::query!(
        r#"
        DELETE FROM friendships
        WHERE user_low = $1 AND user_high = $2
          AND status = 'pending'
          AND requested_by <> $3
        "#,
        low,
        high,
        user.id
    )
    .execute(&state.db)
    .await?;

    if result.rows_affected() == 0 {
        return Err(ApiError::NotFound("friend request"));
    }
    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other): Path<Uuid>,
) -> ApiResult<axum::http::StatusCode> {
    let (low, high) = pair(user.id, other);
    sqlx::query!(
        "DELETE FROM friendships WHERE user_low = $1 AND user_high = $2",
        low,
        high
    )
    .execute(&state.db)
    .await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn list(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<Vec<FriendView>>> {
    let rows = sqlx::query!(
        r#"
        SELECT
            u.id, u.handle, u.display_name,
            f.status::text AS "status!",
            (f.requested_by <> $1) AS "incoming!",
            (SELECT count(DISTINCT c.species_key) FROM catches c WHERE c.user_id = u.id) AS "species_count!"
        FROM friendships f
        JOIN users u
          ON u.id = CASE WHEN f.user_low = $1 THEN f.user_high ELSE f.user_low END
        WHERE $1 IN (f.user_low, f.user_high)
        ORDER BY f.status, u.handle
        "#,
        user.id
    )
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| FriendView {
                id: r.id,
                handle: r.handle,
                display_name: r.display_name,
                status: r.status,
                incoming: r.incoming,
                species_count: r.species_count,
            })
            .collect(),
    ))
}

#[derive(Debug, Serialize)]
pub struct DexEntry {
    pub species_key: String,
    pub count: i64,
    pub first_caught: chrono::DateTime<chrono::Utc>,
}

/// A friend's dex.
///
/// The friendship check is the single most likely place in this service to leak
/// another user's data, so it is an explicit precondition with its own test
/// rather than an implicit join condition.
async fn friend_dex(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other): Path<Uuid>,
) -> ApiResult<Json<Vec<DexEntry>>> {
    let (low, high) = pair(user.id, other);

    let accepted = sqlx::query_scalar!(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM friendships
            WHERE user_low = $1 AND user_high = $2 AND status = 'accepted'
        )
        "#,
        low,
        high
    )
    .fetch_one(&state.db)
    .await?
    .unwrap_or(false);

    if !accepted {
        return Err(ApiError::Forbidden("You are not friends with that trainer.".into()));
    }

    let rows = sqlx::query!(
        r#"
        SELECT species_key, count(*) AS "count!", min(caught_at) AS "first_caught!"
        FROM catches
        WHERE user_id = $1
        GROUP BY species_key
        ORDER BY min(caught_at)
        "#,
        other
    )
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| DexEntry {
                species_key: r.species_key,
                count: r.count,
                first_caught: r.first_caught,
            })
            .collect(),
    ))
}
