use serde::{de::DeserializeOwned, Serialize};
use shared::{ApiError, ApiResult};
use uuid::Uuid;

use crate::state::AppState;

/// Cache and rate-limit helpers.
///
/// Everything here degrades gracefully. Redis backs an optimisation and a cost
/// guard rail, never correctness or authorization, so an outage should make the
/// service slower and more permissive — not broken.

/// Read a cached JSON value. A miss, a decode failure, and an outage are all
/// just "not cached".
pub async fn get_json<T: DeserializeOwned>(state: &AppState, key: &str) -> Option<T> {
    let mut conn = state.redis.clone()?;
    let raw: Option<String> = redis::cmd("GET").arg(key).query_async(&mut conn).await.ok()?;
    serde_json::from_str(&raw?).ok()
}

pub async fn set_json<T: Serialize>(state: &AppState, key: &str, value: &T, ttl_secs: u64) {
    let Some(mut conn) = state.redis.clone() else { return };
    let Ok(encoded) = serde_json::to_string(value) else { return };
    if let Err(e) = redis::cmd("SET")
        .arg(key)
        .arg(encoded)
        .arg("EX")
        .arg(ttl_secs)
        .query_async::<()>(&mut conn)
        .await
    {
        tracing::warn!(error = %e, "cache write failed");
    }
}

/// Fixed-window limiter.
///
/// **Fails open**, for the same reason as the upload limiter: it guards cost and
/// nuisance, not access. A limiter in front of authentication should fail closed
/// instead — the trade is different when the thing being protected is a secret.
pub async fn check_limit(
    state: &AppState,
    scope: &str,
    user_id: Uuid,
    limit: u64,
    window_secs: u64,
) -> ApiResult<()> {
    let Some(mut conn) = state.redis.clone() else { return Ok(()) };
    let key = format!("rl:{scope}:{user_id}");

    // INCR plus a conditional EXPIRE in one round trip: the first request of a
    // window creates the key and stamps its TTL, later ones only increment.
    let (count,): (u64,) = match redis::pipe()
        .atomic()
        .cmd("INCR").arg(&key)
        .cmd("EXPIRE").arg(&key).arg(window_secs).arg("NX").ignore()
        .query_async(&mut conn)
        .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(error = %e, "rate limiter unavailable — allowing request");
            return Ok(());
        }
    };

    if count > limit {
        let ttl: i64 = redis::cmd("TTL")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .unwrap_or(window_secs as i64);
        return Err(ApiError::TooManyRequests { retry_after_secs: ttl.max(1) as u64 });
    }
    Ok(())
}

/// Monotonic version stamped into every geo cache key.
///
/// Precise invalidation of a spatial cache is genuinely hard: a new catch
/// invalidates every cached radius whose circle contains it, which you cannot
/// enumerate without scanning. Versioning sidesteps the problem — bumping the
/// counter makes every existing geo key unreachable at once, and the orphans
/// expire on their own TTL. Costs one INCR per write and one GET per read.
pub async fn geo_version(state: &AppState) -> u64 {
    let Some(mut conn) = state.redis.clone() else { return 0 };
    redis::cmd("GET")
        .arg("geo:version")
        .query_async::<Option<u64>>(&mut conn)
        .await
        .ok()
        .flatten()
        .unwrap_or(0)
}

/// Call after any write that could change what a radius search returns.
pub async fn bump_geo_version(state: &AppState) {
    let Some(mut conn) = state.redis.clone() else { return };
    if let Err(e) = redis::cmd("INCR").arg("geo:version").query_async::<i64>(&mut conn).await {
        tracing::warn!(error = %e, "could not bump geo cache version");
    }
}

/// Cache key for a radius search.
///
/// Coordinates are bucketed to ~110m (3 decimal places) so that two people
/// standing near each other share a cache entry. Keying on raw floats would make
/// every request a miss and the cache pure overhead.
pub fn nearby_key(version: u64, lat: f64, lng: f64, radius_m: f64, limit: i64) -> String {
    format!(
        "geo:nearby:v{}:{:.3}:{:.3}:{}:{}",
        version,
        lat,
        lng,
        radius_m.round() as i64,
        limit
    )
}
