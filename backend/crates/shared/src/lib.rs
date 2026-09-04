//! Types shared by `core-api` and `media-svc`.
//!
//! Deliberately small. Two services sharing a crate is convenient right up until
//! the crate becomes a dumping ground and the "separate" services are welded
//! together by it. What lives here is only what genuinely must agree across the
//! boundary: the error contract, and how a JWT is verified.

pub mod error;
pub mod jwt;
pub mod telemetry;

pub use error::{ApiError, ApiResult};
pub use jwt::{AccessClaims, JwtKeys};
