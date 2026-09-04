-- Media objects --------------------------------------------------------------
-- Photos are uploaded straight to object storage with a presigned URL; they
-- never proxy through the API. A row is created in 'pending' when the URL is
-- issued and only becomes 'ready' once the client confirms and the service has
-- verified the object actually exists with a sane content type and size.
--
-- A presigned URL is not a trust boundary: the client controls what it PUTs, so
-- the declared content type and size are re-checked server-side on completion.
CREATE TYPE media_status AS ENUM ('pending', 'ready', 'failed');

CREATE TABLE media_objects (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    object_key    TEXT NOT NULL UNIQUE,
    thumb_key     TEXT,
    content_type  TEXT NOT NULL,
    byte_size     BIGINT,
    status        media_status NOT NULL DEFAULT 'pending',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at  TIMESTAMPTZ,

    CONSTRAINT byte_size_sane CHECK (byte_size IS NULL OR byte_size BETWEEN 1 AND 26214400)
);

CREATE INDEX media_owner_idx  ON media_objects (owner_id);
CREATE INDEX media_status_idx ON media_objects (status) WHERE status = 'pending';
