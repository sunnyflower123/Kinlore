-- Memorize — D1 schema
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
  role          TEXT NOT NULL DEFAULT 'member',  -- 'owner' | 'member'
  -- The member's own person card in the tree. A member is a subject just as
  -- much as a dead relative is.
  person_subject_id TEXT REFERENCES subject(id),
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER
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
  used_count    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE INDEX idx_invite_family ON invite(family_id);

CREATE INDEX idx_member_family ON member(family_id);
CREATE INDEX idx_member_rc     ON member(rc_app_user_id);

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
  blurhash      TEXT,                 -- placeholder while the photo loads

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
  status        TEXT NOT NULL DEFAULT 'open',  -- 'open'|'answered'|'dismissed'
  answered_memory_id TEXT REFERENCES memory(id),
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  seq           INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_question_open ON prompt_question(family_id, status);
CREATE INDEX idx_question_seq  ON prompt_question(family_id, seq);

-- ---------------------------------------------------------------- quotas

-- Free tier meters. The photo count and AI minutes are limited; writing
-- memories never is — that is the entire value of the product.
-- Only AI minutes are per month. The photo count is derived straight from the
-- subject table: the limit is a total rather than a monthly cap, a deleted
-- photo frees its slot, and a separate counter would inevitably drift out of
-- step with reality.
CREATE TABLE usage_counter (
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  period        TEXT NOT NULL,        -- 'YYYY-MM' UTC
  ai_seconds    INTEGER NOT NULL DEFAULT 0,
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
