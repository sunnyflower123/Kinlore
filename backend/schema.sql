-- Memorize — D1-skeema
--
-- Ydinoivallus: kuva, henkilö, paikka ja tapahtuma ovat kaikki `subject`.
-- Muisto kiinnittyy mihin tahansa subjectiin. Siksi "kirjoita muisto kuvaan" ja
-- "kirjoita millainen isoäiti oli" ovat sama ruutu ja sama reitti — ei kolmea
-- rinnakkaista toteutusta. Sukupuu on person-subjectien väliset kaaret.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------- perhe

CREATE TABLE family (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  -- Kanavatason oikeus: yksi maksaja avaa koko perheen. Ei per-käyttäjä.
  entitlement   TEXT NOT NULL DEFAULT 'free',   -- 'free' | 'archive'
  -- Kuka maksaa juuri nyt. Tilauksen päättyessä palautuu NULLiksi.
  payer_id      TEXT,
  -- Milloin oikeus raukeaa. Kaksi maksajaa: pisin voimassaolo voittaa.
  entitlement_expires_at INTEGER,
  -- Synkronoinnin järjestysluku. Kasvaa jokaisella kirjoituksella. Laitteiden
  -- kelloihin ei voi luottaa: iäkkään puhelimen aikavyöhyke voi olla vuosia
  -- väärässä, ja aikaleimajärjestys tuottaisi hävinneitä kirjoituksia.
  sync_seq      INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE TABLE member (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL,
  -- Laitteen salaisuuden SHA-256. Salaisuus on 32 satunnaista tavua, ei
  -- salasana, joten hidas tiiviste ei toisi mitään: arvattavuutta ei ole.
  -- Tallennetaan silti tiivisteenä, jottei kannan vuoto anna pääsyä.
  secret_hash   TEXT NOT NULL,
  -- Vain maksajalla. RevenueCatin webhookit osuvat tähän.
  rc_app_user_id TEXT,
  role          TEXT NOT NULL DEFAULT 'member',  -- 'owner' | 'member'
  -- Jäsenen oma henkilökortti puussa. Jäsen on subject siinä missä vainajakin.
  person_subject_id TEXT REFERENCES subject(id),
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER
);

-- Kutsulinkit. Oma taulu eikä perheen kenttä, koska linkin pitää voida
-- umpeutua ja olla mitätöitävissä erikseen: linkki on koko turvallisuusraja,
-- ja kuka tahansa sen saanut näkee perheen kaikki muistot.
CREATE TABLE invite (
  code          TEXT PRIMARY KEY,     -- 22 merkkiä base64url, ei luettavaksi
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
  title         TEXT,                 -- "Isoäiti Aino", "Kesämökki Puumalassa"

  -- kind = 'photo'
  r2_key        TEXT,
  blurhash      TEXT,                 -- placeholder latauksen ajaksi

  -- Epävarma ajoitus on sääntö, ei poikkeus. "Joskus 50-luvulla" tallentuu
  -- välinä [1950, 1959] tarkkuudella 'decade' — ei pakoteta valheelliseen
  -- päivämäärään eikä heitetä pois.
  date_start    INTEGER,              -- unix, alaraja
  date_end      INTEGER,              -- unix, yläraja; sama kuin start = tarkka
  date_precision TEXT,                -- 'day'|'month'|'year'|'decade'|'unknown'

  -- AI:n ehdottama (0) vs. ihmisen vahvistama (1). Vahvistamaton näkyy
  -- ehdotuksena, ei koskaan faktana sukupuussa.
  confirmed     INTEGER NOT NULL DEFAULT 1,

  created_by    TEXT REFERENCES member(id),
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  -- Palvelimen myöntämä järjestysluku. Asiakas pyytää kaiken tätä suuremman.
  seq           INTEGER NOT NULL DEFAULT 0,

  -- Sulautus ei poista vaan ohjaa. Kun kertoja korjaa väärin kuullun nimen
  -- ("Aune" → "Aino") ja kohde on jo olemassa, tämä rivi jää paikalleen
  -- osoittamaan säilyvään. Poistaminen rikkoisi toisen laitteen viittaukset:
  -- offline oleva puhelin voi juuri lisätä muistoja sulautettavaan kohteeseen.
  -- Ohjaus tekee sulautuksesta myös peruttavan.
  merged_into   TEXT REFERENCES subject(id)
);

CREATE INDEX idx_subject_family_kind ON subject(family_id, kind);
CREATE INDEX idx_subject_date        ON subject(family_id, date_start);
CREATE INDEX idx_subject_seq         ON subject(family_id, seq);

-- ---------------------------------------------------------------- muisto

CREATE TABLE memory (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  subject_id    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  author_id     TEXT NOT NULL REFERENCES member(id),

  body          TEXT NOT NULL,        -- siivottu, luettava teksti
  -- Alkuperäinen purku säilytetään AINA. Jos LLM siivoaa väärin, totuus on
  -- yhä tallessa — puhuja ei ehkä ole enää kysyttävissä.
  raw_transcript TEXT,
  -- Alkuperäinen ääni. Isoäidin ääni on itsessään perintö, ei välivaihe.
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

-- Muistossa mainitut kohteet. Tämä kudos on se mitä AI "yhdistelee":
-- sama henkilö esiintyy kymmenessä muistossa eri kuvien alla.
CREATE TABLE mention (
  memory_id     TEXT NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
  subject_id    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  confidence    REAL,                 -- LLM:n varmuus, NULL = ihminen linkitti
  PRIMARY KEY (memory_id, subject_id)
);

CREATE INDEX idx_mention_subject ON mention(subject_id);

-- ---------------------------------------------------------------- sukupuu

CREATE TABLE relation (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  from_subject  TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  to_subject    TEXT NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
  -- Suunnattu: 'parent_of' luetaan from → to. 'spouse_of' ja 'sibling_of'
  -- ovat symmetrisiä, tallennetaan kertaalleen ja luetaan molempiin suuntiin.
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

-- ---------------------------------------------------------------- kysymykset

-- AI:n generoimat jatkokysymykset. Nämä ovat sekä taikahetken loppuosa että
-- retention-moottori: avoin kysymys on syy palata sovellukseen.
CREATE TABLE prompt_question (
  id            TEXT PRIMARY KEY,
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  subject_id    TEXT REFERENCES subject(id) ON DELETE CASCADE,
  -- Kenelle suunnattu. NULL = kuka tahansa perheestä voi vastata.
  target_member TEXT REFERENCES member(id),
  text          TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'open',  -- 'open'|'answered'|'dismissed'
  answered_memory_id TEXT REFERENCES memory(id),
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  seq           INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_question_open ON prompt_question(family_id, status);
CREATE INDEX idx_question_seq  ON prompt_question(family_id, seq);

-- ---------------------------------------------------------------- kiintiöt

-- Ilmaiskäytön mittarit. Kuvamäärä ja AI-minuutit rajataan; muistojen
-- kirjoittamista ei koskaan — se on koko tuotteen arvo.
-- Vain AI-minuutit ovat kuukausikohtaisia. Kuvamäärä lasketaan suoraan
-- subject-taulusta: raja on kokonaismäärä eikä kuukausiraja, poistettu kuva
-- vapauttaa paikan, ja erillinen laskuri ajautuisi väistämättä eri tahtiin
-- todellisuuden kanssa.
CREATE TABLE usage_counter (
  family_id     TEXT NOT NULL REFERENCES family(id) ON DELETE CASCADE,
  period        TEXT NOT NULL,        -- 'YYYY-MM' UTC
  ai_seconds    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (family_id, period)
);

-- ---------------------------------------------------------------- moderointi

-- Apple 1.2 vaatii käyttäjäsisältöä sisältävältä sovellukselta raportoinnin ja
-- eston. Halpa nyt, kallis hylkäyksenä syyskuussa.
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
