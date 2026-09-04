use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::ApiError;

/// Access-token claims.
///
/// Short-lived (15 minutes) and never revoked individually — revocation is the
/// refresh token's job. That split is the point: access tokens stay stateless
/// and cheap to verify, while the thing that grants long-lived access lives in
/// the database where it can be killed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessClaims {
    /// Subject — the user id.
    pub sub: Uuid,
    pub handle: String,
    /// Issued at (unix seconds).
    pub iat: i64,
    /// Expiry (unix seconds).
    pub exp: i64,
}

#[derive(Clone)]
pub struct JwtKeys {
    encoding: EncodingKey,
    decoding: DecodingKey,
    validation: Validation,
}

impl JwtKeys {
    pub const ACCESS_TTL_MINUTES: i64 = 15;

    pub fn new(secret: &str) -> Self {
        let mut validation = Validation::new(Algorithm::HS256);
        // `exp` is validated by default; being explicit keeps a future edit from
        // silently turning expiry checking off.
        validation.validate_exp = true;
        validation.leeway = 5;

        Self {
            encoding: EncodingKey::from_secret(secret.as_bytes()),
            decoding: DecodingKey::from_secret(secret.as_bytes()),
            validation,
        }
    }

    pub fn issue_access(&self, user_id: Uuid, handle: &str) -> Result<String, ApiError> {
        let now = Utc::now();
        let claims = AccessClaims {
            sub: user_id,
            handle: handle.to_owned(),
            iat: now.timestamp(),
            exp: (now + Duration::minutes(Self::ACCESS_TTL_MINUTES)).timestamp(),
        };
        encode(&Header::new(Algorithm::HS256), &claims, &self.encoding)
            .map_err(|e| ApiError::Internal(anyhow::anyhow!("jwt encode failed: {e}")))
    }

    /// Any failure collapses to `Unauthorized` on purpose. Distinguishing
    /// "expired" from "bad signature" tells an attacker which half of a forged
    /// token to keep working on.
    pub fn verify_access(&self, token: &str) -> Result<AccessClaims, ApiError> {
        decode::<AccessClaims>(token, &self.decoding, &self.validation)
            .map(|data| data.claims)
            .map_err(|_| ApiError::Unauthorized)
    }
}
