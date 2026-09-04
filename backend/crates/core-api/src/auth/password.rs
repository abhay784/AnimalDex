use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use shared::{ApiError, ApiResult};

/// Argon2id, not bcrypt.
///
/// bcrypt caps the usable password length at 72 bytes and only resists
/// GPU attack; Argon2id is memory-hard, which is what actually makes large-scale
/// cracking expensive, and it is the current OWASP recommendation.
///
/// Default params are deliberate: they encode the tuning (19 MiB, t=2, p=1) that
/// the Argon2 RFC recommends, and hand-picking lower numbers to speed up tests
/// would be exactly the wrong trade.
pub fn hash_password(plain: &str) -> ApiResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(plain.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| ApiError::Internal(anyhow::anyhow!("argon2 hash failed: {e}")))
}

/// Returns false for a wrong password *and* for a malformed stored hash.
///
/// A corrupt hash must not authenticate anyone, and it must not be
/// distinguishable from a wrong password either.
pub fn verify_password(plain: &str, stored_hash: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(stored_hash) else {
        tracing::error!("stored password hash is malformed");
        return false;
    };
    Argon2::default()
        .verify_password(plain.as_bytes(), &parsed)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let hash = hash_password("correct horse battery staple").unwrap();
        assert!(verify_password("correct horse battery staple", &hash));
        assert!(!verify_password("Correct horse battery staple", &hash));
    }

    #[test]
    fn salts_differ_for_identical_passwords() {
        // Two users with the same password must not share a hash, or a single
        // rainbow-table hit compromises both.
        let a = hash_password("hunter2").unwrap();
        let b = hash_password("hunter2").unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn malformed_hash_never_authenticates() {
        assert!(!verify_password("anything", "not-a-phc-string"));
        assert!(!verify_password("anything", ""));
    }
}
