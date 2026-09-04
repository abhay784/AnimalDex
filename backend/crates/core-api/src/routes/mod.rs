pub mod catches;
pub mod friends;
pub mod health;

use uuid::Uuid;

use crate::state::AppState;

/// Drop a user's cached catch list after they write.
///
/// Best-effort by design: a failed invalidation means someone sees a slightly
/// stale list for the remainder of a short TTL, which is not worth failing their
/// write over.
pub async fn invalidate_user_cache(state: &AppState, user_id: Uuid) {
    let Some(mut conn) = state.redis.clone() else { return };
    let key = format!("catches:user:{user_id}");
    if let Err(e) = redis::cmd("DEL").arg(&key).query_async::<i64>(&mut conn).await {
        tracing::warn!(error = %e, "cache invalidation failed");
    }
}
