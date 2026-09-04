use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;

/// Every error the API can return.
///
/// One enum rather than per-module error types, because the thing that matters
/// at the boundary is the *shape of the response*, and that must be identical
/// across both services or clients end up special-casing endpoints.
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),

    #[error("authentication required")]
    Unauthorized,

    #[error("{0}")]
    Forbidden(String),

    #[error("{0} not found")]
    NotFound(&'static str),

    #[error("{0}")]
    Conflict(String),

    #[error("rate limit exceeded")]
    TooManyRequests { retry_after_secs: u64 },

    #[error("database error")]
    Database(#[from] sqlx::Error),

    #[error("internal error")]
    Internal(#[from] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorBody {
    error: ErrorDetail,
}

#[derive(Serialize)]
struct ErrorDetail {
    /// Stable machine-readable code. Clients branch on this, never on `message`.
    code: &'static str,
    message: String,
}

impl ApiError {
    fn parts(&self) -> (StatusCode, &'static str) {
        match self {
            Self::BadRequest(_) => (StatusCode::BAD_REQUEST, "bad_request"),
            Self::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            Self::Forbidden(_) => (StatusCode::FORBIDDEN, "forbidden"),
            Self::NotFound(_) => (StatusCode::NOT_FOUND, "not_found"),
            Self::Conflict(_) => (StatusCode::CONFLICT, "conflict"),
            Self::TooManyRequests { .. } => (StatusCode::TOO_MANY_REQUESTS, "rate_limited"),
            Self::Database(_) | Self::Internal(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "internal")
            }
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code) = self.parts();

        // Internal failures are logged in full but never described to the
        // caller: a database error message can leak schema, and an auth-adjacent
        // one can confirm which half of a credential was wrong.
        let message = match &self {
            Self::Database(e) => {
                tracing::error!(error = ?e, "database error");
                "Something went wrong.".to_string()
            }
            Self::Internal(e) => {
                tracing::error!(error = ?e, "internal error");
                "Something went wrong.".to_string()
            }
            other => other.to_string(),
        };

        let mut response = (
            status,
            Json(ErrorBody { error: ErrorDetail { code, message } }),
        )
            .into_response();

        if let Self::TooManyRequests { retry_after_secs } = self {
            if let Ok(value) = retry_after_secs.to_string().parse() {
                response.headers_mut().insert(axum::http::header::RETRY_AFTER, value);
            }
        }
        response
    }
}

pub type ApiResult<T> = Result<T, ApiError>;
