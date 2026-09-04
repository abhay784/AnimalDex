use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use shared::ApiError;
use uuid::Uuid;

use crate::state::AppState;

/// An authenticated caller.
///
/// Implemented as an extractor so authorisation is expressed in the handler's
/// *signature*: a handler that takes `AuthUser` cannot be routed without auth,
/// and one that forgets it is visibly public. Middleware that stuffs a user into
/// request extensions gives no such compile-time signal.
#[derive(Debug, Clone)]
pub struct AuthUser {
    pub id: Uuid,
    pub handle: String,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or(ApiError::Unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .or_else(|| header.strip_prefix("bearer "))
            .ok_or(ApiError::Unauthorized)?;

        let claims = state.jwt.verify_access(token.trim())?;
        Ok(AuthUser { id: claims.sub, handle: claims.handle })
    }
}
