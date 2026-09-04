-- Friendships ----------------------------------------------------------------
CREATE TYPE friendship_status AS ENUM ('pending', 'accepted', 'blocked');

-- A friendship is one row for one *pair*, not one row per direction.
--
-- The naive `(user_id, friend_id)` shape lets the same friendship exist twice in
-- mirrored rows, after which every query needs OR clauses that eventually miss a
-- case. Storing the pair in canonical order and making that the primary key
-- makes the duplicate structurally impossible instead of something you have to
-- remember to check.
--
-- `requested_by` preserves direction, which the canonical ordering would
-- otherwise discard - needed to render "wants to be friends" the right way round.
CREATE TABLE friendships (
    user_low     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_high    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       friendship_status NOT NULL DEFAULT 'pending',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,

    PRIMARY KEY (user_low, user_high),
    CONSTRAINT canonical_order CHECK (user_low < user_high),
    CONSTRAINT requester_is_a_party CHECK (requested_by IN (user_low, user_high))
);

CREATE INDEX friendships_high_idx ON friendships (user_high);
CREATE INDEX friendships_status_idx ON friendships (status);
