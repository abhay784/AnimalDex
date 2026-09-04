-- Catches --------------------------------------------------------------------
-- A shared catch. The device keeps its own SwiftData store as the source of
-- truth; only catches the user explicitly shares are pushed here.
CREATE TABLE catches (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Joins to the client-bundled species catalog. Kept as an opaque key rather
    -- than a foreign key: the catalog ships with the app and changes on the
    -- app's release cycle, not the database's.
    species_key  TEXT NOT NULL,
    caught_at    TIMESTAMPTZ NOT NULL,
    confidence   REAL,
    media_id     UUID REFERENCES media_objects(id) ON DELETE SET NULL,

    -- Coordinates are stored as plain doubles and the spatial type is DERIVED
    -- from them. This is the whole trick that keeps PostGIS out of the Rust
    -- layer: queries filter on `location` (indexed, spherical, correct), but
    -- every SELECT returns ordinary f64s, so sqlx never has to decode PostGIS's
    -- binary geometry format and we avoid pulling in geozero for what is only
    -- ever a point.
    lat          DOUBLE PRECISION,
    lng          DOUBLE PRECISION,
    location     geography(Point, 4326)
                 GENERATED ALWAYS AS (
                     CASE WHEN lat IS NULL OR lng IS NULL THEN NULL
                     ELSE ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography END
                 ) STORED,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT coords_paired CHECK ((lat IS NULL) = (lng IS NULL)),
    CONSTRAINT lat_range CHECK (lat IS NULL OR lat BETWEEN -90 AND 90),
    CONSTRAINT lng_range CHECK (lng IS NULL OR lng BETWEEN -180 AND 180),
    CONSTRAINT confidence_range CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1)
);

-- The index that makes radius search cheap. Without it ST_DWithin degrades to a
-- sequential scan over every catch ever shared.
CREATE INDEX catches_location_gix ON catches USING GIST (location);
CREATE INDEX catches_user_idx     ON catches (user_id, caught_at DESC);
CREATE INDEX catches_species_idx  ON catches (species_key);
