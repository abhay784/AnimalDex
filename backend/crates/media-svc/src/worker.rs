use anyhow::{Context, Result};
use image::imageops::FilterType;
use uuid::Uuid;

use crate::state::AppState;

const QUEUE_KEY: &str = "media:thumbnail:queue";
const THUMB_MAX_EDGE: u32 = 512;

/// Push a thumbnail job.
///
/// Best-effort: a lost job costs a thumbnail, and `GET /media/{id}` already
/// falls back to the original. Failing the user's upload because Redis blinked
/// would be a far worse trade.
pub async fn enqueue(state: &AppState, media_id: Uuid) {
    let Some(mut conn) = state.redis.clone() else {
        tracing::warn!("no Redis — skipping thumbnail for {media_id}");
        return;
    };
    if let Err(e) = redis::cmd("RPUSH")
        .arg(QUEUE_KEY)
        .arg(media_id.to_string())
        .query_async::<i64>(&mut conn)
        .await
    {
        tracing::warn!(error = %e, "could not enqueue thumbnail job");
    }
}

/// Long-running consumer. Spawned once at startup.
///
/// Takes its **own** connection rather than cloning the one in `AppState`.
/// `ConnectionManager` is a cloneable handle to a single multiplexed connection,
/// and `BLPOP` is a blocking command that holds it for the duration of its
/// timeout. Sharing it made every request-path Redis call queue behind this
/// loop: presigned-URL issuance measured ~5s per request, exactly the BLPOP
/// timeout, which in turn made the fixed-window rate limiter untestable because
/// its window expired faster than 30 requests could complete.
pub async fn run(state: AppState, mut conn: redis::aio::MultiplexedConnection) {
    tracing::info!("thumbnail worker started");

    loop {
        // BLPOP blocks server-side rather than polling, so an idle worker costs
        // one connection and no CPU.
        let popped: Option<(String, String)> = match redis::cmd("BLPOP")
            .arg(QUEUE_KEY)
            .arg(5.0)
            .query_async(&mut conn)
            .await
        {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!(error = %e, "BLPOP failed; backing off");
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                continue;
            }
        };

        let Some((_, raw_id)) = popped else { continue };
        let Ok(media_id) = raw_id.parse::<Uuid>() else {
            tracing::warn!(raw_id, "queue held a malformed id");
            continue;
        };

        if let Err(e) = process(&state, media_id).await {
            // A failed thumbnail is not a failed upload — the original is still
            // served. Log and move on rather than retrying forever on an image
            // that will never decode.
            tracing::error!(error = ?e, %media_id, "thumbnail generation failed");
        }
    }
}

async fn process(state: &AppState, media_id: Uuid) -> Result<()> {
    let media = sqlx::query!(
        "SELECT object_key, content_type FROM media_objects WHERE id = $1 AND status = 'ready'",
        media_id
    )
    .fetch_optional(&state.db)
    .await?;

    let Some(media) = media else { return Ok(()) };

    let bytes = state
        .storage
        .get_bytes(&state.http, &media.object_key)
        .await
        .context("could not fetch original")?;

    // Decoding is CPU-bound and can take hundreds of milliseconds on a large
    // photo. On the async runtime that would stall every other task on the
    // thread, so it goes to the blocking pool.
    let thumb = tokio::task::spawn_blocking(move || -> Result<Vec<u8>> {
        let image = image::load_from_memory(&bytes).context("undecodable image")?;
        // `thumbnail` preserves aspect ratio and only ever shrinks.
        let resized = image.resize(THUMB_MAX_EDGE, THUMB_MAX_EDGE, FilterType::Lanczos3);
        let mut out = std::io::Cursor::new(Vec::new());
        resized
            .to_rgb8()
            .write_to(&mut out, image::ImageFormat::Jpeg)
            .context("could not encode thumbnail")?;
        Ok(out.into_inner())
    })
    .await
    .context("thumbnail task panicked")??;

    let thumb_key = format!("{}_thumb.jpg", media.object_key);
    state
        .storage
        .put_bytes(&state.http, &thumb_key, "image/jpeg", thumb)
        .await
        .context("could not upload thumbnail")?;

    sqlx::query!(
        "UPDATE media_objects SET thumb_key = $2 WHERE id = $1",
        media_id,
        thumb_key
    )
    .execute(&state.db)
    .await?;

    tracing::info!(%media_id, "thumbnail ready");
    Ok(())
}
