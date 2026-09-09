# Recovery — when something on the server has gone wrong

Read this before typing anything. Two of the commands below make the day worse
when run against the wrong target, and the last time a command here looked like
it had run and had not was `schema.sql` against an existing database
(CLAUDE.md, Commands).

Written 5 Sep 2026 against the founder's-eye review's finding #50: *the shared
archive has no backup and rests on one hobbyist account*. Everything below was
measured that evening, and the measurements are dated so that they can go stale
honestly.

## What is where, and in what form

| Store | Holds | Measured 5 Sep 2026 |
|-------|-------|---------------------|
| D1 `memorize` (id `a39d23ba-…`, region EEUR) | Families, members, subjects, memories, mentions, invites, questions — metadata in the clear, content sealed | 12 tables, 520 kB; 7 families, 127 memories, 21 members, all of them throwaway rows left by the check scripts. **No real family yet.** |
| R2 `memorize-media` (EEUR) | Photographs and audio, sealed. Rule 3 lives here | 2 objects, 4.39 kB — the lever-3 round trip's bytes |
| Workers Logs | Shape, counts, status. Never content (rule 9) | on |
| Every member's phone | The whole text archive in one JSON file, in the clear; the media — since 5 Sep 2026 all of it, fetched over Wi-Fi after every sync (`FullCopy`, ARCHITECTURE §5), before that only what was viewed; **the family key** | — |
| The export (*Asetukset → Vie arkisto*) | A readable page, the JSON, and every media file the phone had | made by hand, by a member |

