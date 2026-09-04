use axum::extract::{Path, State};
use axum::response::Redirect;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use shared::{ApiError, ApiResult, AuthUser};
use uuid::Uuid;

use crate::state::AppState;
use crate::worker;

/// Formats we accept. An allowlist, not a denylist: "anything but SVG" is how a
/// service ends up serving stored XSS.
const ALLOWED_TYPES: &[&str] = &["image/jpeg", "image/png", "image/heic", "image/heif"];

/// Matches the `byte_size_sane` CHECK in migration 0002.
const MAX_BYTES: i64 = 25 * 1024 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/media/upload-url", post(upload_url))
        .route("/media/{id}/complete", post(complete))
        .route("/media/{id}", get(fetch))
        .route("/health", get(health))
}

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "ok", "service": "media-svc" }))
}

#[derive(Debug, Deserialize)]
pub struct UploadUrlRequest {
    pub content_type: String,
    pub byte_size: i64,
}

#[derive(Debug, Serialize)]
pub struct UploadUrlResponse {
    pub media_id: Uuid,
    pub upload_url: String,
    pub expires_in_secs: u64,
}

/// Issue a presigned PUT so the client uploads straight to object storage.
async fn upload_url(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<UploadUrlRequest>,
) -> ApiResult<Json<UploadUrlResponse>> {
    let content_type = body.content_type.to_lowercase();
    if !ALLOWED_TYPES.contains(&content_type.as_str()) {
        return Err(ApiError::BadRequest(format!(
            "content_type must be one of: {}",
            ALLOWED_TYPES.join(", ")
        )));
    }
    if body.byte_size <= 0 || body.byte_size > MAX_BYTES {
        return Err(ApiError::BadRequest(format!(
            "byte_size must be between 1 and {MAX_BYTES}"
        )));
    }

    crate::ratelimit::check_uploads(&state, user.id).await?;

    let media_id = Uuid::new_v4();
    // Namespaced by owner so a bucket listing is intelligible and per-user
    // lifecycle rules stay possible.
    let key = format!("catches/{}/{}", user.id, media_id);

    sqlx::query!(
        r#"
        INSERT INTO media_objects (id, owner_id, object_key, content_type, status)
        VALUES ($1, $2, $3, $4, 'pending')
        "#,
        media_id,
        user.id,
        key,
        content_type,
    )
    .execute(&state.db)
    .await?;

    Ok(Json(UploadUrlResponse {
        media_id,
        upload_url: state.storage.presign_put(&key, &content_type).to_string(),
        expires_in_secs: crate::storage::Storage::UPLOAD_TTL.as_secs(),
    }))
}

#[derive(Debug, Serialize)]
pub struct MediaView {
    pub id: Uuid,
    pub status: String,
    pub content_type: String,
    pub byte_size: Option<i64>,
}

/// Confirm an upload landed.
///
/// Everything here is re-derived from the object store rather than believed from
/// the client: the presigned URL let them PUT *whatever they liked* under that
/// key, so the size and type they declared earlier are only a hint.
async fn complete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<MediaView>> {
    let media = sqlx::query!(
        "SELECT id, owner_id, object_key, content_type, status::text AS \"status!\" FROM media_objects WHERE id = $1",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("media"))?;

    if media.owner_id != user.id {
        return Err(ApiError::Forbidden("That media does not belong to you.".into()));
    }

    let Some((actual_type, actual_size)) = state
        .storage
        .head(&state.http, &media.object_key)
        .await
        .map_err(ApiError::Internal)?
    else {
        return Err(ApiError::BadRequest("No object was uploaded to that URL.".into()));
    };

    let normalized = actual_type.split(';').next().unwrap_or("").trim().to_lowercase();
    if !ALLOWED_TYPES.contains(&normalized.as_str()) {
        sqlx::query!("UPDATE media_objects SET status = 'failed' WHERE id = $1", id)
            .execute(&state.db)
            .await?;
        return Err(ApiError::BadRequest(format!("Uploaded object is {normalized}, which is not an accepted image type.")));
    }
    if actual_size <= 0 || actual_size > MAX_BYTES {
        sqlx::query!("UPDATE media_objects SET status = 'failed' WHERE id = $1", id)
            .execute(&state.db)
            .await?;
        return Err(ApiError::BadRequest("Uploaded object is empty or too large.".into()));
    }

    sqlx::query!(
        r#"
        UPDATE media_objects
        SET status = 'ready', completed_at = now(), byte_size = $2, content_type = $3
        WHERE id = $1
        "#,
        id,
        actual_size,
        normalized,
    )
    .execute(&state.db)
    .await?;

    // Thumbnailing is queued, not inlined: decoding a 25MB image would block
    // this request for seconds, and the caller does not need the thumbnail to
    // exist before it can carry on.
    worker::enqueue(&state, id).await;

    Ok(Json(MediaView {
        id,
        status: "ready".into(),
        content_type: normalized,
        byte_size: Some(actual_size),
    }))
}

/// Redirect to a short-lived presigned GET.
///
/// A redirect rather than a proxy, for the same reason uploads are presigned:
/// image bytes should never flow through this process.
async fn fetch(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Redirect> {
    let media = sqlx::query!(
        "SELECT object_key, thumb_key, status::text AS \"status!\" FROM media_objects WHERE id = $1",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("media"))?;

    if media.status != "ready" {
        return Err(ApiError::NotFound("media"));
    }

    let key = media.thumb_key.unwrap_or(media.object_key);
    Ok(Redirect::temporary(state.storage.presign_get(&key).as_str()))
}
