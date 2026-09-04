use redis::aio::ConnectionManager;
use shared::JwtKeys;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    /// Redis is an optimisation (cache) and a guard rail (rate limits), never a
    /// source of truth — so it is `Option`. If Redis is down the service should
    /// degrade to "slower and more permissive", not fall over.
    pub redis: Option<ConnectionManager>,
    pub jwt: JwtKeys,
}
