use redis::aio::ConnectionManager;
use shared::{HasJwtKeys, JwtKeys};
use sqlx::PgPool;

use crate::storage::Storage;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: Option<ConnectionManager>,
    pub jwt: JwtKeys,
    pub storage: Storage,
    /// One shared client so connections are pooled and TLS is set up once.
    pub http: reqwest::Client,
}

impl HasJwtKeys for AppState {
    fn jwt_keys(&self) -> &JwtKeys {
        &self.jwt
    }
}
