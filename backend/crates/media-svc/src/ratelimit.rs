use shared::{ApiError, ApiResult};
use uuid::Uuid;

use crate::state::AppState;

/// Uploads a user may request per window.
const UPLOAD_LIMIT: u64 = 30;
const WINDOW_SECS: u64 = 60;

/// Fixed-window rate limit on presigned-URL issuance.
///
/// The abuse this actually prevents is someone minting thousands of upload URLs
/// and filling the bucket — which costs money and is invisible until the bill
/// arrives, since the bytes never touch our servers.
///
/// **Fails open.** If Redis is down the request is allowed: losing the cache
/// should not take down uploads. That is the right trade here because the limit
/// guards cost, not correctness or authorization — a limiter protecting auth
/// should fail closed instead.
pub async fn check_uploads(state: &AppState, user_id: Uuid) -> ApiResult<()> {
    let Some(mut conn) = state.redis.clone() else { return Ok(()) };

    let key = format!("rl:upload:{user_id}");

    // INCR then conditionally EXPIRE, pipelined so it is one round trip. The
    // first request in a window creates the key and sets its TTL; later ones
    // just increment.
    let (count,): (u64,) = match redis::pipe()
        .atomic()
        .cmd("INCR").arg(&key)
        .cmd("EXPIRE").arg(&key).arg(WINDOW_SECS).arg("NX").ignore()
        .query_async(&mut conn)
        .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(error = %e, "rate limiter unavailable — allowing request");
            return Ok(());
        }
    };

    if count > UPLOAD_LIMIT {
        let ttl: i64 = redis::cmd("TTL")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .unwrap_or(WINDOW_SECS as i64);
        return Err(ApiError::TooManyRequests {
            retry_after_secs: ttl.max(1) as u64,
        });
    }
    Ok(())
}
