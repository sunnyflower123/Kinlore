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
| Every member's phone | The whole text archive in one JSON file, in the clear; the media that phone has fetched; **the family key** | — |
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

Where the bytes also are: on every phone that has looked at the photograph or
pressed play (`MediaLoader` fetches on demand, not ahead), and in every export
made since. Nothing re-uploads them — there is no import — so the recovery is a
member's export, kept.

Today two objects sit there and nothing real is at risk. **Before the first
real family** (Phase E, the grandparent's phone, 15–24 Sep 2026) a copy off
this account has to exist, and the shape it should take is known: an R2 API
token, and

```bash
rclone sync r2:memorize-media <another-provider>:kinlore-media-copy
```

on a calendar, monthly. It is not set up, not automated and has not been run,
and it is the largest thing missing from this page.

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

Versions are kept per deploy since 15 Aug 2026; 5 Sep 2026 is `c29f528d`. Code
only — rolling back does not touch D1 or R2.

## The copies, in the order to trust them

| Copy | Holds | Needs the account | Made by |
|------|-------|-------------------|---------|
| Every member's phone | Text in the clear, the key, fetched media | no | the app, continuously |
| An export | Text, page, the media that phone had | no | a member, by hand |
| `backend/backups/*.sql` | D1 only, content sealed | no, once made | `npm run db:export`, by hand |
| D1 Time Travel | D1, the last 7 or 30 days | yes | Cloudflare, continuously |
| Worker versions | code, not data | yes | every deploy |
| — | R2 objects, off the account | — | **not built** |

## What this page still cannot say

- **No copy of R2 off the account.** The command is above; the token, the
  second provider and the calendar are not.
- **No schedule** for the dump. Run it after every deploy and before every
  hand-typed statement; that is the whole procedure today.
- **No rehearsal** of either restore. The Time Travel restore and the dump
  import have not been run against anything.
- **The phone only holds what was viewed.** It is the family's real backup and
  the only one that needs no account, and it fetches media on demand. The
  review's finding #86 — *keep a full copy on this phone* — is the change that
  would make the first row of the table above complete.
