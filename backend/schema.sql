-- Kinlore — D1 schema
--
-- The core insight: a photo, a person, a place and an event are all a `subject`.
-- A memory attaches to any subject. That is why "write a memory about this
-- photo" and "write what grandmother was like" are the same screen and the same
-- code path — not three parallel implementations. The family tree is the edges
-- between person subjects.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------- family

CREATE TABLE family (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  -- Channel-level entitlement: one payer opens the whole family. Not per user.
  entitlement   TEXT NOT NULL DEFAULT 'free',   -- 'free' | 'archive'
  -- Who is paying right now. Reset to NULL when the subscription ends.
  payer_id      TEXT,
  -- When the entitlement lapses. With two payers, the longest expiry wins.
  entitlement_expires_at INTEGER,
  -- Sync ordering counter. Incremented on every write. Device clocks cannot be
  -- trusted: an elderly user's phone can have the wrong time zone for years,
  -- and timestamp ordering would produce silently lost writes.
  sync_seq      INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE TABLE member (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL,
  -- SHA-256 of the device secret. The secret is 32 random bytes rather than a
  -- password, so a slow hash would buy nothing: there is no guessability.
  -- It is still stored hashed so that a database leak grants no access.
  secret_hash   TEXT NOT NULL,
  -- Only on the payer. RevenueCat's webhooks land on this.
  rc_app_user_id TEXT,
  -- When THIS member's own subscription runs out, or NULL if they have none.
  --
  -- `family.entitlement_expires_at` beside it is the answer, and this is the
  -- working. Until 10 Sep 2026 only the answer was stored, so a second payer's
  -- date was compared, found nearer, and thrown away — and when the recorded
  -- payer's own date then arrived, the family went free with somebody's live
  -- subscription still running. A grandchild on an annual plan and one on a
  -- monthly plan is not an exotic case; it is the case `applyEntitlement`'s
  -- own comment says it is handling.
  --
  -- The family's right is the furthest date anybody in it holds, so it is a
  -- MAX over this column and no longer a comparison against a single stored
  -- winner. For an existing database, the ALTER and the backfill that keeps a
  -- paying family paying across the change — without the second statement the
  -- next event recomputes a family whose members all read NULL and takes the
  -- tier away:
  --
  --   ALTER TABLE member ADD COLUMN entitlement_expires_at INTEGER;
  --   UPDATE member SET entitlement_expires_at = (
  --     SELECT f.entitlement_expires_at FROM family f WHERE f.id = member.family_id
  --   ) WHERE id IN (SELECT payer_id FROM family WHERE payer_id IS NOT NULL);
  --
  entitlement_expires_at INTEGER,
  role          TEXT NOT NULL DEFAULT 'member',  -- 'owner' | 'member'
  -- The member's own person card in the tree. A member is a subject just as
  -- much as a dead relative is.
  --
  -- Declared since the first schema and written by nothing until 13 Sep 2026.
  -- Now `PATCH /family/me` sets one's own (NULL unlinks), the join sets it
  -- from an invitation that names a card, and `GET /family` reads it back.
  --
  -- The foreign key is ENFORCED, and every write here is shaped by that. D1
  -- enforces foreign keys on every query and a query cannot turn them off —
  -- `PRAGMA defer_foreign_keys` only moves the check to the end of the
  -- transaction (Cloudflare's D1 documentation, "Foreign keys"). Measured on
  -- 13 Sep 2026 against the local D1: a member row naming a subject that is
  -- not there fails with `FOREIGN KEY constraint failed`. A card reaches this
  -- database only when the phone that made it syncs, so no statement writes
  -- an id here unless the same statement finds a live person card of the
  -- member's own family under it; otherwise the link stays NULL. The join
  -- claims its code before it inserts the member, so a join that failed on
  -- this column would burn the invitation it came through.
  person_subject_id TEXT REFERENCES subject(id),
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER,
  -- When they left the family, or NULL while they are in it.
  --
  -- The row is NEVER deleted, for two reasons that both point the same way:
  -- `memory.author_id` references it, and the name shown on a memory is derived
  -- from `display_name` on read. Deleting a departing member would either fail
  -- on the foreign key or, worse, quietly strip the teller's name off
  -- everything they ever told. Leaving ends the membership; it does not
  -- unwrite the past. See docs/ARCHITECTURE.md §14.
  --   ALTER TABLE member ADD COLUMN left_at INTEGER;
  left_at       INTEGER
);

-- Invite links. Their own table rather than a column on family, because a link
-- has to be able to expire and be revoked individually: the link is the entire
-- security boundary, and anyone who receives it sees all of the family's
-- memories.
CREATE TABLE invite (
  code          TEXT PRIMARY KEY,     -- 22 chars base64url, not meant to be read
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  created_by    TEXT NOT NULL REFERENCES member(id),
  expires_at    INTEGER NOT NULL,
  revoked_at    INTEGER,
  -- Since 5 Sep 2026 a code admits one person: the join claims it with
  -- `UPDATE … WHERE used_count = 0`, so on any row written since this is 0 or
  -- 1, and the family view lists only the zeros. Older rows may carry a higher
  -- number — it was recorded and compared to nothing, which is what made one
  -- forwarded link a week-long key for a whole group chat.
  used_count    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  -- Who the invitation is for, written by whoever created it.
  --
  -- The join form asks the joiner for their own name, and the joiner is the
  -- 80-year-old: a keyboard on the one path rule 1 most wanted to keep clear.
  -- The person who creates the invitation already knows the answer, so the
  -- answer travels with the invitation and is applied on join when the field
  -- was left empty.
  --
  -- It is never handed back before joining, and that is a boundary and not an
  -- oversight: an unauthenticated lookup that answered for a real code and not
  -- for a wrong one would hand a guesser the oracle §4 exists to deny.
  --   ALTER TABLE invite ADD COLUMN display_name TEXT;
  display_name  TEXT,
  -- The person card the invitation was made for, when the phone that made it
  -- had one — the first minute's answer to "whose memories" (FirstMinuteSheet).
  -- The join links whoever comes through the code to that card, so the
  -- grandmother who opens the link becomes the card her grandchild made.
  --
  -- No REFERENCES, on purpose, unlike `member.person_subject_id` above. The
  -- card is made on a phone and reaches D1 with that phone's next sync, and an
  -- enforced foreign key here would refuse the invitation whenever it was the
  -- quicker of the two. So the id is kept as sent and asked about where it is
  -- used: the join links only to a live person card of this invitation's own
  -- family, and without one joins unlinked. Like `display_name`, never handed
  -- out before joining. Since 13 Sep 2026; for an existing database:
  --   ALTER TABLE invite ADD COLUMN person_subject_id TEXT;
  person_subject_id TEXT
);

CREATE INDEX idx_invite_family ON invite(family_id);

CREATE INDEX idx_member_family ON member(family_id);
-- UNIQUE, and that is the point rather than a tidiness. `syncEntitlement` takes
-- the customer id from the client and asks RevenueCat what that customer owns,
-- so without this one purchase reported from two families unlocks both of them.
--
-- The worse half is the webhook: it finds the payer with
-- `WHERE rc_app_user_id = ?` and takes the first row, so a refund would revoke
-- the right from one family and leave the other paid for ever. An error in that
-- direction does not correct itself.
--
-- Partial, because most members never buy anything and NULL is not a claim.
-- SQLite treats NULLs as distinct in a unique index anyway; the WHERE clause
-- says so out loud and keeps the index small.
--
-- On a database that already exists:
--
--   DROP INDEX IF EXISTS idx_member_rc;
--   CREATE UNIQUE INDEX idx_member_rc ON member(rc_app_user_id)
--     WHERE rc_app_user_id IS NOT NULL;
--
CREATE UNIQUE INDEX idx_member_rc ON member(rc_app_user_id)
  WHERE rc_app_user_id IS NOT NULL;

-- ---------------------------------------------------------------- subject

CREATE TABLE subject (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,        -- 'photo' | 'person' | 'place' | 'event'
  -- Titles are Finnish, as the app is: "Isoäiti Aino" (Grandmother Aino),
  -- "Kesämökki Puumalassa" (Summer cottage in Puumala).
  title         TEXT,

  -- kind = 'photo'
  r2_key        TEXT,
  -- The photograph's colours as the family confirmed them: an R2 object of
  -- their own beside r2_key's photograph, never in its place, and only once
  -- somebody has looked at a colouring and said yes. Who said it and when
  -- travel with it: the newest yes wins, and a member can put only their own
  -- name on one. For existing databases:
  --   ALTER TABLE subject ADD COLUMN colour_r2_key TEXT;
  --   ALTER TABLE subject ADD COLUMN colour_confirmed_by TEXT REFERENCES member(id);
  --   ALTER TABLE subject ADD COLUMN colour_confirmed_at INTEGER;
  colour_r2_key       TEXT,
  colour_confirmed_by TEXT REFERENCES member(id),
  colour_confirmed_at INTEGER,

  -- kind = 'place'
  --
  -- Where the place is, once its name has been looked up. A place is born as a
  -- name somebody said out loud ("Puumala", "Sortavala") and stays that way:
  -- these two columns are a cache of a lookup, never something the family
  -- provided. NULL means nobody has looked it up yet, or no gazetteer knew the
  -- name — a village that no longer exists is a real case here.
  lat           REAL,
  lon           REAL,
  -- How precisely the coordinates locate the memory, in the same spirit as
  -- date_precision: 'exact' is a street address, 'town' a municipality,
  -- 'region' a province or a country. "Karjala" is a region, and drawing it as
  -- a pin would claim a metre of accuracy nobody ever had. Rule 5: uncertainty
  -- is stored, not rounded. For existing databases:
  --   ALTER TABLE subject ADD COLUMN lat REAL;
  --   ALTER TABLE subject ADD COLUMN lon REAL;
  --   ALTER TABLE subject ADD COLUMN geo_precision TEXT;
  geo_precision TEXT,                 -- 'exact'|'town'|'region'|'unknown'

  -- Uncertain dating is the rule, not the exception. "Sometime in the fifties"
  -- is stored as the range [1950, 1959] with precision 'decade' — neither
  -- forced into a false date nor thrown away.
  date_start    INTEGER,              -- unix, lower bound
  date_end      INTEGER,              -- unix, upper bound; equal to start = exact
  date_precision TEXT,                -- 'day'|'month'|'year'|'decade'|'unknown'

  -- Proposed by the AI (0) vs. confirmed by a human (1). Unconfirmed shows as a
  -- proposal, never as fact in the family tree.
  confirmed     INTEGER NOT NULL DEFAULT 1,

  created_by    TEXT REFERENCES member(id),
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  -- Ordering number granted by the server. The client asks for everything above
  -- its own cursor.
  seq           INTEGER NOT NULL DEFAULT 0,

  -- A merge redirects rather than deletes. When the teller corrects a
  -- misheard name ("Aune" → "Aino") and the target already exists, this row
  -- stays in place pointing at the survivor. Deleting it would break the other
  -- device's references: a phone that is offline may be adding memories to the
  -- subject being merged away right now. Redirecting also makes a merge
  -- reversible.
  merged_into   TEXT REFERENCES subject(id)
);

CREATE INDEX idx_subject_family_kind ON subject(family_id, kind);
CREATE INDEX idx_subject_date        ON subject(family_id, date_start);
CREATE INDEX idx_subject_seq         ON subject(family_id, seq);

-- ---------------------------------------------------------------- memory

CREATE TABLE memory (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  subject_id    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  author_id     TEXT NOT NULL REFERENCES member(id),

  body          TEXT NOT NULL,        -- cleaned, readable text
  -- The original transcript is ALWAYS kept. If the LLM cleans it up wrongly,
  -- the truth is still on file — the speaker may no longer be around to ask.
  raw_transcript TEXT,
  -- The original audio. Grandmother's voice is itself the inheritance, not an
  -- intermediate step.
  audio_r2_key  TEXT,
  audio_seconds INTEGER,

  -- Who told it, which is not who pushed it. `author_id` is the session's own
  -- member and nothing else is accepted — a client must not claim a telling
  -- was made by somebody else — and that is exactly right for who may edit it
  -- and exactly wrong for whose voice it is. One phone round a table files
  -- every teller under its owner until somebody says otherwise, which is what
  -- these two columns are: a person card chosen on the result screen, or a
  -- teller who asked not to be named at all. Both NULL and 0 is the state of
  -- every telling made before 19 Sep 2026, and it still reads as the author.
  --
  -- The flag hides the name that is SHOWN. `author_id` still stands, because
  -- the upsert below decides from it who may take a telling back; what the
  -- app and the export promise is that no name is put beside it.
  --
  -- No REFERENCES, for `invite.person_subject_id`'s reason one step further.
  -- The card and the telling travel in the same push and the subjects go in
  -- first, so the foreign key would hold on every ordinary round — but a push
  -- is capped at MAX_ROWS rows per table, and a first sync of a large archive
  -- is exactly where the card falls outside the cap while the telling does
  -- not. D1 enforces foreign keys on every query and a batch is one
  -- transaction, so that round would fail whole, with a constraint error for
  -- a cause. A teller whose card this database has never seen is a name the
  -- reading phone cannot resolve, and `MemoryStore.byline(for:)` already
  -- answers that with the author. For existing databases:
  --   ALTER TABLE memory ADD COLUMN teller_subject_id TEXT;
  --   ALTER TABLE memory ADD COLUMN teller_hidden INTEGER NOT NULL DEFAULT 0;
  teller_subject_id TEXT,
  teller_hidden INTEGER NOT NULL DEFAULT 0,

  source        TEXT NOT NULL,        -- 'typed' | 'voice'
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  seq           INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_memory_subject ON memory(subject_id, created_at);
CREATE INDEX idx_memory_author  ON memory(author_id, created_at);
CREATE INDEX idx_memory_seq     ON memory(family_id, seq);

-- Subjects mentioned in a memory. This web is what the AI "connects": the same
-- person appears in ten memories under different photos.
CREATE TABLE mention (
  memory_id     TEXT NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  subject_id    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  confidence    REAL,                 -- the LLM's confidence, NULL = human linked
  PRIMARY KEY (memory_id, subject_id)
);

CREATE INDEX idx_mention_subject ON mention(subject_id);

-- ---------------------------------------------------------------- family tree

CREATE TABLE relation (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  from_subject  TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  to_subject    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  -- Directed: 'parent_of' reads from → to. 'spouse_of' and 'sibling_of' are
  -- symmetric, stored once and read in both directions.
  kind          TEXT NOT NULL,        -- 'parent_of'|'spouse_of'|'sibling_of'
  confirmed     INTEGER NOT NULL DEFAULT 0,
  confidence    REAL,
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  seq           INTEGER NOT NULL DEFAULT 0,
  UNIQUE (from_subject, to_subject, kind)
);

CREATE INDEX idx_relation_from ON relation(from_subject);
CREATE INDEX idx_relation_to   ON relation(to_subject);
CREATE INDEX idx_relation_seq  ON relation(family_id, seq);

-- ---------------------------------------------------------------- questions

-- Follow-up questions generated by the AI. These are both the tail of the magic
-- moment and the retention engine: an open question is a reason to come back.
CREATE TABLE prompt_question (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  subject_id    TEXT REFERENCES subject(id) ON DELETE CASCADE,
  -- Who it is aimed at. NULL = anyone in the family can answer.
  target_member TEXT REFERENCES member(id),
  -- Who asked. NULL = generated by extraction. A person's name on a question
  -- is what turns a prompt into a request — "Ville kysyy" carries a pull no
  -- machine question has. For existing databases:
  --   ALTER TABLE prompt_question ADD COLUMN author_id TEXT REFERENCES member(id);
  author_id     TEXT REFERENCES member(id),
  text          TEXT NOT NULL,
  -- How much the question asks of the person answering it, 1–5: a name, a fact,
  -- a description, a story, a reflection. Extraction labels its own questions;
  -- NULL means nobody did, and the client reads the level off the wording
  -- instead. See docs/ARCHITECTURE.md §12. For existing databases:
  --   ALTER TABLE prompt_question ADD COLUMN level INTEGER;
  level         INTEGER,
  status        TEXT NOT NULL DEFAULT 'open',  -- 'open'|'answered'|'dismissed'
  answered_memory_id TEXT REFERENCES memory(id),
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  seq           INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_question_open ON prompt_question(family_id, status);
CREATE INDEX idx_question_seq  ON prompt_question(family_id, seq);


-- ---------------------------------------------------------------- quotas

-- Free tier meters. The photo count, AI minutes and colourisations are
-- limited; writing memories never is — that is the entire value of the product.
-- AI minutes and colourisations are per month. The photo count is derived
-- straight from the subject table: the limit is a total rather than a monthly
-- cap, a deleted photo frees its slot, and a separate counter would inevitably
-- drift out of step with reality.
CREATE TABLE usage_counter (
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  period        TEXT NOT NULL,        -- 'YYYY-MM' UTC
  ai_seconds    INTEGER NOT NULL DEFAULT 0,
  -- Photographs coloured by the telling. A column of its own rather than more
  -- seconds, so a grandchild's colouring never spends a grandmother's telling
  -- minutes. For existing databases, BEFORE the Worker that reads it is
  -- deployed — /usage selects it, and fails on a table without it:
  --   ALTER TABLE usage_counter ADD COLUMN colourisations INTEGER NOT NULL DEFAULT 0;
  colourisations INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (family_id, period)
);

-- ---------------------------------------------------------------- moderation

-- Apple rule 1.2 requires reporting and blocking from an app that contains user
-- content. Cheap now, expensive as a rejection in September.
CREATE TABLE report (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL,
  memory_id     TEXT REFERENCES memory(id) ON DELETE CASCADE,
  reporter_id   TEXT NOT NULL REFERENCES member(id),
  reason        TEXT,
  status        TEXT NOT NULL DEFAULT 'open',
  created_at    INTEGER NOT NULL
);

CREATE TABLE block (
  family_id     TEXT NOT NULL,
  blocker_id    TEXT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
  blocked_id    TEXT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
