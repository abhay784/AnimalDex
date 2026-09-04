-- Extensions -----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";     -- case-insensitive handles/emails
CREATE EXTENSION IF NOT EXISTS "postgis";    -- spatial types + GIST indexing

-- Users ----------------------------------------------------------------------
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    handle        CITEXT NOT NULL UNIQUE,
    email         CITEXT NOT NULL UNIQUE,
    -- Argon2id PHC string. Never a plaintext or reversible value.
    password_hash TEXT   NOT NULL,
    display_name  TEXT   NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Handles appear in URLs and friend search, so constrain them at the schema
    -- level rather than trusting every future call site to validate.
    CONSTRAINT handle_format CHECK (handle ~ '^[a-zA-Z0-9_]{3,24}$')
);

-- Refresh tokens -------------------------------------------------------------
-- Rotation with reuse detection: each refresh issues a new token and consumes
-- the old one. Presenting an already-consumed token means it leaked, so the
-- entire family is revoked rather than just that one token.
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- SHA-256 of the opaque token. A database dump must not yield usable
    -- credentials, so the raw token is never stored.
    token_hash  TEXT NOT NULL UNIQUE,
    -- Shared by every token descended from one login.
    family_id   UUID NOT NULL,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    user_agent  TEXT
);

CREATE INDEX refresh_tokens_user_idx   ON refresh_tokens (user_id);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);

-- Housekeeping ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_touch_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
