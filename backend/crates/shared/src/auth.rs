use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use uuid::Uuid;

use crate::{ApiError, JwtKeys};

/// Anything that can verify an access token.
///
/// The extractor is generic over this rather than over a concrete `AppState`
/// because both services must authenticate *identically*. If media-svc grew its
/// own copy of this logic, the two could drift — and a divergence in token
/// validation is a security bug, not a style difference.
pub trait HasJwtKeys {
    fn jwt_keys(&self) -> &JwtKeys;
}

/// An authenticated caller.
///
/// Implemented as an extractor so authorisation is visible in a handler's
/// *signature*: a handler taking `AuthUser` cannot be mounted without auth, and
/// one missing it is obviously public. Middleware stuffing a user into request
/// extensions gives no such signal.
#[derive(Debug, Clone)]
pub struct AuthUser {
    pub id: Uuid,
    pub handle: String,
}

impl<S> FromRequestParts<S> for AuthUser
where
    S: HasJwtKeys + Send + Sync,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or(ApiError::Unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .or_else(|| header.strip_prefix("bearer "))
            .ok_or(ApiError::Unauthorized)?;

        let claims = state.jwt_keys().verify_access(token.trim())?;
        Ok(AuthUser { id: claims.sub, handle: claims.handle })
    }
}