What a database dump yields is written down once, in
[ARCHITECTURE.md §18](ARCHITECTURE.md#18-places-on-a-map--the-three-columns-and-what-they-cannot-promise)
under *a decided leak*: sealed are memory bodies, raw transcripts, subject
titles, question text and the R2 bytes; in the clear are the family's name, the
members' display names, dates, kinds, relationships, the mention graph and place
coordinates. **The family key is on no server.** A dump without a phone is
metadata beside ciphertext.

## Four things that go wrong

### 1. A statement ran against production that should not have

`npm run db:remote` is `schema.sql` against production. On a database that
already exists it stops on the first `CREATE TABLE` and changes nothing, so the
realistic damage here is an `ALTER`, `UPDATE` or `DELETE` typed by hand.

D1 keeps its own history — **Time Travel** — and needs nothing from us until
the day it is needed:

```bash
cd backend && npx wrangler d1 time-travel info memorize
```

answers with the current bookmark. Measured 5 Sep 2026:
`0000000c-00000000-000050dd-3ea2ad71f8f0ed7faf6ff58663ceda83`. To go back:

```bash
cd backend && npx wrangler d1 time-travel restore memorize --timestamp=2026-09-05T18:00:00Z
```

or `--bookmark=<id>`. **Take a dump first** (`npm run db:export`, below): the
restore replaces the present state, and the mistaken state is worth keeping
too. How far back Time Travel reaches depends on the plan — 30 days on Workers
Paid, 7 on Free, per
[Cloudflare's Time Travel reference](https://developers.cloudflare.com/d1/reference/time-travel/)
— and this account is on the free tier unless somebody has upgraded it
(SETUP.md, cost estimate). Check the dashboard before relying on the longer
number. **The restore itself has not been rehearsed**; it rewrites production
and there was no reason to.

### 2. An object, or the bucket, is deleted

**R2 has no versioning.** `PutBucketVersioning` is in the *unimplemented*
table of Cloudflare's
[S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/) page,
measured 5 Sep 2026. A deleted object is gone from the server, and the bucket
is what rule 3 stands on.

Where the bytes also are: on every member's phone that has met Wi-Fi since
the object arrived — `FullCopy` fetches everything after every sync, and the
family screen's *"Kopio tällä puhelimella"* row says whether it has finished —
and in every export made since. Nothing re-uploads them — there is no import —
so the recovery is a member's phone or export, kept.

Today two objects sit there. A copy off this account was the first thing this
page asked for on 5 Sep 2026, and the same evening's `FullCopy` changed the
arithmetic: every phone that meets Wi-Fi holds the bytes, the teller's phone
held the original before it was ever uploaded, the media directory is in
Documents and travels in the phone's own backup, and the export writes it
opened, readable with no app and no key. A copy of R2 is sealed bytes — without
a phone's key it opens nothing — so it earns its keep in exactly one case: the
account is gone, every phone's copy is gone, and a key survives somewhere.
That is a year-three question (who runs the Worker after the hackathon), not a
September one, and **it was decided against for now on 6 Sep 2026**. The
shape, for the day it is decided the other way: an R2 API token, and

```bash
rclone sync r2:memorize-media <another-provider>:kinlore-media-copy
```

on a calendar, monthly.

### 3. The account, the login or the card is gone

Worker, database and bucket go together. What survives is exactly the table
above with the account rows crossed out: every member's phone, the exports,
and the dumps on the developer's machine.

```bash
cd backend && npm run db:export       # → backend/backups/memorize-<date>.sql
```

pulls the production database as SQL. It ran on 5 Sep 2026: 347 kB, 903
inserts. `backend/backups/` is ignored by git on purpose — names are plaintext
in it — and it is by hand; there is no schedule, and a cron Worker that
exported on its own would need an account API token stored as a secret.

Rebuilding on a fresh account: `npx wrangler d1 create memorize`, the new id
into `wrangler.jsonc`, `schema.sql`, then the dump with
`npx wrangler d1 execute memorize --remote --file=backups/<file>.sql`;
`npx wrangler r2 bucket create memorize-media`; the three secrets in
[SETUP.md](SETUP.md); `npx wrangler deploy`. The member rows travel in the
dump, so the same phones authenticate again with the same secret. The Worker's
address changes with the account — it is a constant in `AppServices` — so a new
build follows. And the media is whatever the phones hold: **with no off-account
copy, the voices are the phones'.**

### 4. A deploy broke the Worker

```bash
cd backend && npx wrangler deployments list
cd backend && npx wrangler rollback
```

Versions are kept per deploy since 15 Aug 2026; 5 Sep 2026 is `c29f528d`,
6 Sep 2026 is `f7643e4d` (the move rule) and `6812b0d4` (the rename). Code
only — rolling back does not touch D1 or R2.

## The copies, in the order to trust them

| Copy | Holds | Needs the account | Made by |
|------|-------|-------------------|---------|
| Every member's phone | Text in the clear, the key, and all the media once it has met Wi-Fi | no | the app, after every sync |
| An export | Text, page, the media that phone had | no | a member, by hand |
| `backend/backups/*.sql` | D1 only, content sealed | no, once made | `npm run db:export`, by hand |
| D1 Time Travel | D1, the last 7 or 30 days | yes | Cloudflare, continuously |
| Worker versions | code, not data | yes | every deploy |
| — | R2 objects, off the account | — | **not built** — decided against for now, see 2 |

## What this page still cannot say

- **No copy of R2 off the account**, by decision (6 Sep 2026, under 2). The
  phones are the copies; the day that changes is the day somebody other than
  a hobbyist runs the Worker.
- **No schedule** for the dump. Run it after every deploy and before every
  hand-typed statement; that is the whole procedure today.
- **No rehearsal** of either restore. The Time Travel restore and the dump
  import have not been run against anything.
- **The phone's copy needs Wi-Fi, and it is heavier than this page said.**
  Since 5 Sep 2026 every member's phone fetches the whole archive after every
  sync (finding #86, built), but only over a cheap network: a phone that lives
  on cellular holds what it viewed and nothing more, and the family screen's
  row says so. A family of 3 000 photographs and 2 000 tellings is 2–3.8 GB
  per phone at the sizes measured on 6 Sep 2026, not 1.3, and the copy writes
  the store's JSON every tenth file and once more at the end of any round that
  recorded anything (ARCHITECTURE §5). Corrected 9 Sep 2026: this said "once
  per file", which was the defect §5 records as fixed on 6 Sep, not the
  behaviour. Measured on a simulator
  against a local Worker; an old phone has not been.
