use chrono::{Duration, Utc};
use rand::RngCore;
use sha2::{Digest, Sha256};
use shared::{ApiError, ApiResult};
use sqlx::PgPool;
use uuid::Uuid;

pub const REFRESH_TTL_DAYS: i64 = 30;

/// A freshly minted refresh token. The plaintext exists only in this struct and
/// in the response body — the database sees only its hash.
pub struct IssuedRefresh {
    pub token: String,
    pub family_id: Uuid,
}

/// 256 bits from the OS CSPRNG, hex-encoded. Opaque by design: unlike a JWT,
/// there is nothing in it to parse, so there is nothing to forge.
fn generate_token() -> String {
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Refresh tokens are stored hashed for the same reason passwords are: a stolen
/// database dump must not be a stack of working credentials. SHA-256 rather than
/// Argon2 is right here — the token is already 256 bits of entropy, so there is
/// no dictionary to slow an attacker down against, and refresh happens often
/// enough that a memory-hard hash would be a real cost for no gain.
fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// Start a new token family. One family per login/device.
pub async fn issue_new_family(
    db: &PgPool,
    user_id: Uuid,
    user_agent: Option<&str>,
) -> ApiResult<IssuedRefresh> {
    let family_id = Uuid::new_v4();
    let token = generate_token();

    sqlx::query!(
        r#"
        INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at, user_agent)
        VALUES ($1, $2, $3, $4, $5)
        "#,
        user_id,
        hash_token(&token),
        family_id,
        Utc::now() + Duration::days(REFRESH_TTL_DAYS),
        user_agent,
    )
    .execute(db)
    .await?;

    Ok(IssuedRefresh { token, family_id })
}

/// Exchange a refresh token for the next one in its family.
///
/// **Reuse detection.** Rotation alone is not enough: if an attacker steals a
/// refresh token and uses it, both they and the legitimate user now hold tokens,
/// and rotation just means whoever refreshes second gets rejected — with no
/// signal that anything was wrong. So a token that has *already been consumed*
/// is treated as proof of compromise and revokes the whole family, forcing a
/// real re-login. The legitimate user gets logged out once; the attacker loses
/// persistent access entirely.
///
/// The whole exchange runs in one transaction so two concurrent refreshes cannot
/// both observe an unconsumed token and both succeed.
pub async fn rotate(
    db: &PgPool,
    presented: &str,
    user_agent: Option<&str>,
) -> ApiResult<(Uuid, IssuedRefresh)> {
    let presented_hash = hash_token(presented);
    let mut tx = db.begin().await?;

    let row = sqlx::query!(
        r#"
        SELECT id, user_id, family_id, expires_at, consumed_at, revoked_at
        FROM refresh_tokens
        WHERE token_hash = $1
        FOR UPDATE
        "#,
        presented_hash
    )
    .fetch_optional(&mut *tx)
    .await?;

    let Some(row) = row else {
        return Err(ApiError::Unauthorized);
    };

    if row.revoked_at.is_some() {
        return Err(ApiError::Unauthorized);
    }

    if row.consumed_at.is_some() {
        // Replay. Burn the family.
        tracing::warn!(
            user_id = %row.user_id,
            family_id = %row.family_id,
            "refresh token reuse detected - revoking family"
        );
        sqlx::query!(
            "UPDATE refresh_tokens SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL",
            row.family_id
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        return Err(ApiError::Unauthorized);
    }

    if row.expires_at <= Utc::now() {
        return Err(ApiError::Unauthorized);
    }

    sqlx::query!("UPDATE refresh_tokens SET consumed_at = now() WHERE id = $1", row.id)
        .execute(&mut *tx)
        .await?;

    let token = generate_token();
    sqlx::query!(
        r#"
        INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at, user_agent)
        VALUES ($1, $2, $3, $4, $5)
        "#,
        row.user_id,
        hash_token(&token),
        row.family_id,
        Utc::now() + Duration::days(REFRESH_TTL_DAYS),
        user_agent,
    )
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok((row.user_id, IssuedRefresh { token, family_id: row.family_id }))
}

/// Log out: revoke the presented token's whole family, so every device sharing
/// that login loses access.
pub async fn revoke_family(db: &PgPool, presented: &str) -> ApiResult<()> {
    sqlx::query!(
        r#"
        UPDATE refresh_tokens SET revoked_at = now()
        WHERE family_id = (SELECT family_id FROM refresh_tokens WHERE token_hash = $1)
          AND revoked_at IS NULL
        "#,
        hash_token(presented)
    )
    .execute(db)
    .await?;
    Ok(())
}
