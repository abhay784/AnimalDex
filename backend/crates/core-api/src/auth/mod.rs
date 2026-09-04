pub mod extractor;
pub mod password;
pub mod tokens;

pub use extractor::AuthUser;

use axum::extract::State;
use axum::http::HeaderMap;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use shared::{ApiError, ApiResult};
use uuid::Uuid;
use validator::Validate;

use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
        .route("/auth/logout", post(logout))
        .route("/auth/me", get(me))
}

// MARK: - Payloads

#[derive(Debug, Deserialize, Validate)]
pub struct RegisterRequest {
    #[validate(custom(function = "validate_handle"))]
    pub handle: String,
    #[validate(email(message = "must be a valid email address"))]
    pub email: String,
    #[validate(length(min = 10, message = "must be at least 10 characters"))]
    pub password: String,
    #[validate(length(min = 1, max = 40))]
    pub display_name: String,
}

/// Mirrors the `handle_format` CHECK constraint in migration 0001.
///
/// A plain character scan rather than a regex: the rule is simple enough that a
/// regex dependency (and a lazily-compiled global) buys nothing, and this gives
/// a better error message than a pattern mismatch would.
fn validate_handle(handle: &str) -> Result<(), validator::ValidationError> {
    let len = handle.chars().count();
    if !(3..=24).contains(&len) {
        return Err(validator::ValidationError::new("handle_length")
            .with_message("must be 3-24 characters".into()));
    }
    if !handle.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return Err(validator::ValidationError::new("handle_charset")
            .with_message("may only contain letters, numbers and underscores".into()));
    }
    Ok(())
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub handle: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
    pub user: UserProfile,
}

#[derive(Debug, Serialize)]
pub struct UserProfile {
    pub id: Uuid,
    pub handle: String,
    pub display_name: String,
}

// MARK: - Handlers

async fn register(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<RegisterRequest>,
) -> ApiResult<Json<TokenPair>> {
    body.validate()
        .map_err(|e| ApiError::BadRequest(format_validation(&e)))?;

    let hash = password::hash_password(&body.password)?;

    let user = sqlx::query!(
        r#"
        INSERT INTO users (handle, email, password_hash, display_name)
        VALUES ($1, $2, $3, $4)
        RETURNING id, handle, display_name
        "#,
        body.handle,
        body.email,
        hash,
        body.display_name,
    )
    .fetch_one(&state.db)
    .await
    .map_err(|e| match &e {
        // 23505 is unique_violation. The message deliberately does not say
        // *which* field collided: "that email is taken" is a free account-
        // existence oracle.
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            ApiError::Conflict("That handle or email is already registered.".into())
        }
        _ => ApiError::Database(e),
    })?;

    issue_pair(&state, user.id, &user.handle, &user.display_name, &headers).await
}

async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<LoginRequest>,
) -> ApiResult<Json<TokenPair>> {
    let user = sqlx::query!(
        "SELECT id, handle, display_name, password_hash FROM users WHERE handle = $1",
        body.handle
    )
    .fetch_optional(&state.db)
    .await?;

    // Verify against a dummy hash when the user does not exist, so that a
    // missing account and a wrong password take the same wall-clock time.
    // Skipping the Argon2 work on the "no such user" path leaks account
    // existence through a timing side channel.
    const DUMMY_HASH: &str = "$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHRzb21lc2FsdA$Yl5VmVdMTGE1Cm7ZM/uZBCEwQFN5nHhSVGpo6qsYhqQ";

    let Some(user) = user else {
        let _ = password::verify_password(&body.password, DUMMY_HASH);
        return Err(ApiError::Unauthorized);
    };

    if !password::verify_password(&body.password, &user.password_hash) {
        return Err(ApiError::Unauthorized);
    }

    issue_pair(&state, user.id, &user.handle, &user.display_name, &headers).await
}

async fn refresh(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<RefreshRequest>,
) -> ApiResult<Json<TokenPair>> {
    let agent = user_agent(&headers);
    let (user_id, issued) = tokens::rotate(&state.db, &body.refresh_token, agent.as_deref()).await?;

    let user = sqlx::query!(
        "SELECT handle, display_name FROM users WHERE id = $1",
        user_id
    )
    .fetch_one(&state.db)
    .await?;

    let access = state.jwt.issue_access(user_id, &user.handle)?;

    Ok(Json(TokenPair {
        access_token: access,
        refresh_token: issued.token,
        expires_in: shared::JwtKeys::ACCESS_TTL_MINUTES * 60,
        user: UserProfile { id: user_id, handle: user.handle, display_name: user.display_name },
    }))
}

async fn logout(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> ApiResult<axum::http::StatusCode> {
    tokens::revoke_family(&state.db, &body.refresh_token).await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn me(State(state): State<AppState>, user: AuthUser) -> ApiResult<Json<UserProfile>> {
    let row = sqlx::query!(
        "SELECT id, handle, display_name FROM users WHERE id = $1",
        user.id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(ApiError::NotFound("user"))?;

    Ok(Json(UserProfile { id: row.id, handle: row.handle, display_name: row.display_name }))
}

// MARK: - Helpers

async fn issue_pair(
    state: &AppState,
    user_id: Uuid,
    handle: &str,
    display_name: &str,
    headers: &HeaderMap,
) -> ApiResult<Json<TokenPair>> {
    let access = state.jwt.issue_access(user_id, handle)?;
    let agent = user_agent(headers);
    let refresh = tokens::issue_new_family(&state.db, user_id, agent.as_deref()).await?;

    Ok(Json(TokenPair {
        access_token: access,
        refresh_token: refresh.token,
        expires_in: shared::JwtKeys::ACCESS_TTL_MINUTES * 60,
        user: UserProfile {
            id: user_id,
            handle: handle.to_owned(),
            display_name: display_name.to_owned(),
        },
    }))
}

fn user_agent(headers: &HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::USER_AGENT)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.chars().take(200).collect())
}

fn format_validation(errors: &validator::ValidationErrors) -> String {
    errors
        .field_errors()
        .iter()
        .flat_map(|(field, errs)| {
            errs.iter().map(move |e| {
                let msg = e.message.clone().unwrap_or_else(|| "is invalid".into());
                format!("{field} {msg}")
            })
        })
        .collect::<Vec<_>>()
        .join("; ")
}
