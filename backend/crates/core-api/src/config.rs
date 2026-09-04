use anyhow::{Context, Result};

/// Runtime configuration, read once at boot.
///
/// Everything is required. Defaulting a secret to a placeholder is how a
/// development JWT key ends up signing production tokens, so the service refuses
/// to start rather than guess.
#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub jwt_secret: String,
    pub listen_addr: String,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            database_url: var("DATABASE_URL")?,
            redis_url: var("REDIS_URL")?,
            jwt_secret: var("JWT_SECRET")?,
            listen_addr: std::env::var("CORE_API_ADDR")
                .unwrap_or_else(|_| "0.0.0.0:8080".to_string()),
        })
    }
}

fn var(key: &'static str) -> Result<String> {
    std::env::var(key).with_context(|| format!("{key} must be set (see backend/.env.example)"))
}
