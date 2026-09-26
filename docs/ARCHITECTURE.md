# Architecture

This document explains how Kinlore works and why, one mechanism to a section.
It began in August as the design of what had not been built yet, and most of
that has been built since; what was finished before it began is described in
[PLAN.md](PLAN.md) §7.

**If you read one section, read [§1](#1-where-things-stand)** — an inventory of
what is built and what is not, ending in a warning about why that inventory has
been wrong before. Sections 15 to 20 are about things that were wrong: what
they were, how they hid, and what found them.

## Contents

**What it is**
[1. Where things stand](#1-where-things-stand) ·
[2. Five decisions that determine the rest](#2-five-decisions-that-determine-the-rest) ·
[9. Build order](#9-build-order)

**The machinery underneath**
[3. Sync](#3-sync) ·
[4. Identity and family](#4-identity-and-family) ·
[5. Media](#5-media) ·
[6. Money](#6-money) ·
[7. Quotas and moderation](#7-quotas-and-moderation)

**What it is like to use**
[8. The screens](#8-the-screens) ·
[10. The interview loop](#10-the-interview-loop) ·
[11. Asked questions](#11-asked-questions) ·
[12. The question ladder](#12-the-question-ladder) ·
[14. Settings — taking the archive out, and leaving](#14-settings--taking-the-archive-out-and-leaving) ·
[21. The words](#21-the-words) ·
[22. The one blue button](#22-the-one-blue-button) ·
[23. The card, and why the front door was a blank page](#23-the-card-and-why-the-front-door-was-a-blank-page) ·
[24. Colours by the telling](#24-colours-by-the-telling) ·
[25. A face on the card](#25-a-face-on-the-card)

**Things that were wrong, and what it took to find them**
[15. Contrast — the rule that was never measured](#15-contrast--the-rule-that-was-never-measured) ·
[16. The memory that was interrupted](#16-the-memory-that-was-interrupted) ·
[17. The name that was heard wrong](#17-the-name-that-was-heard-wrong) ·
[18. Places on a map — what they cannot promise](#18-places-on-a-map--the-three-columns-and-what-they-cannot-promise) ·
[19. The telling that was not meant](#19-the-telling-that-was-not-meant) ·
[20. Small promises the app was not keeping](#20-small-promises-the-app-was-not-keeping) ·
[13. The guessing round — built, then cut](#13-the-guessing-round--built-then-cut)

---

## 1. Where things stand

An honest inventory, not a wish list:

| Part | State |
|------|-------|
| Dictation, typing, extraction, name correction | **Done and tested** |
| Photo import, gallery, person cards | **Done** |
| `subject`, `memory`, `mention`, `prompt_question` | In use |
| Identity, family, invite links | **Done and tested** — the door in §4, and the session after it, including the member who has left |
| Sync (`/sync` pull and push) | **Done and tested** |
| Media to R2 (`/media`) | **Done and checked**, see §5 — the round trip and the isolation, against wrangler's local bucket |
| Quotas (`/usage`, limits on the server) | **Done and checked**, see §7 — the counting and rule 2; not the transcription path itself |
| Deferred transcription — the interrupted memory finishes itself | **Done and tested**, see §16 |
| RevenueCat, shared family entitlement | **Done and driven end to end in production, 12 Sep 2026** — the binding rule, the webhook's revocation rules and the REST verification run against the shipping schema with RevenueCat replaced (§6); and on a Test Store key a real purchase reached `family.entitlement`, and a signed `INITIAL_PURCHASE` reached the deployed Worker. The row below is what is left |
| Audio playback, open questions, relationships | **Done and tested** |
| Paywall | **Built, reached and drawn** — the key configures the SDK, the sheet opens and the purchase completes, and since 12 Sep 2026 the design in RevenueCat's dashboard is the app's own words and palette (§6). What it showed when this row was written, the same evening, is the pre-decision pair — `monthly` and `yearly` at 9,99 and 79,99 US$ — and PLAN §10 has since decided on a year at 50 and the archive for ever at 80, with no monthly plan. Redrawing it is dashboard work, not code, and VIDEO.md's fifth scene films whichever is there |
| Interview loop (questions asked aloud) | **Done and tested** — runs hands-free round after round |
| Asked questions (a person asks, the name travels) | **Done** |
| Places, reachable rather than only stored | **Done and tested**, see §8 |
| Coordinates for places — drawn on the place's own card | **Done**, see §18 |
| Correcting a misheard name afterwards | **Done and tested**, see §17 |
| Soft deletion — a rejection that is final | **Done and tested**, see §3 |
| A telling taken back — mid-recording, or after it is saved | **Done and tested**, see §19 |
| Search over what was told, not only over titles | **Done and tested**, see §8 |
| A date given by hand, at the precision somebody actually has | **Done and tested**, see §8 |
| Whether a telling has reached the family, on screen | **Done and tested**, see §3 |
| What the family told while this phone was away, on screen | **Done and tested** — the same promise's mirror, see §3 |
| Rate limiting on the two unauthenticated writes | **Done and tested**, see §4 |
| Accessibility sweep over every screen | **Done** — 97 sweep tests, each auditing one screen at the default text size and again at the largest, out of 276 UI tests, and they audit the screen they are named after. `scripts/verify.sh` counts both and fails if this sentence drifts from the source again |
| A face on a person's card, chosen from a photograph | **Built and tested 21 Sep 2026**, see §25 — a reference and two fractions travel, never a crop, and every phone cuts the disc from its own copy of the picture; the four columns reach production with the deploy §25 records |
| A card on the Tell tab instead of a blank button | **Done and tested**, see §23 — the screen that matters most had nothing to ask and fell back to "Kerro mitä muistat" |
| Photographing a paper photograph into the archive | **Done and tested**, see §8 — the shoebox had no way in until 29 Aug 2026; the only import read the phone's own library |
| A single-device archive opened to a family, without losing it | **Done and tested**, see §14 and docs/UX.md §11.1 — one-way, and the rows already on the phone travel with it |
| Backup and recovery | **Written down and measured**, see docs/RECOVERY.md — Time Travel answers, the dump runs, R2 has no versioning, and nothing yet copies the media off the account |
| The family's media on every phone, not only in R2 | **Done and checked**, see §5 — `FullCopy` after every sync, on Wi-Fi, voices first, with the number on the family screen |
| Colouring a photograph by what was told about it | **Done and tested, deployed 13 Sep 2026**, see §24 — kept only after somebody answers yes, and the model was chosen on one photograph |
| Repo in English | **Done** |
| Moderation (`report`, `block`) | Formally out of v1, see §14 |
| Demo video | Remaining |

The critical path is open: family and sync work, so everything else stands on
them. What is left is either cuttable or somebody's to record — see PLAN.md §8
for the one measurement that has not been taken.

**Verified rules.** Confirmation is one-way, merges are sticky, only the author
edits their own, and another family can neither see nor write. The outbox
survives the app being closed, and a locally changed row is not lost underneath
the remote version. A rejection travels and cannot be revived by a device that
missed it. An audio-only memory is stored rather than dropped, and an empty body
never overwrites a real one.

**And a warning that is worth more than the list above.** Nearly every item here
was written as done long before it was true, and each one looked done from the
outside: the transcription that waited for a text nothing was bringing, the
deletion the client never sent, the rate limit that existed only in this
document, the audit that measured the wrong screen and passed. They were found
by reading a promise and then checking the code that was supposed to keep it —
not by using the app, which behaved perfectly in every one of those cases. That
is the failure mode this project has, and the reason to distrust this table is
that it has been wrong in exactly this way before.

## 2. Five decisions that determine the rest

### 2.1 Local first, not server first

**Decision: every write goes to local storage first and syncs in the
background.**

The alternative would have been a direct server call on every write. That is
simpler, but wrong for this app: an 80-year-old may be at a summer cottage with
no signal, and the memory she just told is irreplaceable. The speaker may no
longer be around to ask.

The price is sync machinery and conflict handling. That is an acceptable price
for **nothing that was told ever being lost to the network**.

### 2.2 A per-family counter, not timestamps

Sync ordering comes from the `family.sync_seq` counter, which the server
increments on every write. Not from device clocks.

The reason: device clocks disagree, and on an elderly user's phone the time zone
can be wrong for years. Timestamp-based ordering would produce random lost
writes that are impossible to trace. A family archive is hundreds of rows, so
one counter is plenty.

### 2.3 Memories are appended, not edited

`memory` is effectively append-only. Only the author can edit or delete their
own, and the automatic edits are the text update made by name correction and
two that move a telling rather than change its words: `MemoryStore.split(mention:in:)`,
and the author re-homing their own telling onto another card, which the server
permits explicitly (added 5 Sep 2026). Both rewrite `subject_id` and neither
touches `body`. Corrected 9 Sep 2026, where this said "the sole automatic edit".

This removes conflicts almost entirely: two people cannot edit the same memory.
It is also the right product rule — nobody gets to tidy up what grandmother said.

### 2.4 Confirmation is one-way

`confirmed = 1` never goes back to zero during sync.

Without this rule, an old device coming online after a week could "restore" a
confirmed person back into a proposal. The same applies to `relation.confirmed`.

### 2.5 A merge does not delete, it redirects

**This is a correction to code that already existed.** `MemoryStore.rename` used
to delete the merged subject. On a single device that works, but it breaks under
sync: if device A merges *Aune → Aino* while device B is offline adding memories
to Aune, B's memories end up pointing at a subject that is gone.

The solution is a tombstone with a forwarding address:

```sql
ALTER TABLE subject ADD COLUMN merged_into TEXT REFERENCES subject(id);
```

The merged row stays in place with a `merged_into` reference, and all references
follow the chain. Nothing points at nothing, and the merge can even be undone.

**On the merging phone only, until 21 Sep 2026.** The forwarding address
travelled and the re-pointing did not, wherever the telling was somebody else's.
The server writes a telling only for its author — rule 3's half of the memory
upsert, which `memory-rules-check.mjs` holds on purpose — and a question's
subject only once, so the merging phone's push of another member's telling was
refused, and counted as accepted. Measured over the shipping `sync.ts` in
SQLite. On every other phone that telling stayed under the tombstone, which no
list shows: on no card, in no count, and left out of the export's readable page.
Every phone now draws the merge's conclusion itself, after loading its file and
after every pull (`MergeChain`, held by `merge-chain-check.swift` and, through
the app, by `SilentFailureTests`), and none of it is queued.

## 3. Sync

### Routes

```
GET  /sync?since=<seq>     → changed rows + a new cursor
POST /sync                 → local changes, returns the granted seq
```

Both require a member identity (§4). The server returns only rows from the
caller's own family — the family is the isolation boundary, and it is checked on
every query rather than only at join time.

### Extra columns on synced rows

Every synced table gets:

```sql
seq         INTEGER NOT NULL   -- granted by the server, per family
deleted_at  INTEGER            -- soft delete, so deletion propagates
```

**Except one, and it is the one that matters.** `mention` has neither column,
and no `family_id` either — `schema.sql` declares exactly `memory_id`,
`subject_id`, `confidence` and a primary key on the first two. That is true of
the four tables the DTOs name and false of the fifth, which is reached through
the memory it hangs off rather than pulled in its own right.

What followed from it until 11 Sep 2026: **a mention could not be un-said
across sync.** The only mention write was `INSERT OR IGNORE INTO mention` in
`sync.ts`, so a merge that re-pointed a name on one phone left the old edge
standing on every other phone for ever. Corrected 9 Sep 2026; the sentence
above had said "every". **A mention is now stored as the set the client
sent.** `sync.ts` deletes the edges a push omits before re-inserting the ones
it names, scoped by an `EXISTS` to the pusher's own family, and the Swift half
queues every memory whose `mentionedSubjectIDs` it remapped — so `rename` and
`split` both travel, for the pusher's own tellings. Another member's is refused
whole, mentions and all (§2.5). `memory-rules-check.mjs` asserts it.

Soft deletion is mandatory: a hard delete never reaches the other device, which
would go on showing the deleted row forever.

**The client did not do it.** The column was in the schema, the server stored it
and made it sticky, and the pull carried it — and every row the app sent set
`deleted_at` to nil, while every row it received had the field ignored. So
deletion worked in neither direction, and the app's one deletion is the one that
matters most: **rejecting a person the extraction proposed.**

What happened was that the subject was taken off the device, stayed on the
server, and came back on the next pull as an unconfirmed proposal — with
*"Ehdotus — vahvista henkilö"* on it, and no way to reject it a second time,
because rejecting is only offered in the seconds after telling. A person who
says no once should not have to say it again, least of all to somebody they
already said no to. Removing a relationship had the same hole.

Both are tombstones now. The row stays with `deletedAt` set and travels like any
other change; every list and lookup skips it, and `findOrCreateSubject` will not
hand a buried subject back when the same name is heard again — hearing it again
earns a fresh proposal, which can be rejected again.

Verified against SQLite on the schema: the rejection stores, a stale device
pushing the pre-rejection row back cannot revive it, and the pull carries the
tombstone rather than hiding it, which is what makes the deletion travel at all.
The other end — that a kept row is not a shown row — is a case in the demo
archive and a test over it.

### The client's outbox

Local changes are recorded in an outbox: a set of changed row ids per table, and
the rows themselves are read from the store when the payload is built. Ids
rather than queued operations, because every operation here is an upsert of a
whole row — a row changed twice before a push should travel once, in its final
state.

**The queue is emptied on the reply, not on the outcome, and that is worth
knowing before trusting it.** Written down 9 Sep 2026. `clearPending` subtracts
the ids in the payload as it was built, unconditionally — a write that landed
during the request stays queued, which is the case it was written for, but a row
the server *declined* is subtracted too. And the reply cannot tell them apart:
`accepted` counts the statements the Worker built, not the rows D1 changed, so a
row skipped by a guard inside an upsert is reported the same as one that was
stored. The client therefore cannot distinguish a stored row from a refused one
even in principle, and a silently dropped row is never retried.

The guards that can skip a row are few and each is deliberate — an empty body,
a memory with neither text nor an uploaded recording, another member's telling —
so this is a narrow hole rather than a general one. It is a hole all the same,
and §3 used to describe it as if it applied only to the untranscribed-memory
case.

**The queue is drained when the app is opened, when it comes back to the
foreground — and, since 23 Aug 2026, the moment a write lands in it**, not on
a timer and not with backoff. An earlier version of this document promised
backoff; it never existed, and it should not. iOS suspends a backgrounded app,
so a retry timer is a thing that mostly does not fire, and the one moment
worth retrying at — the phone being in someone's hand again — is a lifecycle
event the system already delivers. A failed sync leaves everything queued and
says nothing to the user, because a network error is not her problem.

The write-lands trigger closes the gap the lifecycle pair left open: the
ordinary flow — open the app, tell, put the phone down — shipped the telling
on the NEXT opening, while Muistot promised it would leave by itself. The
same argument had already been applied twice, to the joiner's mode flip and
to a deferred transcription completing, and the ordinary telling was the
argument left unwired. It is event-driven (the app watches the outbox grow),
so the no-timer decision above stands untouched; the cottage phone kept
foregrounded with no signal still waits for a lifecycle moment, which that
decision knowingly accepts.

**Since 6 Sep 2026 the network coming back is a trigger too**, the same
argument a fourth time. A joiner standing in a kitchen whose Wi-Fi dropped
under the first pull had a phone that never left her hand, the family's
memories one round away, and Muistot showing the empty archive's invitation
to photograph an album (founder's-eye review, finding #63) — until she put the
phone down and picked it up again. `SyncEngine` watches the path with an
`NWPathMonitor` and starts a round when it becomes satisfied, **only while the
engine is in `waitingForNetwork`**: an idle phone's network flapping costs
nothing, and a refused device (§4) is not the network's to fix. It is
event-driven like the outbox trigger, so the no-timer decision stands; the
cottage phone in the paragraph above still waits for its signal, but no
longer for a lifecycle moment after it. What Muistot shows in the meantime is
the third state in docs/UX.md §4.3.

The one row the outbox deliberately holds back is a memory whose audio has not
reached R2 yet: the server would refuse it, and a refused row is cleared from
the outbox exactly as a stored one is. See §16.

Operations are **idempotent**: everything is an upsert keyed by a client
generated UUID. The same operation twice breaks nothing, which makes retrying
safe without coordination.

### The cursor, which only pulls may move

The pull cursor is the family's delivery guarantee: everything above it is
what the server still owes this device, so a cursor that runs ahead is a
telling that never arrives — silently, with every push and pull answering 200.
On 23 Aug 2026 three defects were found living in that one number, none of
them reachable by the checks that existed, all of them the ordinary operation
of a two-device family rather than a race:

1. **The client advanced its cursor to the push reply's seq.** That number is
   the family-global counter, so anything the others committed between this
   device's last pull and its own push fell below the cursor and was never
   fetched — grandmother tells something, grandchild opens the app with any
   change of his own queued, and her telling is gone from his phone forever.
2. **The server reserved seq with an UPDATE and a separate SELECT.** Two
   pushes arriving together could read the counter after both increments and
   share one number, giving each device the same blind spot against the other.
   The reservation is one atomic statement now (`RETURNING`).
3. **A reply's cursor was the maximum seq across four separately-capped
   tables.** When one table filled its 500-row cap while another returned
   higher numbers, the capped table's tail was skipped permanently. Measured
   by replaying the pull queries over SQLite: a joiner to a 700-telling
   archive lost 200 memories and the loop ended cleanly. The reply now
   advances only to what it is *complete* up to — held one below a capped
   table's last number, because a push stamps up to 500 rows with one seq and
   the cap can cut through the middle of such a group; the re-fetched group
   costs bandwidth, which idempotent upserts turn into nothing.

The rule that survives all three: **the cursor moves only through pull
replies.** A push tells the server things; only a pull tells this device what
it has seen. The pull that follows a push therefore returns the device's own
rows once more, and `applyRemote` re-applies them — which surfaced a fourth
defect waiting in the same room: replacing a row wholesale dropped the fields
only this device knows, `imageFilename` and `audioFilename`, orphaning a
quota-refused photograph the moment any other device touched its subject.
Remote rows now keep the local file references, which the DTOs never carried
in the first place.

A fifth was waiting for the first new relationship kind, and was closed on
21 Sep 2026 before that kind exists. `RelationKind` is a `String` enum, so a
pulled row of a kind the build does not know is dropped at the wire
(`Relation.init?(dto:)` answers nil) — correctly, since the build cannot show
it — and the cursor then moves past it like any other row. The row never
comes again unless it changes on the server, and the phone that later updates
to a build that knows the kind holds a relationship the family confirmed and
never shows it. So the store records what it can read — the relationship
kinds and the subject kinds, `MemoryStore.kindsKnown`, which read `4/4` the
day `friend_of` arrived — in UserDefaults (`sync.kindsKnown`) at every
launch, and a launch that finds a different signature — or none, which is
what every build before this check recorded — forgets the cursor once and
pulls the family again from the start. Subject kinds are in the signature
because `Subject.init?(dto:)` drops an unknown one the same way, and it was
widened while no phone had recorded a value: widened later, it costs every
phone one more pull. Safe for the reason the pull after a push is safe: `applyRemote` skips
the outbox and upserts by id. The same enum was the other half of rule 10's
blind spot: one such row in the *file* failed the whole archive and sent it
down the moved-aside path, so `Snapshot` now reads `relations` row by row
and leaves out what it cannot read, counted. `-store unknownKind`,
`-store synced` and `-sync.kindsKnown` drive both in `SilentFailureTests`.

`scripts/sync-cursor-check.mjs` drives the interleavings that showed each
defect against a running Worker, and it is load-bearing: putting the maximum
back as the cursor turns two of its checks red, with 102 of 600 subjects
lost. What it cannot pin is the Swift half of the rule — no Node script can
see whether `SyncEngine` grows a new `advance` call — and the D1 parameter
limit behind the mention batching (§3's pull inlines mentions in batches of
100, D1's documented maximum) does not exist in local SQLite, so the check
proves the batches are assembled correctly rather than that D1 accepts them.

### Whether it got through

A sync failure is a waiting state and not an error: the memories are safe on the
device, the queue drains by itself, and a network error is not an 80-year-old's
problem. That decision stands and nothing here shows an error.

But it had been read as *say nothing at all*, and the two are not the same. The
engine has carried `state` and `lastSyncedAt` from the day it was written, it was
never put in the environment, and no view ever asked — so a memory told at a
cottage with no signal looked exactly like one the whole family had already read.
That difference is the app's entire promise, and it was the one thing on screen
with no way to tell.

Muistot now carries a line while, and only while, something is waiting: *"Yksi
muisto on vielä vain tässä puhelimessa. Se lähtee perheelle itsestään kun verkko
palaa."* It asks for nothing — the queue drains on its own, so instructing
somebody to fix the network would be inventing a job for them — and it disappears
when the last telling is through, because this is a waiting state and not a
permanent piece of furniture. Nothing is shown at all without a family and a
backend: a single-device archive has nowhere to send anything.

The count is of **memories**, from the outbox. Nobody has ever wondered whether a
relationship row reached their family; the question being answered is "did what I
told get through". The family view says the same thing where somebody goes to
check rather than to be told — with a time on it, and with *"kaikki lähetetty"*
when there is nothing waiting, because that is an answer rather than the absence
of one.

**And since 17 Aug 2026, the other direction.** *"Uutta perheeltä"* at the top
of Muistot lists the tellings other members made that this phone has not seen —
author and subject, leading to the subject's card — and when such tellings are
waiting, they are what the app opens on. A visit marks everything seen: the
section is a waiting state exactly as the note above is, never furniture, and
there is no badge and no count anywhere else. Seen-ness is a device-local list
of telling ids (`NewFromFamily`), like the ladder's comfort (§12) and for the
same reason — what a family member has or has not read is not the family's
data. The first visit defines the baseline rather than dumping a joiner's whole
archive into the section; the arrival state (docs/UX.md §4.3) frames that case.
The cut guessing round left the reading loop unanswered (PLAN §4.1, §13); this
is the smaller instrument that answers it, and the map staying out of v1
(PLAN §10) is the removal that paid for it.

Two defects were found in that mechanism on 23 Aug 2026, both in the
appearance plumbing rather than in `NewFromFamily` itself. Opening ONE of
three new tellings erased the other two: the pop-back from the card re-ran
the capture after everything was already marked seen, so the section
supported exactly one read per visit — and with it gone, the derived launch
tab lost its signal too, so the unread tellings left no trace anywhere. The
tab now owns its navigation path and tells a pop-back (path was non-empty
when the root was covered) from an arrival (it was not); the section stays
through the former and still clears on the latter, and both halves are
pinned in `SyncVisibilityTests`. And the joiner's baseline was written
against an empty store: the arrival visit marked nothing as everything, and
the first pull then landed the whole family archive on the wrong side of
that baseline — the exact dump the first-visit rule exists to prevent, one
visit late. The baseline now waits until the cursor has moved: until the
first pull has landed, being on the tab does not count as having seen
anything.

### Conflict rules

| Situation | Resolution |
|-----------|------------|
| Two memories on the same subject | No conflict, both are kept |
| The same memory edited on two devices | Impossible: only the author edits |
| A subject renamed on two devices | The push that arrives second wins — see below |
| One confirms, the other does not | Confirmation always wins (§2.4) |
| One merges, the other adds | The merge redirects, nothing is lost (§2.5) |
| One deletes a memory, the other reads it | Only the author can delete |
| Two phones choose a different face for the same person | The newest choice wins, whole — and a removal is a choice, a phone that never saw the face is not (§25) |

Everything else is resolved by the push that arrives second. There are
deliberately few rules — every extra rule is a place where data can silently go
wrong.

**Both of those rows used to say "the higher `seq` wins", and that was a
tautology dressed as a rule.** Corrected 9 Sep 2026. `seq` is granted at
*arrival* — one number per request, `UPDATE family SET sync_seq = sync_seq + 1`
— so "the higher seq" and "arrived later" are the same sentence. No comparison
of any kind happens in the upsert: `title = excluded.title` is unconditional in
`sync.ts`, and it is the one subject column that is not `COALESCE`-protected.

**What the old wording hid.** A device that read a title, went offline, and
pushes afterwards arrives *later* and therefore wins — reverting somebody
else's rename. And because the coordinate rule keys off the title changing, the
revert takes the resolved point with it: the `CASE WHEN excluded.title IS NOT
subject.title` clause sees a change and nulls `lat`/`lon`. The ordinary way in
is not even an edit — confirming a person re-pushes that subject with whatever
title the confirming device is holding.

Nothing catches this. `subject-rules-check.mjs` covers the coordinates, the
dates, one-way confirmation, merge stickiness and rejection revival, and has no
case for a stale title. Recorded rather than fixed: last-write-wins is the right
default for a four-to-eight person family, and the honest fix is a check that
would have to decide what "stale" means without a clock (§2.2 says why there is
no clock). It is written down here so the next person meets it as a known edge
rather than as a mystery.

### The second push, checked

The table above says "impossible" and "only the author", and until now that was
a reading of the SQL rather than a measurement of it. Most of what this repo
promises about a telling lives in one `ON CONFLICT DO UPDATE` in `sync.ts`, and
`scripts/memory-rules-check.mjs` pushes the same memory twice to find out.

Rule 3 first: the transcript and the audio key are `COALESCE`d, so a phone that
no longer holds them cannot strip them by pushing the row again — and the
author's *other* phone is exactly such a device, since the Keychain identity
syncs and it pushes as the same author. Then §16: an empty body never overwrites
a real one, and a recording with no text is accepted rather than dropped.
Then the two about who is speaking: the author is taken from the session and
never from the payload, and a member of the same family cannot rewrite what
somebody else said. Last, that a deletion survives a stale push.

Twenty-one assertions, and none of them is visible when it breaks. A memory whose
raw transcript has quietly gone looks like a memory.

**Shown to be load-bearing**, in a throwaway worktree with its own Worker and
database. Dropping the `COALESCE` turned exactly one case red — the transcript
gone, the audio key still there, which is what the failure would actually look
like. Removing the author test turned exactly one other case red, and left
`author_id` untouched: the sentence had become somebody else's while the name on
it stayed grandmother's. That is the version of the bug worth having a test for.

A first attempt at that second mutation deleted the `?` along with the test and
broke the bind count, so every case failed at once — which measures nothing.
When a mutation reddens everything, suspect the mutation.

Adding it also showed that the suite had grown into its own rate limit.
Creating a family is five a minute per address, and the seven checks that need
one create eleven between them, so whichever ran last failed with `429` — a
message that reads like a broken Worker and is not one. Each check now knocks
from an address of its own via `CF-Connecting-IP`, and it is **local only** —
though not for the reason this sentence used to give. It said Cloudflare sets
the header from the connection and ignores what the client sends. It does not:
the edge refuses a request carrying a client-set `CF-Connecting-IP` outright,
with `403 error code: 1000`, before the Worker is reached. Measured on the
invite check, 29 Aug 2026; `memory-rules-check.mjs` carries the same
correction beside the code that acts on it. Seven scripts, twice through with
no pause: green both times.

### The second push of a subject, and what it cost

The companion check, `scripts/subject-rules-check.mjs`, was written to confirm
the same statement one table over. It found a defect instead.

A phone pushes its **whole local row** — `Subject.dto` fills every field from
local state — so a device that has never seen a date sends three nulls with it.
The coordinates beside them were carefully protected against exactly that; the
date was assigned straight over the top. Measured against a running Worker: a
place kept its point and lost *joskus viisikymmentäluvulla* the moment anybody
on an older copy renamed it. Rule 5 is that uncertainty is stored rather than
rounded, and it does not survive being stored and then quietly overwritten.

The fix gives the three date columns the shape the point already had, with
`date_precision` as the signal that the pushing device has an opinion at all.
That leaves one hole, and it is the interesting half: if a missing date never
overwrites, a date somebody deliberately *cleared* comes back on the next sync
from an old copy, for ever. So clearing now sends `unknown` rather than nothing
— `DatePrecision.unknown` already existed and `displayText` already read it as
*"Ajankohta ei tiedossa"*, so what changed is that the sheet stores the answer
instead of an absence. **En tiedä is an answer**, which is the same principle the
question ladder rests on.

Nine assertions, and the neighbours in that statement are checked beside it:
confirmation is one-way, a merge is sticky, a rejection cannot be revived.

**Shown to be load-bearing** without a mutation, because the bug was real: run
against `origin/main` before the fix, on a Worker and database of its own, the
two date cases went red and the other seven stayed green.

### Why JSON and not SQLite

Local storage stays a JSON file even after sync.

A family archive is hundreds of rows, not hundreds of thousands. The whole file
fits in memory and the write is atomic. SQLite would bring indexes and partial
updates, but also a dependency, migrations and more code to be judged.

**Switch only if you measure a problem.** A half-finished SQLite layer is worse
than working JSON, and this repo is judged on readability.

## 4. Identity and family

### No login screen

On first launch the following are created in the Keychain
(`kSecAttrSynchronizable`, syncs via iCloud to the user's devices):

- `member_id` — a UUID
- `device_secret` — 32 random bytes

The server stores only a hash of the secret, as it would for a password.
Requests authenticate with `Authorization: Bearer <member_id>.<device_secret>`.

An 80-year-old sees none of this. She gets a link from a grandchild and she is in.

### Invitations

```
POST /family              → create a family, the creator is the owner
POST /family/invite       → create an invite code, valid for 7 days
POST /family/join         → { code } adds the member
GET  /family              → members, own role, the invitations still open
DELETE /family/invite?code= → revoke a link
DELETE /family/member?id= → the owner removes a member (5 Sep 2026)
```

**The invite link is the entire security boundary.** Anyone who receives the
link sees all of the family's memories. Therefore:

*Read strictly, that sentence stopped being true when lever 3 shipped, and it
is corrected here rather than below because everything that follows depends on
it.* **There is a second credential, and it is an Apple account.**
`Keychain.query(_:)` in `Identity.swift` builds one query shape for all three
entries — `member_id`, `device_secret` and `family_key` — and every one of them
carries `kSecAttrSynchronizable`. So the member secret that authenticates and
the family key that decrypts both travel to every device signed into the same
Apple ID. That is the mechanism "The identity survives deleting the app" below
is about, and it is presented there purely as resilience, which is half the
story: it is also a way in. Nothing in the app or the docs said so until
9 Sep 2026. Whoever holds the Apple account holds the archive, invitation or
no invitation.

- The code is long and random, not meant to be read by a human — 16 random
  bytes, 128 bits, base64url. Guessing it is not a threat model
- It expires, and the owner can revoke it at any time
- **It admits one person** (since 5 Sep 2026). The join claims the code with
  a conditional `UPDATE … WHERE used_count = 0`, so two phones opening the
  same link in the same second cannot both get in; the second person through
  is refused in the same words as a wrong code, because a used code confirmed
  as used is a code confirmed as real. `used_count` had been recorded and
  compared to nothing, so one link forwarded on through a group chat was a
  week-long key for everybody in it (founder's-eye review, finding #33). The
  invitation already asked who it was for (§11.3 in docs/UX.md); now it is for
  exactly that person, and the same phone coming back — a reinstall, an iCloud
  restore — still comes through the door it came in by
- **The owner can close the door behind somebody** (since 5 Sep 2026).
  `DELETE /family/member?id=` marks the row `left_at` exactly as leaving does
  (§14): the memories stay, the name on them keeps resolving, and
  `authenticate` refuses the identity on every route from then on. Until then
  the only way out of a family was one's own, so whoever tapped a forwarded
  link was in for good (finding #32). **Every open invitation of the family
  goes with them**, because the invite text carries the family key and the
  person being removed may hold any live link — being forwarded one is how
  they got in — and the dialog on the phone says so. **The key is not
  rotated**, and that is a decision: nothing sealed under it reaches a refused
  identity again, what is already on their phone no rotation could take back,
  and the only other road to the ciphertext is a live invitation, which the
  removal has just closed. Only the owner, and never their own row — leaving
  is `leaveFamily`, which knows how to hand ownership on
- **Creating a family and joining one are rate limited**, per IP, with
  Cloudflare's `ratelimits` binding: 5 and 10 a minute. They are the only two
  routes in the Worker that write without a member identity, so they are the
  only doors an uninvited caller can knock on — and both insert rows. The limit
  is aimed at that unmetered write rather than at the guess, which the entropy
  above already answers
- **The boundary is checked against the deployed Worker, not only a local
  one.** `scripts/invite-boundary-check.mjs` takes a URL; first production run
  29 Aug 2026, twelve cases green; 5 Sep 2026, 25 of 25, the same evening the
  thirteen cases for one person per code and the owner's removal were
  deployed. The local Worker meters the join door with the same numbers as
  production does — the first local run of the fourteen joins failed its
  last five with `too_many_requests` — so the script moves to a fresh
  synthetic address at the ninth join locally, and against production waits
  the minute out, which the run's log says while it does. It had never been pointed there before, and
  the first attempt failed on its first line — the script sends a synthetic
  `CF-Connecting-IP` so that seven checks in `verify.sh` do not starve each
  other's rate limit, on a comment claiming Cloudflare ignores a client-set
  value. It does not: the edge refuses the request with `403 error code: 1000`
  before the Worker is reached. The header is local-only now, and the expiry
  case picks `--local` or `--remote` from the same fact — it had been ageing a
  database nothing was reading
- **The invitation carries the name it is for**, and that name is never handed
  back out before joining. `invite.display_name` is written by whoever creates
  the code — the grandchild, who knows — and `joinFamily` uses it when the
  joiner leaves the name field empty: `input.displayName ||
  invite.display_name || 'Perheenjäsen'`, the joiner's own typing always
  winning. The obvious design was to show the suggested name on the join form
  for her to accept or correct, and it was refused: that needs an
  unauthenticated lookup of a code, and a lookup that answers for a real code
  and not for a wrong one is precisely the oracle the rule below denies. So the
  name travels one way. It buys the one thing worth buying on that path — the
  80-year-old joining from a link types nothing at all. See docs/UX.md §11.3
- **A member can change their own name**, since 6 Sep 2026, behind the pencil
  on the Perhe screen — the same symbol the person card uses for *"Korjaa
  nimi"*. `PATCH /family/me` writes `member.display_name`, which every
  telling's author is resolved from at pull time, so one change reaches every
  memory that member ever told, on every phone, on its next pull;
  `family-sync-check.mjs` pins that, the trimming, and the refusal of an empty
  name — 16/16 against production on 6 Sep 2026 (`6812b0d4`), the script's
  first production run. One's own only: there is no route to rename anybody
  else. Until then
  the name was written at the join and never again, and a joiner who left the
  form empty on a code made without a name was *"Perheenjäsen"* for good
  (founder's-eye review, finding #64). Not a row on the member list: one
  row's worth of height on the owner's row moved the list's resting place so
  its last invite row sat twelve points above the bar, and the bar's own
  item changes no geometry
- **A member can be a card in the tree**, since 13 Sep 2026, and a
  grandparent who joins through an invitation becomes the card the inviter
  made for her. `PATCH /family/me` takes `personSubjectID` (null unlinks),
  `POST /family/invite` takes the card it is for (`invite.person_subject_id`),
  the join links to it, and `GET /family` returns the id on every member and
  on `you`. The founder's own card is made from their name when the family is
  created and linked after the round that pushes it; the first minute's
  invitation pushes its card before naming it. **The foreign key decided the
  shape.** D1 enforces foreign keys on every query and a query cannot turn
  them off (Cloudflare's D1 docs); measured on the local D1, a member row
  naming a missing subject fails, and through the Worker a push naming one is
  a 502. A card reaches D1 only when its phone syncs, and the join claims its
  code before it inserts the member, so writing an unsynced id would burn her
  invitation. So no statement writes the link unless the same statement finds
  a live person card of that family: otherwise she joins unlinked, the reply
  names the card, and her phone links itself once a pull brings it.
  `invite.person_subject_id` has no `REFERENCES` for the same reason.
  `invite-boundary-check.mjs` presses on it in fifteen cases; against a
  `family.ts` that wrote the id directly, eight went red — a join answering
  502, and a member linked to another family's card, which the key alone
  never refused
- **A member linked to no card can say which card is theirs**, since 26 Sep
  2026, on the person card: *Tämä olen minä*, a second row in the face's
  section. Offered only while this phone's member is linked to no card and
  waiting for none, only on a confirmed person (rule 4: a name heard and
  never checked is nobody's to be yet), never on a card another member
  already is, and never on a phone kept to itself, which has no server to
  tell. It asks first; one's own card answers *Tämä olet sinä* — linked, or
  waiting for the round that links it — and takes the mark back behind a
  second question, because nothing else changes the link: `family.ts` keeps
  a member's card through leaving and joining again, so a link made by a
  slip stayed for good. The same `PATCH /family/me`, null included, which
  the app had never sent: a server that cannot be reached, or does not hold
  the card yet, leaves the card waiting for `SyncEngine.linkOwnCard` exactly
  as the founder's own does, and the footer says so; taking a mark back
  without the server changes nothing and says that. Until then the founder
  and the first minute's invitee were the only members with a card, and a
  joiner from an invitation made for nobody in particular had no word in the
  tree and no way to get one (founder's-eye review, gap 8). `OwnCardTests`
  walks the road and its refusals; `-you none` is the seeded family linked
  to no card and `-theirs <card id>` puts another member on one. The row
  sits above the relatives, and the audit's default-size simulation
  reported *"Lisää sukulainen"* the moment it did — y 630 on the card
  offered, y 642 on the card waiting, the button's code untouched, the same
  card without the row clean, the real AccessibilityXXXL launch clean on
  every run: the §15 signature, sixth appearance.
  `AccessibilityPolicy.isDefaultSizeSimulationArtefact` forgives
  `.dynamicType` on `relative.add`, on the first launch only, and
  `scripts/audit-exemption-check.mjs` pins it with the rest of that set. The
  identifier sits on the button's label, not the button: the audit reports
  the label as a static text, and an identifier on the button matched
  nothing — measured, the finding unchanged, before it was moved
- The family view shows who has joined **and when**. The date was decoded from
  the server and never drawn until it was looked for: a stranger in the list is
  a question, and a stranger who arrived last Tuesday is an answer about which
  link went astray — and, since 5 Sep 2026, a question the owner can act on
  from the same row. The invitations listed are the ones still open, each
  with the name it was made for; a used one is no longer open and no longer
  listed

**A missing binding allows the request and logs a warning**, which is the
arguable half. Failing closed would mean one configuration mistake stops every
new family from being created, and the app is deliberately vague about causes
(rule 9), so nobody would ever diagnose it from the phone. Verified against a
local `wrangler dev`: ten joins pass and the eleventh is 429, five families pass
and the sixth is 429, the window resets, create → invite → join still works end
to end, and with the binding removed the request goes through with
`[ratelimit] no binding … allowing the request unmetered` in the log.

That was a hand-run, which is not a check: it does not happen again when
somebody edits `wrangler.jsonc`. `scripts/rate-limit-check.mjs` is the same
measurement made repeatable, plus the two properties a hand-run could not easily
reach. **The limit is per address** — keyed on anything constant, one busy
household locks every other family in the world out of ever being created, and
rule 9 means nobody could diagnose that from the phone. **And the two doors keep
separate buckets**: sharing a namespace id would mean a family that has just
been created cannot be joined from the same sofa, which is exactly the moment it
is joined. It also asserts the other half of rule 2 — a session that has used
its five creations can still tell the archive something.

**Shown to be load-bearing**, twice, in a throwaway worktree with its own Worker
and database. Keying the limiter on a constant reddened only the per-address
case; giving the join door the create door's namespace id reddened only the
two-doors case.

This is a point where simplicity and security genuinely conflict, and the choice
is deliberate: ease wins, because a login wall would drive away exactly the user
the app exists for.

### The shape of the invite link — a known shortcoming

The link is `kinlore://join?code=...`. **iOS shows a confirmation dialog for
custom URL schemes** ("Open in Kinlore?"), which is in English and is one extra
step for precisely the user who is most easily confused.

A universal link (`https://…`) would open directly without a dialog, but it
requires a domain and an AASA file — that is, store-release infrastructure.

The mitigation is already in place: the shared text contains **both the link and
the code**, and the join form has a paste field. Grandmother gets into the
family even if the link never opens at all. If a domain is ever acquired, this
is the first thing worth changing.

**And the dialog had a second cost that took longer to see.** Because tapping
the link goes through a prompt rather than straight into the app, the app is
usually *already running* when the code finally arrives — she opened it to look
before using the link, or the message was read with the app in the background.
The onboarding screen read the code in `onAppear`, which fires once, so in that
case the code was dropped: she tapped Open, watched the app come to the front,
and found the same two buttons with nothing filled in. Cold launch worked, which
is why it looked fine.

It is read on change now, and cleared once used so that a code from a family she
has since left cannot fill itself in over a fresh invitation. A link is a
deliberate act and the most recent one, so it wins over whatever is in the
field.

Both halves of the delivery were checked on a simulator — the scheme is
registered, and `kinlore://join?code=…` reaches the app cold and warm. The tap
on the system dialog itself could not be automated here, so what happens after
Open rests on the code rather than on a run.

**And the key fell off exactly there.** Found 17 Aug 2026: since lever 3 the
shared link is `kinlore://join?code=<code>#<key>`, the family key riding as
the URL fragment — and the parser read query items, which a fragment never
reaches. A tapped link therefore joined its family without the means to read
it, while the pasted text, handed whole to `Session.split`, worked. Silent in
the worst way: everything looks joined, and nothing sealed had ever been
synced yet to disagree. The parser reattaches the fragment now, and `-invite`
accepts a full URL so the test drives the real parser instead of bypassing it
(`SilentFailureTests.testATappedLinkKeepsTheFamilyKey`).

### The identity survives deleting the app

Keychain entries persist across app deletion, and `kSecAttrSynchronizable`
carries them via iCloud to the user's other devices. Verified: the same member
id across three launches, including after deletion and reinstallation.

That is the correct behaviour for this audience. Accidentally deleting the app
must not mean losing the family.

**Until 26 Sep 2026 it did mean exactly that, one level up.** The identity came
back and the family id did not: it lives in UserDefaults, which a deletion
empties and an Apple account does not carry. So the phone that came back landed
on the fork as a stranger, and a member cannot use the fork.
*"Aloita perheen arkisto"* is `POST /family` with an identity the server
already has, refused as `member_exists`; *"Liity kutsulinkillä"* needs somebody
in the family to notice and send an invitation. The server would have let the
member back through any invitation to their own family (the reinstall case
under "It admits one person" above), but nothing on the phone knew to ask.

Now it asks. An identity that was already in the Keychain when the app launched
— never one made by that launch, which cannot be a member of anything — puts
`Session.homecoming` at `.asking`, and the onboarding screen asks `GET /family`
before it offers the fork (`Session.lookForFamily`). Exactly one answer is read
as "no family": the server's own `{"error":"unauthorized"}`, which
`FamilyError.forStatus` maps to `.unauthorized` and which a stranger and a
member who has left get alike. That opens the fork as before. A family in the
reply is `.found`: a page that names it and opens it with one button. **Every
other outcome — no network, a timeout, a 5xx — is `.unanswered`, not a no.** It
keeps the fork hidden, because for a member the fork's two roads are the
refusal above and an archive set up apart from the family, and it asks again
when the app comes to the front, when `NWPathMonitor` reports a path back, and
on its *"Yritä uudelleen"* button. An invitation tapped meanwhile waits for the
answer and is used the moment the answer is no. The pages are docs/UX.md §4.5.

`Session.returnToFamily` writes the family id and the arrival flag, and nothing
else. **It writes no key.** Where the Keychain has the family key, it is already
there; a phone that has lost it is held at `.keyMissing` by `SyncEngine` —
nothing pushed, uploaded or taken in, one pull asked for and thrown away —
until an invitation brings the key back through `Session.rejoin`, as it does
for any phone in a family that has lost its key.
`scripts/keyless-sync-check.swift` counts the roads in `Session.swift`:
`FamilyKey.create()` once, `FamilyKey.adopt(` twice, `FamilyKey.store(` and
`Keychain.write(` never. A copy of `returnToFamily` that stored the key again
was compiled against the count, and it went red. Nothing is written for the
person card either: `GET /family` returns `you.personSubjectID`, so a returned
phone learns its card from the server, not from `pendingPersonLink`.

The page cannot tell a reinstall from a new phone on the same Apple account,
and its words do not try. Two limits, both priced. An identity that never
joined anything asks too — one made by an earlier launch that stopped at the
fork is held by the next — so that launch, offline, waits on the page rather
than opening the fork: strict, for a case that is rare and harmless. And the
text floor (*"Kenen puhelin tämä on"*) is device state, so a phone that came
back starts without it. `ReturningPhoneTests` drives all three answers
(`-seed returning`, `-homecoming ask`, `-homecoming unauthorized`), and every
other UI test launches with `-homecoming off`, because the simulator's Keychain
keeps an identity from one test to the next.

### The boundary, pressed on

Reading the join path is not the same as trying it, and this is the one place
where the difference is not academic: there is no login, so whoever holds a code
sees a family's memories of their dead relatives.

`scripts/invite-boundary-check.mjs` presses on it against a running Worker. An
invited member gets in; a made-up code, a revoked code and an expired code are
all refused **in the same words**, because a different answer for a real-but-
late code tells a guesser they have found a family; a member of another family
cannot be pulled across; and a stranger cannot revoke somebody else's invite,
nor does the attempt damage it.

**"The same words" holds for a caller with no member row, and that is the
caller the rule was written against.** Qualified 9 Sep 2026, because the prose
had claimed it without limit. One class of caller can tell the answers apart: a
device that already belongs to *another* family gets `member_exists` 409 for a
valid code and `invalid_invite` 404 for a fake one (`family.ts`), so it learns
whether a code is real. The check script asserts that distinction on purpose,
which is why the two disagreed until this paragraph existed.

It is a leak and it is priced. What it hands over is existence, to somebody who
cannot spend it — the same 409 that tells them the code is real is the refusal
that keeps them out, and a fresh install, which is what a guesser actually has,
gets the identical three words every time. The alternative is answering a
returning device with a lie, and §11.3 in `docs/UX.md` is about the cost of
unclear refusals to exactly this audience.

Ageing a code past its expiry has no route and should not have one, so that case
reaches into the local D1 directly — which is also where the check taught its
author something. Pointed at a second Worker on another port it aged the
*first* one's database and the expiry case passed for the wrong reason: a green
check measuring nothing, the exact failure this repo keeps finding. It takes
`KINLORE_WORKER_DIR` now.

**Shown to be load-bearing.** The revocation check was deleted in a throwaway
worktree, with the mutated Worker on its own port and its own database so no
other session's was touched, and the run came back red on exactly that case.

### The session afterwards

The invite is the door; `authenticate` in `backend/src/auth.ts` is everything
after it. `scripts/session-boundary-check.mjs` presses on that: a right member
with a wrong secret, a member who does not exist and a token with no shape are
all refused alike; one family reads nothing of another's, and a write aimed at
another family's row does not land on it. What is stored is a SHA-256, not the
secret — read out of the database rather than taken on trust — so a leak of D1
is not a set of keys.

The rule worth having a check for is **the member who has left**. Their row is
kept on purpose, so the names on the memories they recorded still resolve, which
makes "in the database" and "in the family" two different things separated by
one column. Nothing else in the suite covers it, and it is silent when broken: a
departed member who can still read looks exactly like a working app to everybody
except the family who asked them to go.

**Shown to be load-bearing.** `if (row.left_at) return null` was deleted in a
throwaway worktree, Worker and database of its own. The departed member's read
came back `200` and that one case went red; the other eight stayed green.

Since 26 Sep 2026 the same script also holds the contract the returning phone
reads (§4, "The identity survives deleting the app"): a member who asks
`GET /family` is told her own family and herself in it, an identity the server
never saw and a member who has left both get `401` with `unauthorized` — the
one word the app reads as no — and a member who starts a family instead is
refused as `member_exists`.

## 5. Media

Photos and audio go to R2, metadata to D1.

```
POST /media          → upload a file, returns r2_key
GET  /media/:key     → download (checks family membership)
```

The local filename and the R2 key are **different fields** (`imageFilename` and
`r2Key`). The same photo has a different filename on each device but the same
key, so one field would not be enough.

**The bytes in that bucket are sealed, and this section did not say so until
9 Sep 2026.** Everything below — the routes, the byte-for-byte check, the whole
`Checked` subsection — was written as though a plain file passes through the
Worker, and `grep seal` over these 120 lines returned nothing. It does not.
`SyncEngine` seals every photograph and every recording under the family key
before upload, and `MediaLoader` opens them on the way back; what R2 holds is
`Data("k1.".utf8)` followed by an AES-GCM envelope. `docs/RECOVERY.md` had the
fact right — *"Photographs and audio, sealed"* — so the architecture section
that owns media was the only place it was missing.

Three consequences that belong here rather than in §10 of the plan. The file is
**not re-encoded**: sealing is an envelope, so what a family gets back is the
exact recording, which is what rule 3 is about. The size ceiling is measured
against the **sealed** body, not the original. And a seal that fails uploads the
plaintext rather than dropping the file — the right trade against rule 3, and a
silent one: nothing anywhere checks per object whether the bytes in R2 are
actually sealed, and an unsealed object is shape-identical to a pre-lever-3 one
because `FamilyCrypto.open` passes unmarked bytes straight through.

Upload happens **before push**, so rows travel with their keys. Otherwise the
other device would see the memory but not the photo it belongs to.

Fetching for the views is **on demand**: a family may have hundreds of photos,
and they are not fetched at launch. The grid fetches only what is visible.

**And since 5 Sep 2026 the phone also keeps the whole thing.** Until then the
views' policy was the archive's: everything nobody had happened to open
existed in R2 alone, and R2 exists for as long as one hobbyist's Cloudflare
account does (founder's-eye review, finding #86; docs/RECOVERY.md). `FullCopy`
runs after every successful sync round, in the background, and fetches every
photograph and recording that exists only as an R2 key — voices first, because
a recording cannot be made a second time; on a cheap network only, never
cellular or a hotspot, so a phone that never meets Wi-Fi never copies and the
family screen says so; never into the phone's last gigabyte; three failures in
a row end a round and the next sync starts another from where it stopped; one
round at a time. The family screen's *"Kopio tällä puhelimella"* row carries
the number, because a copy that never started looks exactly like one that is
complete. `scripts/full-copy-check.swift` holds those rules with the network,
the disk and the fetch handed in as closures.

**What it weighs — measured 6 Sep 2026.** The sizes this section used to
quote were guesses, and both were low. One minute of voice as `AudioRecorder`
writes it (AAC, 22.05 kHz, mono, medium quality) is **268 kB** — 4.5 kB/s, so
90 seconds is 403 kB and not 200 — measured by writing 60 s of speech-like
signal through `AVAudioFile` with the recorder's own settings. A photograph as
`MediaStore` stores it (2048 px, JPEG 0.85) is **340–990 kB** from a
12-megapixel original: 342 kB for a smooth synthetic album page, 987 kB for
the same page with film grain at every pixel, and a photographed print lands
between the two; no real photograph was on the machine to measure. So the
family this paragraph used to imagine — 3 000 photographs and 2 000 tellings
of 90 seconds — is **2–3.8 GB per phone**, not 1.3.

The copy was then run against a real Worker for the first time: a seeded
family of 100 photographs, 50 recordings and 1 900 text tellings on
`wrangler dev`, joined from a fresh private simulator through the invite
form, with the app's container watched from the shell every five seconds.
**The first run fetched nothing.** `NWPathMonitor.currentPath` is
`unsatisfied` from `start()` until the monitor's first report — 1 ms later,
measured — and `NetworkPrice` started its monitor on the first question it
was asked, which was this round's: the copy halted as *waiting for Wi-Fi* on
a Wi-Fi machine, the family screen said so, and nothing in the check script
could have seen it, because the network arrives there as a closure. The
engine warms the monitor at init now. The second run copied all 150 files,
82 MB, in ten to fifteen seconds — and wrote the store's 5.4 MB JSON 150
times over, once per file, because `setLocalImage` and `setLocalAudio` each
saved. For the archive above that is roughly 30 GB of JSON written to copy
2–4 GB of media, on the main actor. **So the round writes in batches now**:
the filename is recorded in memory (`saving: false`), and the store is
written every tenth file and once more at the end of any round that recorded
anything, whichever way it ended — a phone killed mid-round fetches at most
nine files again and leaves at most nine unreferenced files behind. **Nothing
removes those** — corrected 9 Sep 2026, where this used to say the next wipe
did. `MemoryStore.wipe()` deletes the files named by a surviving row and then
removes the store JSON; a file no row names is reachable from nothing and is
never deleted by anything in the app. Nine stray files after a killed round is
a small enough bill to accept, and it is a bill rather than nothing. The third run, same seed: 150 files in six to seven
seconds, fifteen writes of the store instead of 150, every one of the 150
filenames in the file afterwards. The fetch through the Worker is the larger
half of the per-file cost on this machine; on an old phone the encode is the
half that would have grown. `full-copy-check.swift` holds the batching with
the same fake phone: at ten, at twenty and at the end, once for exactly ten,
never for nothing, and once for a round that failures or the network ended.

**In the MVP the file passes through the Worker.** At the sizes above that is
entirely sufficient. Presigned URLs are the right answer for larger files, but
right now they would only add moving parts.

Upload is part of the outbox: a photo appears locally at once, and other family
members see it when sync catches up. A photo added offline is not lost.

**The ceiling used to be swallowed whole.** Found 17 Aug 2026: the free tier's
photo limit is enforced at `POST /media` with a 402, and the client's upload
path threw the same bare `URLError` for it as for a dead network — then
discarded even that with `try?`. The 21st photograph looked normal in the
grid and silently never reached the family; no path on the client could ever
produce the photo-quota sentence `RemoteError` carries. The 402 is decoded
now (the same shape `AppServices` already decodes for transcription), the
engine counts the refusals per round instead of swallowing them, and Muistot
carries a quiet note — *"…ei mahtunut ilmaiseen arkistoon. … tallessa tässä
puhelimessa ja lähtee perheelle kun tilaa on."* — in the `SyncNote` register:
no modal, no badge. Going paid re-syncs at once, which is what clears it.
The note's state is held still for the audit by `-photos-refused`; the
decode itself mirrors a proven path rather than having a Worker-driven check
of its own, and that is stated here rather than implied otherwise.

**And every other phone was left spinning.** A refused photograph's card
still syncs — `pendingPayload` sends a changed subject whether or not its
file went up — so the rest of the family holds a photograph with no file and
no key to fetch one by. Until 26 Sep 2026 its tile stayed grey and its card
drew a `ProgressView` for as long as anybody looked, while only the phone
that added it said anything. `MediaLoader.hasNotArrived` names that state
now. The tile draws an hourglass and gives *"Kuva ei ole vielä tullut
perille"* as its accessibility value; the card says where the photograph is
and what it waits for — *"…kun perheen ilmaisessa arkistossa on tilaa"* when
`Session.isOutOfPhotos` reads the family at the count the refusal reads,
*"…kun se lähetetään sieltä"* otherwise. A fetch that fails says so and
offers *"Yritä uudelleen"*, the spinner is left to a fetch that is actually
running, and both loads are keyed to the key and the file, so a key that
arrives while the screen is open is fetched rather than missed. `-seed
unarrived` holds both states still for `SyncVisibilityTests` and two sweeps.
The demo archive's photograph has no file either, nor does one from
`-import`, so every sweep of their cards now measures the second sentence
where it used to measure a spinner. That cost the default-size audit one
finding: its simulation grows the words until the rename row under them
cannot be measured whole — *"Anna kuvalle nimi"* at the same point on three
screens, and gone with the spinner put back — which is the §15 signature
once more. `AccessibilityPolicy.isDefaultSizeSimulationArtefact` forgives
`.dynamicType` on that row's identifier, `subject.rename`, on the first launch
only — it sits in the same set as the memory row's — and
`scripts/audit-exemption-check.mjs` pins it with the rest of that set.

**The original audio is always uploaded**, including on the free tier. It is the
core of the product, not an extra.

### Checked

`scripts/media-check.mjs` presses on the two directions and the boundary between
them. A photograph goes up and comes back **byte for byte** — a corrupted one is
corrupted invisibly until somebody looks at it years later, which is the whole
failure this archive exists to prevent. Audio is accepted on the free tier with
no reference to the photo ceiling, which is rule 3 written as an assertion: a
family out of photograph slots must still be able to keep a voice.

And the one that matters most: **another family gets nothing.** The key carries
the family id and the prefix is checked before the bucket is touched, so a
guessed key does not even cause a lookup, and the answer is `404` rather than
`403` — it does not say whether the guess was close. Somebody with no identity
at all gets `401`.

**Shown to be load-bearing.** The prefix check was deleted in a throwaway
worktree with its own Worker on its own port, and the run came back red on
exactly that case: status 200, a stranger holding another family's photograph.

Locally `wrangler dev` gives R2 a simulated bucket, so none of this touches real
storage — which also means it is the shape of the round trip that is checked,
not Cloudflare's.

## 6. Money

### The model

The payer is not the beneficiary: the grandchild buys, the whole family gets it.
RevenueCat grants the right to the buyer; the backend spreads it to the family.

```
POST /entitlement/sync   → the client reports a purchase, the server VERIFIES it
POST /webhook/revenuecat → renewal, cancellation, refund
```

**The client's word is not trusted.** `/entitlement/sync` does not accept a
state but a hint: the server asks RevenueCat's REST API for the truth using
`RC_SECRET_KEY` and writes `family.entitlement` based on that. The webhook keeps
it current without the app having to be opened.

### Edge cases that must not be forgotten

| Situation | Behaviour |
|-----------|-----------|
| Subscription ends | The family returns to the free tier. **Nothing is deleted.** Existing photos and audio remain and stay readable; the limits apply only to new content. |
| The payer leaves the family | Nothing happens at the moment they leave — see the row below the table. Another member can buy. |
| Two payers | The longest expiry wins. Neither is shown anywhere. |
| Refund | The webhook drops the right immediately. There is no REFUND event: it arrives as CANCELLATION with `cancel_reason: CUSTOMER_SUPPORT`, which is the only cancellation that revokes. |
| Auto-renew switched off | Nothing, until the EXPIRATION event ends the period that was paid for. This was assumed wrong once — a plain CANCELLATION revoked at once, locking the family out of a paid month — and `webhook-revocation-check.mjs` now pins the split. |

The rule **"downgrade never deletes"** is absolute. A family that loses memories
when the payment ends never comes back, and that is not a product worth building.

**Two rows in that table were wrong, and one of them is a defect rather than a
sentence.** Both corrected 9 Sep 2026.

*Two payers.* "Both are shown in the family view" was never built. `getFamily`
selects `id, name, entitlement, sync_seq` and returns no payer at all, and the
Perhe screen draws one row, *"Tila: Maksullinen / Ilmainen"*. Nothing anywhere
names who is paying. The arithmetic half — longest expiry wins — is real code.

*The payer leaves.* **Leaving does not lapse anything.** `leaveFamily` writes
`invite.revoked_at`, `member.left_at`, the leaver's role and the new owner's
role, and touches `member.rc_app_user_id`, `family.payer_id` and
`family.entitlement` in none of its statements; `removeMember` is the same. So
the family keeps the paid tier until a revoking webhook happens to arrive on its
own schedule — which is the safer direction of the two, and is not what the
table promised.

The other direction is not safe, and nobody had written it down. **The departed
payer's customer id stays bound to their old family's member row for ever**, and
`syncEntitlement` refuses a customer id that belongs to another family with a
409 `customer_belongs_to_another_family` *before* it calls RevenueCat. So a
person who leaves one family and joins another cannot make their subscription
work in the new one, at all, and the error they would see is about a family they
are no longer in. Nothing releases the binding: the only `NULL`ing of
`rc_app_user_id` is the restore path inside a family.

Recorded rather than fixed — it needs a decision about what a purchase follows,
the person or the family, and §6 has been arguing that both ways since PLAN §9.
The one-line version of the fix, when it is made, is that leaving must release
the binding the same way the restore path does.

### After the money

The purchase belongs to the buyer and the archive belongs to the family, and the
second one is what they think they bought. Everything between the two is ours,
and it is the part that can be reasoned about without a RevenueCat key — which
is what was done, because the key is still missing and the screen itself is
still unverified.

Two things were wrong in it.

**A failed handoff was silent.** `syncPurchase` threw the result away — `try?`,
then `refresh`, then the sheet dismissed itself regardless. A purchase made
while the Worker was unreachable therefore closed the sheet over a family view
still reading *"Ilmainen"*, having said nothing whatever to somebody who had
just been charged. The person who does that twice is not being careless. The
call now answers **whether the family actually has the archive** — not whether
the request succeeded, which is a different and less interesting question — and
the sheet stays open to say so: *"Kiitos — maksu meni läpi. Perheen arkisto ei
vielä ehtinyt avautua… eikä sinun tarvitse maksaa toista kertaa."* That last
clause is the one that matters.

**The recovery ran at launch only.** `syncEntitlementIfPurchased` reports an
unreported purchase again, which is why nothing was ever lost — but it fired in
`task`, once, at a cold start. A phone that is never quit is most phones, and it
could carry a paid-for archive the family did not have for days. It runs on
returning to the foreground too now; the guard is a cached RevenueCat lookup and
answers false on every device that has bought nothing.

**Still unverified, and honestly so:** the paywall screen itself. It is
RevenueCat's own view, it requires the SDK to be configured, and without a key
`paywallSheet` deliberately renders nothing at all. When a Test Store key
exists, `-rcKey <key>` is enough to see it — and the first thing to check is not
that it looks right but that a purchase reaches `family.entitlement`, with the
Worker deliberately stopped once to see the sentence above.

### The purchase, verified rather than believed — 1 Sep 2026

`/entitlement/sync` does not accept a state from the client, it accepts a hint:
the app says *this customer bought something* and the server asks RevenueCat.
That sentence is the reason the endpoint exists, and until this date nothing
checked it — §1 carried the row *"the REST verification and the webhook need
keys and are unrun"* for two weeks after the webhook half had stopped being
true.

The key was never what stood in the way. `scripts/entitlement-sync-check.mjs`
imports the real `syncEntitlement`, runs it over the shipping `schema.sql` in
in-memory SQLite behind a D1-shaped shim, and replaces `fetch` with something
that answers like RevenueCat and keeps the request — the same technique
`data-collection-check.mjs` uses, and for a reason that applies twice as hard
here: the request that proves the payer's account is protected must not be the
request that sends it somewhere.

Thirty checks, and the ones worth naming:

- **A purchase RevenueCat has never heard of unlocks nothing.** This is the
  request an attacker makes and also the request a confused app makes, and it
  is the single claim the endpoint exists to enforce.
- **An entitlement that has already run out opens nothing**, and a perpetual one
  — `expires_at: null`, which is also what *no date* looks like — opens
  everything. Read the wrong way round, the second is the first.
- **The 409 answers before asking RevenueCat anything.** The database refuses
  the second binding in any case (§6 above); this is the guard over it, and the
  part worth pinning is that a refused claim costs no upstream request.
- **A restore inside the family moves the binding** rather than adding one. This
  is the check that found the file's own defect: breaking the release makes the
  UPDATE violate the unique index, the case threw, and the run printed every
  earlier `ok`, then its own closing line *"The purchase is verified rather than
  believed"*, and only then a stack trace. A green sentence over a failed run is
  what every check in `scripts/` exists to prevent, so a throw is now a failure
  of the case that threw.
- **The two-payer rule through this path.** The longest expiry wins, and only
  the webhook had ever exercised it.
- **Rules 7 and 9 on the one path where the upstream body is a subscriber's
  account.** The key is in the Authorization header and nowhere in the URL; a
  failure logs the status and RevenueCat's numeric code and none of the body,
  and neither does the message of the error that is thrown — `message` is the
  one field of a thrown error that reaches the log. The 409's own line says
  *another family* and names no ids.
- **No key configured answers `revenuecat_not_configured`** and asks nobody
  anything, because that is the branch a real install takes today.

**Nine deliberate breakages, nine caught** — trusting the client, moving the 409
below the fetch, logging the body, moving the key out of the header, reading a
perpetual entitlement as none, dropping the restore's release, swallowing the
upstream failure, letting the newest payer always win, and putting the ids back
in the 409. That list is the argument for the file; an all-green first run is
not one.

What this does **not** check, and no amount of it could: a real Test Store key,
a real purchase, a real webhook signature, and the paywall screen. Those are
still the first things to do the day a key exists.

### Driven end to end, 12 Sep 2026

The section above proved the logic with RevenueCat replaced. This is the day it
ran against the real one, and the row in §1 changed because of these two
measurements rather than because the code looked right.

**A purchase reached `family.entitlement`.** A Test Store purchase on a
simulator, and the production row went from `free` with no payer to
`archive`, `payer_id` set, `entitlement_expires_at` set — and `member.
entitlement_expires_at` with it, which is `c519132`'s column getting its first
real value. The baseline was measured first: ten families, all free, no bound
payer. So the row could not have been old.

**And a signed event reached the deployed Worker.** From `wrangler tail`:

    POST .../webhook/revenuecat — Ok @ 14:40:57
    (log) [entitlement] INITIAL_PURCHASE → archive

That line is the one that cannot be faked, and the reason is worth keeping.
`Ok` rather than 401 means the Authorization header matched `RC_WEBHOOK_SECRET`
byte for byte. `INITIAL_PURCHASE` is RevenueCat's own event-type string, and
`handleWebhook` is the only thing in this repository that logs it —
`syncEntitlement` logs nothing on success. So the line cannot have come from
the app's own path, which was already proven and is a different claim.

**Two things had to be got wrong first, and both are the same mistake.**

A watcher polled D1 for the entitlement changing and called that proof. It is
not: a new purchase reaches `applyEntitlement` through the app's
`syncPurchase` as well as through the webhook, so a changed row says *one of
the two* worked. Then the same watcher saw `archive → free`, announced *"the
downward path is proven end to end"* — and that transition was a hand-typed
`UPDATE` clearing the stale row four minutes earlier. **A D1 row does not
record who wrote it.** The Worker's log does, which is why the proof above is
a log line and not a row.

**And then the real one arrived**, 27 minutes after the false claim, from the
same tail:

    (log) [entitlement] RENEWAL → archive      14:47:27, 14:51:30, 14:59:31, 15:03:31
    (log) [entitlement] EXPIRATION → free      15:07:31

D1 followed it: `free`, no payer, no date. So the downward path is proven too,
and by the thing that can carry the claim — `revokes()` is the function that
cost a family a paid month when it was assumed, and the rule
`webhook-revocation-check.mjs` pins now holds against the real service and not
only against an in-memory SQLite.

Four renewals and then the end, which is RevenueCat's documented Test Store
behaviour — accelerated renewals, at most five, then cancellation — read from
their documentation on 1 Sep and observed here on the 12th. VIDEO.md's fifth
scene depends on that clock: buy on filming night, not before.

**The paywall's own design, drawn the same day.** Until it was, `PaywallView`
fell back to RevenueCat's placeholder — pink, in English, with their cat and
the words *"No Paywall configured"* — which is what VIDEO.md's fifth scene
would have filmed.

The cause was not a wrong setting. **There was no paywall in the project at
all**, and the useful check is RevenueCat's own answer rather than the
dashboard's view: `/v1/subscribers/x/offerings` lists a `paywall_components`
key on the offering when one is attached, and omitted it. It still answers
that question in one line and needs no app and no simulator.

What it says is the app's vocabulary and not new words, because §21's rule is
that a new word is a new thing to an 80-year-old: *"Open the whole archive"* as
both the title and the button, the same words the button behind it already
uses; *"No limits, and one payer opens it for the whole family"*; and
**rule 2 said out loud on the money screen** — *"Telling is always free. It is
never limited."* The palette is `Elder.swift`'s: `#F6EEDF` ground, `#FFFAF0`
cards, `#1C1917` text, `#0B57D0` for the one blue button. RevenueCat's red
appears nowhere, and neither does a testimonial — there are no users to quote.

**Measured from the app's pixels rather than the editor's preview**, because
the editor cannot show either thing: text 15.17:1, white on the blue 6.39:1,
the discount label's blue on cream 6.14:1, package rows 96 pt and the button
84 pt against `Elder.minTapTarget`'s 60.

At the very largest accessibility size the package rows sit below the fold and
the screen scrolls to them. That was raised here as a defect and withdrawn:
the app's **own** Kerro screen does the same with its record button at that
size, with its shortened sentence and its 150 pt button cap already in effect,
and `IdleView`'s comment records that as a considered trade-off rather than an
oversight. The paywall is consistent with the app; there is nothing to fix that
would not also be a change to the app.

**One thing that cannot be fixed from here:** the prices read *9,99 US$* and
*79,99 US$*. Test Store has no currencies, real ones need App Store products,
and §2.1 closed that route on 24 Aug. It will be visible on the video.

**Superseded the same evening, and not yet redrawn.** PLAN §10 decided the
prices on 12 Sep 2026: a year at 50 and the archive for ever at 80, each
bought once, and no monthly plan. The paragraphs above describe the paywall
as it still is — two packages, a discount label, 9,99 and 79,99 US$ — and
they stay until the dashboard has `lifetime` back as a non-consumable,
`yearly` at 50 and `monthly` out of the `default` offering, when they are
rewritten from the pixels again rather than from the plan. One consequence
lives in this file and is easy to misread: `handleWebhook` ignores a
`NON_RENEWING_PURCHASE`, deliberately, because the event carries no expiry
and a null must not end a tier the event was not about — so the perpetual
purchase is granted through `/entitlement/sync` and reconciliation, never
through the webhook. PLAN §10 carries the arithmetic.

**One thing measured on the way, recorded because it is invisible.**
`quota.ts` reads `SELECT entitlement FROM family` and nothing in
`backend/src/` outside this file reads `entitlement_expires_at` at all. The
date is written and never compared. So the paid tier is gated by a word that
only an event can change — and the app cannot supply that event either:
`syncEntitlementIfPurchased` guards on `hasActivePurchase`, which is false once
the subscription lapses, so the device stops reporting exactly when the news
matters. **The webhook was the only path that could ever take the tier away.**
It works, as of today; the point was that if it stopped, nothing noticed, and
the family stayed paid with a date months in the past.

**Answered the same day, and not by either of the two obvious answers.** Making
the date authoritative would have been the opposite mistake: a webhook running
an hour late would end a month somebody paid for, which is what the assumed
CANCELLATION set already did once. Leaving the word authoritative is what the
paragraph above describes. So the tier is neither trusted nor distrusted — it
is **re-asked**, and only in the state that says it must be wrong.

`quota.isPaid` now reads the date beside the word as a **tripwire rather than
an answer**. A date in the future, or null for a perpetual entitlement, is the
end of it: no request, and one more column on a query it was making anyway. A
date that has passed under the word `archive` cannot be true, and
`reconcileStaleEntitlement` asks RevenueCat instead of guessing.

**Its failure mode is the whole safety property.** Missing keys, a payer with
no bound customer, an unreachable RevenueCat — each answers null, null means
*keep what you had*, and what you had is paid. Only RevenueCat saying nothing
is active ends a tier. And every member holding a customer id is asked rather
than `family.payer_id` alone, because `applyEntitlement` takes the MAX across
the family and a second payer who renewed while the webhook was missing has to
count.

`scripts/entitlement-reconcile-check.mjs` pins all of it over the shipping
schema with `fetch` replaced — twenty-two checks, and **seven deliberate
breakages, seven caught**: reading only the word, reconciling unconditionally,
reading a perpetual date as stale, downgrading on a failure, asking only one
holder, putting the ids in the log, and reconciling a family that was never
paid. Two of those seven were built wrong the first time — one never applied at
all and reported a green run, the other broke the query's parameters instead of
narrowing it — which is worth recording because a mutation that does not mutate
proves exactly nothing and looks identical to one that does.

### One purchase, one family

`syncEntitlement` takes the customer id **from the client** and asks RevenueCat
what that customer owns. Nothing checked whose id it was, and
`member.rc_app_user_id` had an index without a uniqueness rule — so the same
purchase reported from two families would have unlocked both.

The worse half is the webhook. It finds the payer with `WHERE rc_app_user_id =
?` and takes the first row, so a refund would have revoked the right from one
family and left the other paid for ever. An error in that direction does not
correct itself and nobody would notice until somebody read a bill.

Two answers, deliberately at different levels. The index is now UNIQUE and
partial — NULL is not a claim, and most members never buy anything — so the
second binding cannot be written at all. And `syncEntitlement` looks first, so
the case comes back as **409 `customer_belongs_to_another_family`** rather than
as a constraint violation: a refused claim is not an outage, and 503 would
invite the app to retry something that will never succeed.

What must keep working does: the buyer changes phone, or another member of the
same family restores the purchase — `onRestoreCompleted` exists for exactly
that. The binding *moves* within a family, released from the old row first.

**Checked by `scripts/entitlement-binding-check.mjs`**, which loads the shipping
`schema.sql` into an in-memory SQLite and asks it — no Worker, no D1, no
RevenueCat, none of which exists on this machine. The guard in TypeScript cannot
be run here at all; the database rule can, and it is the half that still holds
when the guard is wrong. Run with the index made non-unique again, two of its
six checks fail, which is how it was shown to be worth having.

### Where the paywall goes

Right after the first AI-structured memory is finished. That is when perceived
value peaks. Not in onboarding, not in settings.

**Telling is never paywalled.** The limits apply to the photo count and AI
minutes.

**But not after every telling, and never beside a name.** The moment is right
and it stays; what was wrong is that the card appeared every single time, on the
screen somebody reaches when they are most tired, between the names they have to
check and the way out. `UpsellRhythm` puts two rules on it:

- **Never against a proposal.** A name waiting to be confirmed is rule 4's whole
  mechanism — a wrong person becomes a fact if nobody looks — and an offer to buy
  something is the worst possible neighbour for it. That telling shows no card at
  all, however long it has been.
- **One in three.** Counted on the device in `UserDefaults`, never synced, for
  the same reason the question ladder's comfort is not (§12): it describes the
  person holding the phone, and a family has no business seeing how often
  somebody has been asked to pay. "Tyhjennä tämä laite" clears it.

The count keeps running even when the card is withheld, so a family whose every
telling names somebody does not stall the rhythm — the next quiet one carries the
offer. Four lines of arithmetic, every failure of them silent, so they are
checked by `scripts/upsell-rhythm-check.swift` rather than by looking.

**And never to a family of one.** Since 17 Aug 2026 the slot the card sits in
is shared: while the family is one person it carries the invitation instead —
*"yksi maksaja avaa sen koko perheelle"* was a false sentence with nobody to
open it for, and the invitation itself lived four levels deep in Settings.
`UpsellRhythm.card` decides which card and `UpsellRhythm.slotShows` decides
whether the slot shows at all — but only the paid archive keeps the rhythm
above. The invitation ignores it and waits on one thing instead, `case
.invite: !proposalsRemaining`, so it shows on every finished telling that left
no name unanswered. The check script covers both halves. The argument is
docs/UX.md §3.2.

**Two defects the check script could not see, found 23 Aug 2026.** Both lived
in the wiring around `UpsellRhythm`, which is exactly the half a check of the
pure function never touches. The slot's input was dead on every cold launch:
`session.family` and `usage` were populated only by `refresh()`, which nothing
on the launch or Tell path ever called — so from the second launch on,
`card()` read nil, the slot rendered nothing, and the rhythm counter was spent
on the empty view all the same; the launch and foreground tasks now refresh
beside the sync, which as a side effect also carries a webhook's verdict to
the devices that never bought anything. And the never-against-a-proposal rule
held only on the direct path: three interview exits — *"Riittää tältä erää"*,
a sub-second answer, a discarded one — reused the decision made before the
loop, while the rounds since had put fresh names on the result screen.
`leaveInterview` now narrows the decision on every exit, never widens it: a
slot already denied stays denied.

## 7. Quotas and moderation

### Quotas on the server

`usage_counter` is checked **before** the OpenRouter call and incremented after
it. The client's counter is not trusted — it can be edited.

**Half of that last sentence is true, and the half that is not is the meter
itself.** Corrected 9 Sep 2026. What the server does not trust is the client's
*tier*: `isPaid` reads `family.entitlement` from D1 and no request can claim it.
What it trusted until 10 Sep 2026 was the client's *number*. `recordAISeconds`
was handed `payload.seconds ?? 0` — the duration the app read off its own file —
so both the meter and the hallucination guard in `budget.ts` ran on a field the
caller supplies and may simply omit. An omitted `seconds` rounded to zero and
`recordAISeconds` returned before writing anything, so a client that stopped
sending the field transcribed without ever spending a second of the family's
month.

**The bytes are the one thing the caller cannot lie about, because the Worker
counted them.** `boundedSeconds` in `budget.ts` clamps the claim between what
that many bytes can hold at 40 kB/s and what they can hold at 1 kB/s — both
deliberately generous, since the app's own files sit at 4.5 kB/s — and
`worker.ts` hands that one number to all three things that trusted the raw
field: the meter, the hallucination ceiling and the token budget. There is no
longer a way to charge one duration while budgeting another.

Hardened the next day, because the field is typed and not checked: a string,
an object or a NaN all arrive wearing `number | undefined`, and every one of
them used to propagate through the clamp and come back NaN — NaN is falsy, so
`looksHallucinated` opened with `if (!seconds …) return false` and the guard
against an invented memory turned off silently for anyone sending `{"seconds":
"90"}`. Anything that is not a finite number is now an absent claim, which the
clamp already knows how to price.

**It is a bound and not a measurement**, and that difference is the honest part:
knowing the real duration means decoding the audio, which this Worker will not
do. An omitted `seconds` on ninety seconds of speech is charged about ten
seconds rather than nothing, so what is left is a discount and not a free pass.
`transcribe-budget-check.mjs` covers the omitted, zero, string and NaN paths
beside the arithmetic.

Two devices calling at the same time can overshoot the limit slightly. That is
acceptable: the alternative is locking, which would cost more than a few extra
seconds of speech.

When the limit is reached, **transcription** of a dictation is blocked but
typing is not — otherwise the paywall would block telling, which violates rule 2.
`/extract` is deliberately unmetered: it is text, it costs a fraction of a cent,
and limiting it would prevent a typed memory from being saved at all.

**A quota never rejects a recording.** If the minutes are gone, the audio is
saved anyway and transcription waits — `Memory.isAwaitingTranscription`. The
audio is irreplaceable and the transcription is replaceable: it is done when the
minutes reset or the family goes paid. The same applies to a network error. What
does the doing, and what it cost that nothing did for a while, is **§16**.

The check uses the amount already consumed rather than consumed + incoming: a
recording that has started is not cut off because it happened to be long. The
limit is exceeded slightly, and that is cheaper than a rejected memory.

### Moderation

`report` and `block` are in the schema because Apple's rule 1.2 requires them of
an app containing user content. The implementation is small:

- A memory can be reported (a row in `report`)
- A member can be blocked, hiding their memories from the blocker
- The family owner can remove a member — **built 5 Sep 2026** (§4,
  `DELETE /family/member`), not as moderation but as the only remedy for an
  invitation that reached the wrong person. The other two stay out

**This is a family's private channel, though, not a public network.** The real
abuse risk is small and the solution matches: no notification centre and no
moderation queue, only the required minimum. If the release is never made, this
can be cut entirely (PLAN.md §5, item 6).

### What is checked, and what is not

`scripts/quota-check.mjs` presses on the counting against a running Worker: a new
family starts at nothing, three photographs count as three, **a deleted one gives
its slot back** — the count is derived from the table rather than kept beside it,
which is the reason that works — a spent month is reported as spent, paying takes
the ceiling away, and what was used stays counted after it does.

The one that matters most is the one nobody had ever checked: **with the month's
minutes gone, a typed memory still syncs.** Rule 2 in one assertion. The minutes
are put where they need to be with a direct D1 write rather than by spending
them, because buying a real quota failure would cost ten minutes of
transcription and prove the same thing.

**Not checked:** the transcription path itself. `checkAISeconds` is called by
`/transcribe`, which calls OpenRouter and costs money on every run, so nothing
here exercises the refusal in place — what is exercised is the counter it reads
and the promise it must not break.

**And an edge worth naming rather than fixing quietly.** A family whose
subscription lapses mid-month keeps the minutes it spent while paying, so it can
be over the free limit the moment it lands there. Rule 2 still holds — the audio
is kept, typing works, nothing is refused that was ever promised — but the first
free month is short, and that is a decision about money rather than a defect.

## 8. The screens

Built, in the order they were built:

1. **Onboarding** — two options: "Start the family archive" or "Join with a
   link". Nothing else. One screen.

   The form behind the first one asks three things — who it is between, the
   name, and, last and not about the family at all: **whose phone is this.** Setting up takes a grandchild a
   few minutes; the using is done for years by somebody who has never opened
   iOS Settings and will not be told to, and the answer sets the smallest text
   the app will draw (`Elder.textFloor`, a floor and never a ceiling — iOS's
   own size still wins above it). It is changeable afterwards in Settings,
   because a phone can be handed over later than it was set up, or handed back.

   The pairing that bought it: the *family name* field is gone. It was
   optional, its own footer promised the name could be "decided later", and
   nothing in the app renames a family — the server's `'Perhe'` default fills
   it in, and it is read in one place.

   Nothing had ever audited either form. Blank, they measured six accessibility
   issues each: `Form` styles its own headers and footers below the contrast
   minimum, exactly as `List` does, and the disabled primary button is drawn
   grey on grey. The button is no longer disabled — it says what is still
   missing instead, the same trade as the refused microphone in §9 below.
2. **Family** — members, sharing the invite link, usage.

   **The screen nothing could measure.** Every row on it is drawn from what the
   Worker sends, so a device without a backend reaches the offline note instead
   — which meant no test and no screenshot run had ever rendered the invite
   rows, and a button on one of them was renamed (§21) without anything
   drawing it once. `-seed family` (DEBUG) gives `Session` a canned family
   with no network: three members, two open invitations — one made out to a
   name, one not — and a part-spent free quota. Same hole as `-mic denied` and
   `-screen result`, same shape of answer.

   The first audit that reached it found three defects, and the worst was the
   sentence that carries §4's whole security boundary: *"kuka tahansa linkin
   saanut näkee perheen kaikki muistot"*, drawn as a `List` footer — the
   framework's grey at about 4.2:1, capped so it could not grow with Dynamic
   Type at all, its last line under the floating tab bar with nothing left to
   scroll. It is an ordinary row now. The member icon was reading its own SF
   Symbol name aloud in English, and the list has bottom room for the bar.
3. **Audio playback** — the memory card's "Listen in her own voice". Emotionally
   the product's strongest detail and small to implement.

   It answered both of its failures with nothing at all: audio that could not be
   fetched from R2 returned early, a file that would not open was caught and
   swallowed, and either way the tap changed nothing on screen. On the control
   that plays a dead person's voice, "nothing happened" is indistinguishable
   from a phone on silent or a finger that missed — so the button says it now,
   in its own label and in two different sentences, because one is worth
   retrying and the other never will be.
4. **Open questions** — surfaced on the Tell screen rather than in a view of
   their own. This is the retention engine: an open question is a reason to come
   back, and it is also an easier start than a blank button.
5. **Relationships** — "add parent / spouse / sibling" from the person card. An
   unconfirmed relationship shows as a proposal.

   **And a friend, since 21 Sep 2026.** `friend_of` is a fourth kind on the
   same table and the same card, symmetric like a marriage and never proposed
   by the extraction, so it is always something a person entered. It is not
   kinship — `RelationKind.kinship` is what the tree and the *Suku* list read
   — so the card lists a friend under *Ystävät* rather than under *Suku*, the
   row that adds one still says *Lisää sukulainen* and its sheet offers *Lisää
   ystävä* after a gap, the export writes them a line of their own, and the tree draws
   somebody joined to the family by friendship alone apart, on a band above
   the people related to nobody (`FamilyTreeLayout.aside`) and with no line:
   a friend is not a generation, and a line to one would read as descent. A
   friend who is also somebody's kin is placed by the kinship. It cost the
   Worker nothing — `sync.ts` checks that a kind is non-empty and no more —
   and the phone one thing first: a build that met the kind before it knew it
   dropped the row silently and moved its cursor past it, which is what §3's
   `sync.kindsKnown` closes. The row on the card looks the relationship up
   by kind and direction now rather than taking the first live line between
   the two, because one person can be a sister and a friend.

   **And a face, since 21 Sep 2026.** The card's first row is the disc the
   list and the tree draw for this person, with *Valitse kasvot* beside it:
   a photograph of the archive and a spot in it, chosen by tapping the face,
   and cut on every phone from its own copy of the picture rather than sent
   anywhere. §25 has the flow, the four columns and what the Worker refuses.
6. **Paywall** — RevenueCat's own, not a hand-built one: it is configured
   remotely, so prices and wording change without shipping a build. Every way in
   only exists when a RevenueCat key is configured — a dead button is worse than
   no button, and `paywallSheet(isPresented:)` returns the view unchanged
   without one, so today there are zero buttons rather than broken ones. The
   primary way in is the moment a memory finishes, where perceived value peaks;
   the second is the family view, so a grandchild looking at the limits does not
   have to go and dictate something to find it.

   **It is no longer two.** Corrected 9 Sep 2026: the entry points grew with the
   quota notes on Muistot, each of which acquired a button of its own, and the
   deferred telling has one too. Rather than a count that goes stale — it moved
   between two readings of this file on the same day, while another session was
   editing `GalleryScreen.swift` — the way to know is
   `grep -rn "\.paywallSheet(" ios/Kinlore/Screens/`. What matters is the shape
   the count keeps: three of them are quota walls reached from the two things
   `quota.ts` meters, and only the rhythm-gated card is an offer. None of them
   is on the path of telling something, which is rule 2 in the layout.
   **Closing the paywall is not the end of the purchase**: `syncPurchase` is
   what turns one person's subscription into the family's entitlement (§6).

7. **Settings** — export, leaving the family, emptying the device. Written out
   in §14; moderation, which this list once expected to sit beside them, is
   formally out.
8. **Places** — a *"Paikat"* section on Muistot, and the section that should
   have existed from the first day the extraction could produce a place.

   `subject.kind` has covered photo, person, place and event from the beginning,
   and three of the four were listed somewhere. A place was created when a
   memory named one, synced, counted in the export and given its own starter
   questions — and **no screen listed it**, so its card could not be opened at
   all. Nothing failed; it was simply unreachable, which is the failure mode a
   single table invites and the one worth naming here. A row nobody can reach is
   not part of the archive.

   Most places have nothing on them, because a place is usually named *inside* a
   memory rather than being the memory. That is why the row says *"Kerro tästä"*
   rather than *"0 muistoa"* — the same invitation an empty person card carries,
   for the same reason (§6.5 of PLAN.md).

   The pairing required by "every addition requires a removal" (CLAUDE.md): the
   event-only row is gone. Moments and places are listed by one row that takes
   its icon from `kind`, which is what the `subject` design claims and what a
   second row type would have quietly started to contradict.

9. **The camera** — *"Kuvaa vanha valokuva"*, and the way the archive is
   actually filled.

   Until 29 Aug 2026 the only import was `PhotosPicker`, which reads the
   phone's own library — and an 80-year-old's photographs are not in iCloud,
   they are in an album on a shelf. The premise of the whole product had no
   door.

   **One decision shapes the screen: the shutter does not close.** After a shot
   the camera stays where it is and the line under it becomes *"Tallennettu.
   Kuvaa seuraava."* An album is thirty photographs and the person taking them
   is a grandchild in one sitting; returning to the gallery after each one is
   thirty round trips and the point at which the job is abandoned half-done.
   That is why this is `AVCaptureSession` and not `UIImagePickerController`,
   whose camera dismisses itself on every "Use Photo".

   No cropping, no deskewing, no correction — each is its own swamp and none is
   needed to remember a face. The row a photographed photo makes is the row a
   picked one makes.

   Nothing is drawn over the preview: text on a live camera image has no
   contrast to measure. The preview takes the top and every word sits on solid
   ground below it, which is the same shape the rest of the app uses — what has
   to be readable is pinned and the picture takes what is left.

   Three states, all audited: capturing, the refused camera (a screen that
   opens Settings itself and offers the library beside it, §8.9's trade), and a
   device with no camera at all — which is not hypothetical, it is every
   simulator, and it is what `SilentFailureTests` checks without forcing
   anything.

   Muistot' empty state stopped being a `ContentUnavailableView` with it. That
   view caps how far its own text grows, which is why `AccessibilityPolicy`
   exempts its labels by name — and the exemption came with the instruction to
   stop using the view rather than widen the list if it ever stopped being good
   enough. It did: the screen needs two ways in with the camera first, and a
   `Button` in that view's action slot fails the Dynamic Type audit in every
   shape it can be written in. The three strings that screen owns came off the
   exemption list with it, and now grow like every other sentence in the app.
10. **The refused microphone** — a screen of its own rather than a message.

   It had been a `failed` state whose text read *"Salli mikrofoni asetuksista"*
   and whose only button retried the same refused permission, for ever. The
   instruction is also the one this audience is least able to follow: four taps
   into a settings tree, in a list of apps, under a switch.

   So the screen opens that place itself, and offers the keyboard beside it —
   which needs no permission from anybody, and produces the same kind of memory
   through the same extraction. Rule 2 says telling is never paywalled; a
   microphone the phone refuses must not become the thing that blocks it either.

   Reachable in a test run through `-mic denied` (docs/SETUP.md), because the
   real way in is answering a system prompt with "Älä salli" and then digging
   the app back out of iOS Settings by hand — which is why nothing had ever
   looked at this screen, and why the audit had never measured it.

11. **"Näin tämä toimii"** — the help page, behind the gear.

    The app explains each step where the step happens, which is the right order
    and was the whole of it. Three things are true of the app rather than of any
    screen, and one of them a person cannot discover by using it at all: **the
    recording leaves the phone.** It goes to our Worker, which sends it on to be
    turned into text. Nothing anywhere said so — the microphone prompt talked
    only about keeping the voice for the family, and it says both things now.

    The other two are what somebody asks before trusting an app with their
    family: who can see this, and can I get it back out. Nine short sections, no
    disclosure triangles — a person who opened a help page is already looking
    for the answer, and making them hunt twice is how help becomes decoration.

12. **Search**, on Muistot and Ihmiset.

    It searches **what was told**, not only titles. A photograph has no title
    until somebody says something about it, so a search over titles would find
    least on exactly the archive that most needs finding — and what a person is
    looking for is "the one about the cottage", never a name nobody gave it. One
    query runs over the subject's own title and the text of every memory on it,
    in `MemoryStore.subjects(of:matching:)`, so both screens ask the same
    question of the same rule.

    **And over who and where those memories name**, since 6 Sep 2026. The
    words are what was heard; the mentions are what the family made of them —
    a name corrected on its card (§17), two cards merged into one — and the
    search read only the words: a photograph whose telling was about
    grandmother, corrected from "Aino" to "Kaarina" the day after, was still
    found by the wrong name and never by the right one (founder's-eye review,
    finding #5). A mention resolves through `subject(id:)`, which follows a
    merge to its survivor and answers nothing for a rejected proposal, so a
    name the family refused finds nothing. The fixture's telling on the
    photograph names Puumala without saying the word, which is the only way
    the rule can be tested apart from the words.

    **And since 19 Sep 2026 the album lists the tellings themselves.** The
    search answered with cards: a tile found by a word inside its story looked
    exactly like a tile found by its title, and the sentence that matched was
    on the card two taps away — and a memory told about a *person* lives on
    her card on Ihmiset, so from the album it could not be found at all. A
    *"Muistot"* section now stands first in a search, one row per telling: the
    words first, cut in the string the way an untitled moment's row cuts them
    and not by the frame; the card's name with its kind's symbol under them;
    and who told it, by `byline(for:)`. `MemoryStore.memories(matching:)`
    matches the words, the mentions, the card's title and the teller, and
    resolves the card through `subject(id:)` like the rest, so a merged card
    answers with its survivor and a rejected one is not listed; a telling not
    yet transcribed has no words to match. Every kind of card leads where the
    album already goes, a person's included. The rows exist only inside a
    search — nothing changes for somebody who is not searching, and a
    grandparent's phone has no field to search from. `SearchTests` reads the
    row by its words at both text sizes and audits it, and finds Eeva's one
    sentence from the album without her name in it.

    Out of the way by design — and on Albumi, since 19 Sep 2026, by a rule
    rather than by trust in the platform. The bargain was that `.searchable`
    keeps the field above the list until somebody pulls down, so the grandchild
    looking for one name in forty finds it and grandmother never meets it.
    iOS 26 broke the second half: it draws the field under the large title on
    every arrival, and measured at the text floor on `-seed film-week` the
    first thing on her album was a box saying *"Etsi"*, above her own
    photographs, with a keyboard one tap away. So `GalleryScreen` hangs
    `.searchable` on the archive only when `elder.largerText` is off — the
    same whose-phone signal that puts the blind card on Albumi (§23) and the
    tree behind the people list (`PeopleTab` in `RootView.swift`). A reader's
    phone keeps the search, a grandparent's never had a use for it, and
    `SearchTests` runs on the reader's. Ihmiset still carries its field on
    every phone. A fruitless search gets its own dead end rather than the
    empty archive's invitation — offering *"lisää kuvia"* to somebody who
    searched for a word answers a question nobody asked.

    **A round is not a search result.** The waiting guessing round kept the
    gallery out of its empty state, which is right when the archive is empty and
    wrong the moment somebody is searching: the first version of this showed a
    blank screen for a search that matched nothing. The test that caught it is
    `SearchTests`, on the second run.

    The round has since been cut (§13), so the thing that used to hide this is
    gone — but the dead end it forced into existence is not, and neither is the
    test. Kept as it happened rather than rewritten as though the search had
    always known better: the reason this dead end exists is that something else
    was standing in front of the bug.

    The pairing "every addition requires a removal" asks for is **not paid**.
    Nothing was removed for this one; it is an addition, and the decision to
    take it was made deliberately rather than by forgetting the rule.
    The rows of tellings are an addition too, inside a state only a reader
    who is already searching ever enters.

13. **A date by hand**, on a photograph or a moment.

    The three date columns have been in the schema from the first day and rule 5
    — uncertainty is stored, never rounded — is one of the things this app rests
    on. Only the extraction could ever write them, so a granddaughter who knows
    the summer was 1957, looking at a photograph the model heard no year for, had
    nowhere to put what she knew.

    The screen asks **how sure you are before it asks what you know**: a decade,
    a year, or "en tiedä" which clears it. Choosing is answering — tapping a
    decade stores it and closes the sheet, the pattern `RelationPicker` already
    uses — so there is no save button to keep on screen while a hundred rows
    scroll past. People and places are left out: `dateHint` means "when this
    happened", and a person's date would have to mean birth or death, which the
    column does not say and the app must not guess.

    Three things were built and taken out again, each by measurement rather than
    taste, and they are worth more than the feature:

    - **A wheel picker.** Its text does not grow with Dynamic Type. On an app
      built around rule 1 that is a defect and not a tool's opinion.
    - **An exact-day answer.** The only controls iOS offers are that wheel and a
      graphical calendar; the calendar audited at three findings on its own. A
      control this user cannot read is not a capability. Extraction still writes
      `.day` when somebody says a date out loud, and the sheet shows it as its
      year rather than pretending it is not there.
    - **A pinned bar** holding the actions. Content scrolls under it, and the
      audit read a year dimmed to below the contrast minimum — the same fade the
      system's bars are forgiven for, except this one was mine to not build.
    - **A `Label` for the date row** on the photo's card. The audit called its
      text clipped in every shape it was tried in — as a button's label, as a
      plain row, with the tap target on the label, with the tap target on the
      button, with an explicit Dynamic Type font, with `fixedSize` — and it
      pushed a second finding onto the memory underneath, so the symptom
      followed the layout rather than the words. The same row built from a
      `Text` and an `Image` in an `HStack` passes at both sizes. Four runs for
      one fact, and it is written down so the fifth is not needed.

    **And once for a whole import.** Thirty scanned photographs are almost
    always one album and one era, and asking thirty times is asking nobody: the
    import offers the same sheet once for everything it just brought in. Two or
    more only — a single photograph is opened and looked at, and its own card
    already carries the row. It is offered rather than imposed: the photos are
    in the archive before the sheet appears, and swiping it away leaves them
    exactly as an import used to leave them.

    `MemoryStore.setDateHint` **overwrites**, unlike `describe` beside it, and
    the difference is the point: `describe` speaks for the extraction and a
    machine's guess must not walk over a person's knowledge. This one is the
    person.

    **And since 6 Sep 2026 the date sorts something.** Until then it reached
    the card and nothing else: every browse query ordered by `createdAt`, so
    the grid stood in the order the album happened to be scanned, and "show
    me the fifties" had no answer on the one screen built for finding
    (founder's-eye review, finding #10). The grid now groups dated
    photographs by decade, oldest decade first and oldest first within it,
    and the ones nobody has dated follow under *"Ilman ajankohtaa"*, newest
    scanned first as before; a grid with no dates in it is exactly as it
    was, because a heading over the whole archive saying nobody has dated it
    would be a reproach. The moments list orders the same way. The decade is
    interpolated as a `String`: an integer in a `Text` is formatted for the
    locale, and Finnish groups thousands, so the heading read *"1 950-luku"*
    and the test looking for *"1950-luku"* found nothing. `-seed dated` is
    the one archive with a date in it, for the sweep; the plain one stays
    undated so DateTests can give one and then find the heading.

    The row under it says when the telling was made — *"Mummo · 5.9.2026"*
    in the device's own short form — which the export had printed beside
    every telling from the first day and the card never had (finding #9). And
    the first sweep to put untold photographs with real pictures on the grid
    found the tile's *"Kerro"* badge failing contrast on all three: a frosted
    capsule takes its colour from the photograph under it. It is opaque now.

    **And a name by hand**, since 6 Sep 2026: *"Anna kuvalle nimi"* on the
    photograph's card beside the date row, *"Vaihda nimi"* on a moment's, the
    same `NameSheet` the Perhe screen's pencil opens for one's own name.
    `MemoryStore.setTitle` overwrites, as `setDateHint` does and for the same
    reason: this is the person, not the extraction. The card could date the
    picture and not name it; the title was whatever the first telling left.

    **And a person by hand**, since 13 Sep 2026: *"Lisää henkilö"* in its own
    corner at the top of Ihmiset, and *"Joku uusi"* at the top of
    the picker behind *"Lisää sukulainen"*, all through the same `NameSheet`.
    It stood beneath the empty state as well until 16 Sep 2026, where whoever
    sets the archive up meets it first — and that is exactly who lost it: the
    first person added emptied that screen, and the button was suddenly at the
    top of a list the person had never looked at. A button that is easy to find
    once and gone afterwards is worse than one place that never moves, so the
    empty state's last sentence points at the toolbar instead.

    **And the toolbar was not one place either**, which the test written for
    that fix then measured: beside the gear the button moved 90 pt left
    (x 218 → x 128) on the same first person, because the tree/list switch
    joins that trailing group as soon as there is somebody to draw. It sits on
    the leading side now, alone, where nothing conditional can push it.
    `AddPersonTests.testTheWayToAddAPersonIsInOnePlaceBeforeAndAfter` compares
    the frame either side of the first person rather than only asserting the
    button exists.
    Until then a person could only be born out of a telling. That is the right
    order for the person talking and the wrong one for whoever sets the archive
    up, who knows the family's shape before anybody has said a word — and the
    blind card needs three names before it can ask anything.
    `MemoryStore.addPerson` confirms what it creates, because the person who
    typed the name vouches for it, which is what rule 4 asks; and a name the
    family already has is the same card, so typing a heard *Aino* confirms her
    rather than making a second one.

    **The tile reads its name.** A photograph has inherited a title from its
    first telling since 15 Aug 2026 — the place and the time that were said,
    `Extraction.suggestedTitle`, filled only into an empty field — and the
    tile never read it out: thirty tiles were thirty *"Valokuva"* to
    VoiceOver, and to an English phone as well, because `displayTitle`'s
    fallback was a bare `String` (finding #12; CLAUDE.md, Language). The label
    is *"Mökin ranta, 2 muistoa"* now and *"Valokuva, …"* only when there is no
    name. What was not built is a title from the names or the words in a
    telling with no place or time in it: a person's name there is usually an
    unconfirmed proposal, and a proposal on a tile is rule 4 inverted; and
    nothing renames a photograph yet, so a wrong caption would be for keeps.

Cut from v1, and then built after all:

13. ~~**Family tree** — a drawn graph. **A trap.**~~ **Built on 13 Sep 2026**,
   on a family member's phone only, **and rebuilt from zero on 25 Sep 2026.**
   Relationships stay lists on the person card — the same information, at the
   largest text size and aloud with VoiceOver — and those lists are all a
   grandparent's phone and VoiceOver get. What made the drawing a trap was her
   phone, so the drawing is where her phone does not go: what Ihmiset opens
   on, with the list one tap away through its menu — `FamilyTreeView` over
   `FamilyTreeLayout` and `Kinship`, confirmed people and confirmed
   relationships only (rule 4). Everybody confirmed is in the picture, the
   family's friends on a band of their own under the generations (item 5) and
   the people related to nobody under them, and a person tapped in it takes a
   new relative, or a friend, through the card's own `RelationPicker`, so the
   tree grows where it is looked at.

   **Why from zero.** The first shape (13–21 Sep 2026) explained its rows with
   a rail down the window's left edge — *Vanhempiesi polvi*, *Sinun polvesi*,
   *3 polvea ylempänä* — pinned to the window over a drawing that moved under
   it. On the iPhone 17 Pro simulator it was measured and passed every sweep;
   on an iPhone 13 mini it was used, and the rail took 156 of the phone's 375
   points, so the words stood over the names in any family wider than what
   was left, which at 132 points a place is a family of three. A word pinned
   to the window cannot be kept apart from a drawing that moves under it on a
   phone that narrow, so the question was not where to put the rail but
   whether anything may be pinned at all. Nothing is. Every word on the
   screen is inside the drawing, moves with it and scales with it, and what
   the rail said about a row each card now says about itself. The placement
   engine went with the screen: its rows were the rail's unit, a generation
   counted from the reader, and the screen needs a family's rows and a
   reader's words — which is what the assessment of 25 Sep 2026 (section 05
   of the 16 Sep artifact) chose over repairing the rail.

   **One word under every card**, said from whoever holds the phone
   (`member.person_subject_id`, §4): *Vanhempasi*, *Isovanhempasi*,
   *Lapsesi*, *Puolisosi*, *Sisaruksesi*, *Serkkusi*, *Pikkuserkkusi*,
   *Sisaruksesi puoliso*, *Puolisosi vanhempi* — twenty-two in all, in
   `Kinship.Word` — and *Sinä* on your own card.
   `Kinship.words(from:people:ties:)` walks the confirmed relationships from
   your card, finds the shortest path to each person, and matches every path
   of that length against a table of paths in the table's order; a person
   none of whose shortest paths is in the table gets no word, and no longer
   path is tried. That is rule 4 for words. *Serkkusi* on a card looks
   exactly like *Pikkuserkkusi* to anybody who does not already know, so a
   near word is the wrong relationship drawn as fact, and a card with none
   says only that the app is not sure. Gender-neutral by construction in
   both languages — *Vanhempasi*, never *Äitisi* — because the archive stores
   no gender (§2). A word reaches the screen as a `String`, so `Word.label`
   is `String(localized:)` and both tables carry all twenty-two (CLAUDE.md,
   Language). A friend's word is the whole one-step path from you and
   nothing longer: *Ystäväsi* names Jonne, and nobody is reached through him.
   A cousin who is also a friend reads *Ystäväsi*, the shorter of two true
   words. And the words are read from the bonds the drawing keeps: a parent
   bond entered the other way round after its reverse is left out, as the
   layout leaves it undrawn, so from Sulo's phone Onni — drawn as his
   child — reads *Lapsesi*, where an engine handed both bonds matched upward
   before downward and called him *Vanhempasi*.

   **Captions inside the drawing.** *Ystävät* and *Ei vielä sukupuussa* stand
   on the caption rows the layout leaves empty above each band, drawn
   `captionBand` tall — 44 points at the default size — rather than a
   generation tall. When the archive holds families that share nobody,
   *Toinen perhe* stands over every family but the first in a band across
   the top, and it says why their cards carry no word: every family starts
   at row 0, and nothing is known about the second one's age either way.
   Each wraps at the window's width, measured from the canvas and handed
   in with the drawing: a name stops at its place's edge and a caption has
   no edge to stop at, and *Ei vielä sukupuussa* at the largest text size
   ran 461 points across a window of 402 before it did (25 Sep 2026). A
   band of `Elder.card` shades every other generation of each family, counted
   from your own row in yours so that yours is always a shaded one, so a row
   reads as one row across a family too wide to see at once. Card on paper is
   1.11:1, a tint and not an edge; the names measure 16.81:1 on it against
   15.17:1 on paper, so no name gets harder to read for being in a shaded
   generation.

   **The drawing is a map**: a `UIScrollView` whose zooming view is the SwiftUI
   drawing. It moves in both directions under one finger and grows about two
   fingers between 0.4× and 2.5×, and when the pinch ends the drawing is laid
   out again at the new scale, so the text is rendered at its size rather
   than stretched. The pinch is a recognizer of our own on the scroll view
   (`TreePinch`), because the scroll view's own never fires here: SwiftUI's
   responder recognizer on the hosted drawing recognises on the first touch
   and prevents every other recognizer in the chain, so a pinch that began
   on two cards — where the fingers land more often than not — was two
   taps, a sheet and no zoom. Measured 25 Sep 2026, with the built-in
   recognizer holding two touches at the first event and none from the first
   move. `TreePinch` refuses to be prevented, and a gate keeps the presses
   that ran through it from being taps
   (`testTheTreeZoomsUnderTwoFingersAndKeepsItsPeople` asserts both the
   growth and the absence of a sheet). Two buttons take the place of the magnifiers a hand that
   cannot pinch used to get. They are paper capsules with a hairline rather
   than the system's bordered style, which is glass on iOS 26, and the
   drawing stops at the tab bar instead of running under it: the audit's
   contrast check reads a text element's pixels into a set of colours one by
   one, and text on glass or under it at the largest size is more colours
   than the check's fifteen seconds hold — measured 25 Sep 2026 in a sample
   of testmanagerd, and the reason `testFamilyTreeAtSize` timed out on every
   run until then (the header of `AccessibilitySweepTests.swift`). The
   buttons sit 24 points above the bar rather than 8, because XCUITest's
   zoom-out pinch begins its second finger nine points inside the element's
   bottom-right corner — under the bar and beside the tabs while the drawing
   ran under it, on the *Sinä* button once it stopped — and a button takes
   the finger: the recognizer saw one touch, the scroll view panned, and
   `testTheTreeZoomsUnderTwoFingersAndKeepsItsPeople` said a name was still
   drawn at the smallest zoom, alone, on the first run inside the bars.
   *Koko suku* fits the whole family in the window,
   never above 1×; *Sinä* flies to your own card at 1×, into the upper part of
   the window — the card's centre at half the width and three tenths of the
   height, so that your parents are above it and your children below. A tap
   on a person flies the same way at 1× or the current scale if it is
   larger, and their sheet comes up with the word, how many memories the
   archive holds about them when it holds any — the count the person list
   shows, and the map plan's *2 muistoa* on a chip — *Avaa kortti* and the
   five ways to add a relative. The sheet is the window's full height, and
   the medium detent that would have kept the card in view over it is
   gone: iOS 26 lays a half-height sheet's content out at the window's
   width and draws it at the sheet's — 402 laid out, 386 drawn, every frame
   a multiple of a 67th — so every line in it is 4 % smaller than the size
   the reader asked for, and the audit reported each one clipped at both
   text sizes, twice alone on 25 Sep 2026, and nothing once the detent went.
   When the sheet goes, the person is where the flight left them, with their
   name. The flight is 420 milliseconds ease-in-out, and none under Reduce
   Motion. **Below 0.65× the
   names, the words and the captions are not drawn at all** — a name at the
   smallest zoom would be 6.8 points of ink in the shape of a word — and the
   discs stay, each still a tap target of `Elder.minTapTarget` on the screen
   whatever the scale. A tap at that size flies to the person at 1× with
   their name back, so the pinch is optional and *Koko suku* is a picture of
   the family's shape.

   **Where the picture begins.** At its natural size and never smaller:
   centred, when the whole family fits the window; on your own card when it
   does not; and at its own top left corner, like any picture, on a phone
   linked to no card. The first draft of this opening fitted a family that
   fit at a scale that still had names, and the audit is what refused it —
   the same way it refused the rail's shrinking names on 19 Sep. Its
   default-size run steps the text through twelve sizes, the drawing was
   fitted again at each, and at the sizes where the family nearly fit it was
   shrunk to fit: every name on the screen reported clipped, twice alone on
   25 Sep 2026. The reader may shrink this drawing and the app may not do
   it for them; *Koko suku* is the same fit, and the reader's to press. The
   opening is taken again whenever the
   window's size or its insets change, until the reader has moved the
   drawing — which is what the accessibility audit needs, because its screen
   is laid out once with the tab bar and once without, and the first shape
   opened against the wrong one. Two measurements it waits for: the bars'
   insets are read from the scroll view's own `safeAreaInsets` with
   `contentInsetAdjustmentBehavior = .never`, and the two buttons' band is
   measured with `onGeometryChange` into `controlsHeight`, and no opening is
   taken before it is known, because an opening taken against a window
   without the band is moved when the band arrives, and a name under a
   button is one the audit reads as paper on paper
   (`testTheTreeOpensWithNothingUnderItsButtons`, at both text sizes).

   **What is deliberately not there.** No `accessibilityZoomAction`: VoiceOver
   never reaches this screen, because `PeopleTab.showsTree` sends it to the
   list, so a zoom action here would be code nothing can run. No zoom
   buttons: fit, home and closer are the two named buttons and a tap on a
   person. No word for a relationship the table does not name — a
   great-great-grandparent, a parent's cousin's wife, a second cousin's
   daughter — because Finnish has no word anybody says for most of them, and
   an approximation is the failure rule 4 is about.

   **Where everybody lands is `FamilyTreeLayout`**, rewritten with the screen,
   and `scripts/family-tree-layout-check.swift` with it. Nine requirements,
   each a way of being wrong that draws just as well: everybody placed once, a
   place apart, the leftmost at zero; generations as rows, per family, every
   family starting at row 0 and drawn side by side, yours first and the rest
   by their earliest card; an
   earlier relationship winning over a later one that contradicts it, the
   loser returned in `undrawn` for the menu to name rather than dropped, and
   an exact or reversed duplicate dropped in silence; a couple adjacent,
   somebody twice married between the first two spouses, and a couple's line
   dipping round a third person rather than running through them; a bracket
   from a couple's union to their children at a hang dealt so that two broods'
   bars never share a height where they overlap, with the children contiguous
   and centred; a bar at `row − 0.4` over siblings who share no entered
   parent; the
   same picture whatever order the family was entered in; the friends' band
   and then the loose row under the families, an empty caption row over each,
   wrapped at the drawing's width; and fast, because it runs on every change.
   `scripts/family-tree-layout-check.swift` drives them over the clan — six
   generations with the root on the fifth, Aapo between Hilma and Lyyli with
   each marriage's children hung from its own midpoint, Impi and Urho a
   couple with nobody under them, Sulo's one child under his own name, Oiva
   and Eemeli on a sibling bar, Rauha among her kin and Jonne on the friends'
   band, the loose seven on one row, the bands on rows 7 and 9 with their
   captions on 6 and 8 — then the same clan with every symmetric link turned
   round and shuffled twenty times, and the cases the clan has no room for:
   a person married three times, a couple's line dipping under the root's
   own card with the child's stem starting on the dip, contradictions
   undrawn once in input order, repeats dropped in silence, a link to nobody
   known ignored, siblings with and without parents entered, unmarried
   parents and three parents each with a stem under their own name, children
   centred, the bands wrapped at a family two wide. Then 5 000 seeded random
   families — 121 938 links between them — with the eight invariants derived
   from the input again and audited on every one, 4 548 of them re-run with
   their links reversed or shuffled and the picture compared, and the cost:
   the clan's 55 people laid out in half a millisecond and the whole check
   in about two seconds, unoptimised, as `verify.sh` compiles it. One thing
   the check excuses rather than asserts, and proves before it excuses:
   where the couples rule cannot hold at all — somebody entered as the
   neighbour of three people, or marriages that close a ring — the check
   shows it for that family, excuses exactly those claims and prints the
   reason, and every other claim in the same family is still asserted. Two
   named cases pin the proof; none of the 5 000 needed it, and 2 of the
   20 000 the sample was cut from did.

   **Which word each card gets is `Kinship`**, and
   `scripts/kinship-check.swift` derives it rather than asserting it: every
   card of `-seed clan` from Elina's phone against the words worked out by
   hand from the fixture, the same from seven other phones and from Sulo's
   for the contradiction, then 600 seeded random families and a thousand
   random tangles of ties against a reference that walks every shortest
   path by brute force — under three seconds unoptimised, the engine itself
   some sixty microseconds a phone. Its one concession is the mirror. A
   word is required to mirror its reverse — *Vanhempasi* one way, *Lapsesi*
   the other — only where the pair has a single shortest reading, because
   two siblings married to two siblings are *Sisaruksesi puoliso* from both
   ends and no order of the table can make them differ: 616 such pairs
   among 2 164 ambiguous ones on the last run, every one of them that
   exchange. Broken on purpose in twenty ways — two table rows swapped, a
   longer path accepted, a path continued through a friend, half-siblings
   lost, a neighbouring key under a word — the engine failed the check in
   seventeen; the three it did not catch cannot change an answer.

   **What the tests hold.** `FamilyTreeTests` asks over a family of three
   whether the screen works: Ihmiset opens on the tree with everybody
   confirmed in it and nothing else on the screen, the list and every other
   door are in the menu, your card says *Sinä* and your husband's *Puolisosi*
   inside their own buttons and inside the scroll view, the picture zooms
   under two fingers and keeps its people as tap targets at the smallest
   size, a person's sheet says how many memories the archive holds about
   them and opens their card or takes a new relative on the spot, and a
   grandparent's phone keeps the list. `FamilyTreeCrowdTests` asks over
   `-seed clan` what only happens at size: the thirteen words Elina's family
   has, counted card by card against what the kinship check derives — two
   *Vanhempasi*, four *Isovanhempasi*, five *Isovanhempasi sisarus*, one
   *Ystäväsi* — and seventeen people who get none; nothing on a phone linked
   to no card; the words moving with the drawing under a flick; *Toinen
   perhe* over Otto and Helmi eight screens away; the opening on Elina with
   her parents above and her children below and nobody under the buttons at
   either text size; the discs alone at the smallest zoom, Aapo still a
   44-point target and his name back on a tap; *Sinä* flying home from the
   far end; a tapped card in the upper half of the window over its sheet; the
   legend and the two undrawn bonds in the menu; Onni reading *Lapsesi* from
   Sulo's phone, the way he is drawn; each caption a caption's height under
   what it follows; and a name larger at the largest text size
   than at the default. The sweeps *Sukupuu*, *Sukupuu, iso suku*, *Sukupuu,
   valikko* and *Sukupuu, henkilö* audit the four screens at both text sizes.

   **`-seed clan` is the fixture all of that is measured against**: six
   generations, 55 confirmed people, a second marriage and the half-siblings
   from it, a sibship of six, a childless couple, a child with one parent, two
   cousin marriages, a marriage the generations cannot hold, siblings with no
   parents entered, two families sharing nobody, a contradiction, a duplicate
   link, an unconfirmed person, a friend who is nobody's kin, a sister who is
   also a friend, and seven people related to nobody. Every defect the first
   shape found is one that five people cannot show. The two bonds the rows
   cannot hold — *Eemeli ja Sirkka — aviopuolisot*, *Onni ja Sulo — vanhempi
   ja lapsi* — are named in the menu under *Nämä eivät mahdu kuvaan* rather
   than dropped, because from the picture a dropped line is indistinguishable
   from a bond nobody has entered yet, which is the reading that sends
   somebody off to enter it a second time.

## 9. Build order

Pinned to the phases in PLAN.md §3.

| Phase | Contents |
|-------|----------|
| **C** (11–31 Aug) | Identity, family, invite link, the sync backbone. The `merged_into` fix before sync is built on top of it. |
| **D** (1–14 Sep) | Media to R2, RevenueCat, quotas, paywall. Craft and accessibility. |
| **E** (15–24 Sep) | Audio playback, open questions, relationships. Testing with a grandparent. Repo in English. |
| **F** (25–28 Sep) | Demo video, submission. |

### The critical path

Sync is the only thing that **blocks** others: media, quotas and moderation all
assume membership and a family. It has to work during phase C or the rest slips.

Everything else is parallel and cuttable.

### What gets cut first

The order in PLAN.md §5 still holds, and this plan sharpens its first item: **if
sync does not get finished, seed a demo family.**

The data model already supports multiple members (`memory.author_id`), so the
video can show several relatives' memories on the same photo even without a join
flow being built. The concept is visible, the implementation is incomplete — and
that is a more honest outcome than half-finished sync that loses data in the
demo.

## 10. The interview loop

Added after the inventory above: the follow-up questions the extraction
already produces are now asked aloud. One button on the result screen starts
the loop — the app reads out the question the ladder selected, in the voice of
whichever language is being spoken (`InterviewVoice` follows `SpokenLanguage`,
so an English phone gets its own English voice), starts recording when the
sentence ends, and the answer
runs through the same transcribe → extract → save pipeline as any other
memory, which yields the next question. Ninety seconds of telling becomes a
guided conversation, and no hand touches the screen until "Riittää tältä erää".

Decisions, in the order they were argued about:

- **Opt-in, not automatic.** A result screen that starts talking by itself
  would startle exactly the user this app is for, and the name-correction
  moment needs a calm screen more than the loop needs one saved tap.
- **Same pipeline, not a second one.** Each answer is an ordinary memory on
  the subject the first memory landed on, and the spoken question is marked
  answered by the same rule as any answered question. The loop wraps the magic
  moment; it does not reimplement it (the data-model rule in CLAUDE.md).
- **On-device TTS.** Works at a summer cottage without signal and sends
  nothing anywhere. The voice that matters in this app is grandmother's, not
  ours.
- **VoiceOver never competes.** When the screen reader runs, the app does not
  speak and does not auto-start the microphone — it would record the reader.
  The question takes accessibility focus, and the record button answers it.
- **Ending is cheap, and never eats a question.** Silence (a sub-second
  recording) ends the loop like the button does, and the question that was
  being asked stays open. Quota running out mid-loop ends the loop with the
  answer's audio safe, exactly as in a single dictation.

  The same invariant held only inside the loop until 23 Aug 2026: outside it,
  an answer abandoned on the way back to the idle screen — a discard, a
  sub-second recording, a cancelled typing — left the chosen question
  silently attached, and the next telling on that screen, about anything at
  all, marked it answered and taught the ladder at its level. Every return to
  idle now resets the question with the phase.

One knowingly open edge: every round adds three questions and answers one, so
a long interview grows the open-question list. That is today's behaviour for
every answered question, not something the loop introduced — if it starts to
hurt, the cap belongs in the store, not here. It went there on 25 Sep 2026:
one subject carries at most five open questions (§12).

The pairing required by "every addition requires a removal" (CLAUDE.md): the
drawn family-tree graph, already last in line in §8, is now formally out of
v1. The person-card lists carry the same information. It was built after all
on 13 Sep 2026 (§8, item 13), and the lists are still there.

## 11. Asked questions

The other half of the open-question loop. Extraction has always generated
questions; now a person can ask one too. "Kysy perheeltä" on a subject's card
files the question into the same `prompt_question` flow: it waits on the
family's Tell screen next to the machine's questions, and the answer comes
back as an ordinary structured memory on the subject.

What makes it different from an AI prompt is one field: the asker. "Ville
kysyy" above a question turns a prompt into a request from a person — the
strongest reason there is for an elderly user to press the button. The
questions the machine generates stay unattributed on purpose: pretending the
app is a person would be a lie in a warm font.

The rules are borrowed from the memory's author, verified with curl against
a local D1:

- The server accepts an asker only for the session's own member id. A client
  can claim itself or nobody — never another member. A spoofed id is nulled,
  not rejected: the question is still worth keeping.
- The display name is derived on read from `member.display_name`, so a
  renamed member is right everywhere at once.
- Authorship is sticky under sync: an older device re-pushing the same
  question without the field cannot strip the name off it.

### Asked of one person — 25 Sep 2026

`prompt_question.target_member` sat in the schema unused from the first day,
and on 25 Sep 2026 the ask sheet started setting it: *"Kenelle?"* offers
*"Koko perhe"* and the family's other members by name. What the aim narrows is
kept small on purpose:

- **Everyone still sees it.** The card shows every question to every member,
  with *"Kenelle: Aino"* under one asked of somebody else, and anyone who knows
  may answer it there. A question hidden from the rest of the family would be a
  private message, and this app has none.
- **Only the Kerro tab narrows.** `MemoryStore.openQuestions(…, viewer:)` puts
  a question asked of this phone's member first, oldest first, headed *"Mummo
  kysyy sinulta"*, and leaves out the ones asked of somebody else. The
  family-wide questions follow exactly as before.
- **The server keeps the asker's rules.** Only the asker aims, and only once: a
  target is bound only when `author_id` is the session's own member, and a
  re-push cannot move it (`COALESCE`, as for authorship). A target that is not
  a current member of this family is nulled by a subselect rather than refused,
  because D1 enforces foreign keys and a push is one transaction — one bad
  reference would otherwise fail every row of it, on every retry.
- **The answer is the latest one.** `answered_memory_id`, unused until then as
  well, records the newest telling that answered the question rather than the
  first: an answer taken back reopens the question (`MemoryStore.reopen`), and
  the telling that answers it next is the one the asker should be pointed to.

The name travels like the asker's: `target_name` is derived on read from
`member.display_name`, and the asking phone writes it locally so the line shows
before the first sync. **One edge is known and left:** a question asked of
somebody who has since left the family is offered on nobody's Kerro tab. It is
still on the card, where anyone can answer it.

§12 paid for a removal by keeping this column unused, and that removal is not
restored in its place. The addition has none beside it, by the user's decision
of 25 Sep 2026 — PLAN §5, row 11.

### Two notifications — 25 Sep 2026

Nothing rings a phone except these two: *"Mummo kysyi sinulta jotain."* to the
member a question is aimed at, and *"Kysymykseesi tuli vastaus."* to its asker.
Neither can say what was asked or told, and that is not a choice made in the
Worker: both texts are sealed on the phone (lever 3), so it has no words to put
in one. The asker's display name is the one thing a notification carries, and
it is plaintext on `member` already. The sentence is a `loc-key` looked up in
the phone's own `Localizable.strings`, so the Worker never needs to know which
language a phone speaks.

- **Who is told is `sync.ts`'s decision** (`noticesFor`). It reads each pushed
  question's state before and after the batch: a question that has just been
  aimed at somebody tells them, and a question a person asked that has just
  been answered tells its asker. Never the member who pushed, never about a
  machine's question, and a re-send tells nobody.
- **`apns.ts` only delivers**, after the reply and under `waitUntil`: an ES256
  provider token signed with WebCrypto from the Worker secret `APNS_KEY_P8`
  (beside `APNS_KEY_ID` and `APNS_TEAM_ID`), kept for fifty minutes per
  isolate, and sent to the endpoint each token belongs to. Nothing is retried
  and nothing can fail a sync — the question is on the card and in the Kerro
  tab either way. A token APNs calls dead (410, `BadDeviceToken`,
  `DeviceTokenNotForTopic`) is deleted. The log carries status, APNs's own
  reason and counts: never a token, never a name (rule 9).
- **`push_token`** is one row per phone, keyed by the token, so a phone that
  registers under a new identity moves its row rather than adding a second
  one. Leaving the family and being removed from it delete a member's rows,
  and the wipe in Settings asks the server to forget this phone's before the
  identity is renewed, best effort.
- **The phone never asks.** `PushNotifications` requests *provisional*
  authorization, which iOS grants without a dialog: notifications arrive
  quietly in Notification Center, and the first one offers to keep them or
  turn them off. A permission prompt on an elder's phone is the cost UX §6
  named when it put push in v1.1, and the rule since 25 Sep 2026 is not to pay
  it when a feature can work without one. A tap on a question asked of you
  opens Kerro; a tap on an answer opens Albumi.

**What is not verified yet, and why.** APNs speaks only HTTP/2, which a
deployed Worker's `fetch` does and `wrangler dev` on macOS does not (workerd
issue #4841), so no notification can leave a local Worker at all.
`scripts/targeted-question-check.mjs` runs the real push, pull and notify over
`schema.sql` in an in-memory SQLite with `fetch` replaced, which covers
everything up to the wire; the wire itself is checked once, deployed. And the
app registers only when it is signed with the `aps-environment` entitlement,
which needs Push Notifications on the App ID — a capability Apple gives the
paid Developer Program and not a personal team (SETUP). Until then the
registration fails, is logged as a domain and a code, and nothing else
changes.

## 12. The question ladder

Some people cannot start with "tell me about this photo". The first thing this
app asks of a person has to be small enough that failing at it is impossible —
and it has to grow as they get used to being asked.

*This paragraph describes the state before the ladder was built; the table at
the end of this section is what shipped. Marked as past 9 Sep 2026, because it
was written in the present tense and a reader met it as current.* It did
neither. Questions were not selected at all: `openQuestions` took the three
oldest unanswered ones and the interview loop took `newQuestions.first`,
whichever the model happened to emit first. Both go through
`QuestionLadder.select` now. Extraction
aims its questions "at the gaps" (`extract.ts`), and a gap question is almost
always *"Millainen ihminen Aino oli?"* — a three-sentence answer. Worst of all,
a photo nobody has spoken about yet has **no questions at all**, so the first
contact of the whole app is a blank button. That is the wall.

### The levels

Five, measured by **the shape of the answer** rather than the topic:

| Level | Name | Answer | Example | Word floor |
|---|---|---|---|---|
| 1 | Naming | 1–3 words | "Kuka tässä kuvassa on?" | 1 |
| 2 | Fact | a sentence | "Missä tämä on otettu?" | 2 |
| 3 | Description | a few sentences | "Millainen ihminen Aino oli?" | 10 |
| 4 | Episode | a story with a beginning | "Kerro siitä päivästä, kun muutitte Ouluun." | 20 |
| 5 | Meaning | reflection | "Mitä toivoisit lastenlastesi tietävän isästäsi?" | 20 |

Levels 1–2 have the property the whole design rests on: they can be answered
with a three-second dictation or a typed word. That is a genuinely small
experiment, and it needs no new UI — both paths already exist.

**Starters** fill the blank-button gap. A subject with no memories offers
**two** questions derived from its `kind` — `starterQuestions(for:)` takes the
first two — with no LLM call, no network and no AI minutes. Their level is
written out beside each text rather than read off it, so a reworded starter
cannot quietly become harder than the one place in the app that promises an
easy question: a photo and a person open at `.naming`, a place at `.fact`.
They are **not stored and not synced**: thirty imported photographs would
otherwise put sixty rows into the family's open-question list and make the
list worthless. A starter is a prompt, not a debt.

### The algorithm: a staircase, not a model

A **transformed up/down staircase** (Levitt 1971, psychophysical threshold
tracking), plus one borrowed piece of Leitner. Both are existing methods, ~40
lines together, and neither needs training data:

```
two consecutive fluent answers  →  comfort += 0.5
one strained answer             →  comfort -= 1.0
```

Two-down/one-up is known to converge on roughly a 70 % success rate, which is
about where the questions stay answerable without being trivial. The asymmetry
is the point: **slow to climb, quick to drop.** For this user one wall costs
more than a run of questions that were too easy.

There is no right answer to "what was your father like", so the signal is not
correctness but whether the person could answer at all. Everything it reads is
already stored:

| Observation | Source | Reading |
|---|---|---|
| Answered, word count ≥ the level's floor | `rawTranscript` | fluent |
| Extraction yielded a mention or a date | `mentions`, `date` | fluent |
| Answered under the floor | `rawTranscript` | strained |
| Question skipped without an answer | "Riittää tältä erää" while asking, or a sub-second recording | strained |
| Over 14 days since the last answer | `createdAt` | `comfort = max(1.5, comfort − 1)` |

The last row matters as much as the staircase: **coming back is always a small
step.** After three weeks away nobody is asked where they left off.

Skipping is read as strain even when it is really fatigue at the end of a long
interview. That is a knowing inaccuracy: it nudges the next session slightly
easier, and for an 80-year-old that is the correct direction to be wrong in.

**Selection is not compulsion.** The Tell screen already shows two open
questions; they are picked by fit — nearest the current level, with a penalty
for being above it rather than below — and the easiest is shown first. The
person still chooses, and the choice is free calibration.

A question asked by a *person* is pinned rather than ranked: "Ville kysyy" pulls
harder than any machine prompt, and a grandchild's question going unseen for a
fortnight is a worse failure than a question one level too high. Never more than
one of them, and never the last slot — so a hard one always arrives beside an
easy way out.

And since 12 Sep 2026 a person's question is the *only* kind the Kerro tab's
idle screen offers. The extraction's follow-ups stood there too, under *"Tai
vastaa aiempaan kysymykseen"*, and after one telling that was three questions
the app had thought of by itself on the screen somebody opens cold. They are
still asked — the interview loop asks them the moment the telling ends, and
the Tell screen opened from their subject lists them — but the front screen
carries what a person asked, or nothing.
`testTheFrontScreenCarriesNoneOfTheModelsQuestions` pins it.

### What was rejected

| Alternative | Why not |
|---|---|
| IRT / Elo (adaptive testing) | Needs a right/wrong signal and a calibration corpus. A family produces tens of observations, not thousands. |
| SM-2 / FSRS (spaced repetition) | Models forgetting; nothing here is being memorised. **One piece is borrowed:** a skipped question returns later instead of vanishing — the same principle as "gaps are shown". |
| Bandits (Thompson, UCB) | Cold start would spend an elderly person's few sessions on exploration. |
| A model of our own | No data, no time, and not explainable in a demo video. |

Inventing nothing is an advantage here: the repo is judged on being readable.

### Two things it deliberately does not do

1. **The level is never shown.** No points, no badges, no "level 3".
   Gamifying an old person's account of her own family would be condescending,
   and it would wreck the tone the rest of the app is built in.
2. **`comfort` does not sync.** It lives in `UserDefaults` on the device, not in
   a column on `member`. The family has no business seeing a difficulty score
   attached to a relative, and a device-local number cannot produce a sync
   conflict. The phone belongs to one person; so does the number.

### Built in this order

| Step | Work | Touches |
|---|---|---|
| **0** | Starters for a subject with no memories | `QuestionLadder.swift` |
| **1** | Level read off the question text, ladder ordering in `openQuestions` and in the interview loop, outcome recorded on save | `MemoryStore.swift`, `TellViewModel.swift`, `TellScreen.swift` |
| **2** | `level` as a field of extraction's JSON schema (the model labels its own question, no extra call) and a `prompt_question.level` column | `extract.ts`, `schema.sql`, `sync.ts` |
| **3** | Generation aimed at a level ("one at N−1, one at N, one at N+1") | `extract.ts`, `worker.ts` |

The order matters because each step stands alone. Steps 0–1 are client-only: the
level is **derived from the question text** by a Finnish opening-word classifier
(`Kuka`/`Missä` → 1–2, `Millainen` → 3, `Kerro` → 4, `Miltä tuntui` → 5), so
nothing is stored, nothing is migrated and sync is untouched.

Step 2 makes the label the model's own — it knows what it meant by the question
— and the classifier stays as the fallback for rows written before the column,
for questions a person asked, and for a model that ignored the field. Three
places tolerate a missing level rather than failing: the Worker stores it as
null, sync keeps an existing level when an older device pushes the row back
without one (the same `COALESCE` rule as authorship), and the app decodes a
question that arrives as a plain string.

Step 3 sends the teller's level with the transcript and asks for one question
below it, one at it and one above. **It is the one part measurement has not
caught up with**: it changes the Finnish extraction prompt, and re-validating
that against real elderly speech costs credits (CLAUDE.md). It is built to
degrade safely — if the model ignores the instruction, the questions are still
labelled, still ordered and still chosen by fit; only the spread is lost. If
that measurement ever contradicts it, this is the piece to revert, not the
ladder.

The pairing required by "every addition requires a removal" (CLAUDE.md):
**`prompt_question.target_member` is formally out of v1**, and §11's note above
becomes permanent. It has been unused in the schema from the start, and a ladder
that picks questions for the person in front of it makes routing to a named
member more tempting than it is worth — it would need a picker, a visibility
explanation, and a second selection rule competing with this one.
**Reversed on 25 Sep 2026 by the user's decision** (§11): the column is used,
and the ladder keeps its rule for everything else — a question asked of this
member by name is simply offered before the ladder's own choice.

As a side effect this closes the open edge left in §10: the open-question list
grows by three every round, and ordering plus the return of skipped questions is
exactly the cap that was deferred to "the store".

### What the questions are aimed at — 19 Sep 2026

The ladder decides **how much** a question asks. Nothing until now decided
**what it asks about**, and that half was worse than it looked. The extraction
saw one thing, the transcript, and rule 6 of the prompt asks it for a gap *in
the speech* — so the questions converged on the three shapes that rule names, a
person named but not described, a place known only by its name, a smell or a
sound, and came back in the same shapes on the fourth telling about a
photograph as on the first. The archive was standing right there and the model
had never been shown it.

Three things now travel with the transcript, and the fourth is the photograph
itself. `ExtractionContext` carries the subject the telling was filed under, so
a question can ask for the year a photograph does not have; what is **missing**
about each person and place the archive already links to that subject; and every
question still open on it, so the model can aim elsewhere rather than be
filtered down to fewer than three afterwards. What the archive *holds* never
leaves the phone — no memory text is sent, only names and the shape of each
hole, from a closed vocabulary of five that the Worker turns into a Finnish or
an English phrase. The client cannot write the prompt by writing a gap, and the
data goes in the **user** message while the instruction stays in the system
prompt, because `asked` is free text an earlier model wrote and free text
appended to a system prompt is somewhere for an instruction to hide.

A photograph is not on that list of gaps, and that is the one thing the check
found. *"Onko teillä valokuvaa Ainosta?"* is answered "kyllä on" and nothing has
been told — and `QuestionLadder.outcome` measures an answer against the level's
word floor, so the honest answer reads as strain and drops the teller a whole
level. A question that punishes somebody for answering it correctly is worse
than no question. Every gap that remains is answerable by talking.

Measured 19 Sep 2026 against `google/gemini-3.6-flash` through the real Worker,
one Puumala transcript, level 3. With nothing sent the middle question was
*"Millainen paikka Puumalan mökki pihapiireineen oli?"* — which needed no
archive to write and restated one of the three questions already open. With the
archive it became *"Miten Aino oli sinulle sukua ja millainen pikkutyttö hän
oli?"*, which is the `relation` and `description` holes exactly, and the easy
question moved to *"Missä päin Puumalaa tämä mökki tarkalleen sijaitsi?"*, which
is the `place` hole. With the photograph as well, the easy question became
*"Minä vuonna Aino syntyi?"* and the middle one *"Kuvassa näkyy suuri puuvene
rannassa — muistatko, oliko se perheen oma?"*. The memory's own text stayed
215–219 characters in all four runs: the archive aims the questions without
reaching the telling, which is what it was told not to do.

**The photograph rides on the extraction call rather than a second one**, because
`MODEL_EXTRACT` is already multimodal. Measured the same day: a flat **+1140
prompt tokens whatever the resolution** — 512, 768 and 1024 px tokenise
identically — taking the round from $0.0045 to $0.0061, about a sixth of a cent.
1024 is sent because the smaller one was not cheaper and was the one that
answered about the cottage in general rather than the boat tied to the jetty.
Only a `photo` subject, and only the picture as it was taken: a colourisation is
the family's guess at the colours (§24, rule 4), and asking a model what it sees
in another model's output is a question about the wrong picture.

The prompt is told to **describe, never identify** — *"nainen vasemmalla"*, not a
name — and not to ask about age, health, money or mood, because the person
answering is often in the photograph. That is rule 4 on a surface where the
model can see faces and the app cannot.

Two checks, both free. `scripts/extraction-context-check.swift` runs the builder
and the de-duplicator, which is why `ExtractionContext.build` is pure over the
model types rather than a method on `MemoryStore` — the store reaches
`MediaStore` and so reaches UIKit, and a check that needs UIKit needs a booted
simulator. `scripts/extract-shaping-check.mjs` gained the Worker's half: the
caps, the closed vocabulary, and that an empty archive emits nothing at all. An
instruction about a list that is not there is how a model starts inventing the
list.

The pairing required by "every addition requires a removal" (CLAUDE.md): the
model's three questions are **no longer taken on trust**. `add(questions:)` used
to append whatever came back, three per telling for ever, and the already-asked
list only asks the model not to repeat itself. `ExtractionContext.deduplicated`
drops a restatement on the client as well, so the archive's question list stops
growing by three a round whether or not the model cooperated — which is the cap
§10 deferred to "the store" and the note above claimed was already closed.

It stopped the repeats, not the growth, because each telling still brings three
questions and answers at most one. **Since 25 Sep 2026 one subject carries at
most five open questions** (`ExtractionContext.openQuestionCap`). A model's
reply adds only as many as fit: the de-duplicated questions first, in the
model's order. The question being answered frees its own slot. Both paths a
reply takes into the archive go through the same `admitted` gate, the
ordinary telling and the catch-up in `DeferredMemory`, and before this the
catch-up did not de-duplicate at all. A question a person asked is never
held back, though it counts towards the five. Neither is a question synced
from another phone, which is why the count can go past five. The gate decides
only what this phone adds.

## 13. The guessing round — built, then cut

**Cut on 16 Aug 2026** (PLAN.md §5, row 8). The code is gone: `GuessRound.swift`,
`GuessRoundCard.swift`, the `guess` table, the sync rows in both directions, the
mask check and the round's own test file. This section is what is kept, because
the argument in it is still the best answer this project has to a problem it
still has.

### What it was

A memory that named exactly one person was shown to the rest of the family with
the name taken out and four person cards to choose from. It was **derived, never
authored** — nothing was stored but the answer, because only the answer is a
fact about a human being rather than about the current state of the archive. The
teller asked nothing extra: she told the story the way she always does, and the
round fell out of it.

### Why it earned its place, and what the cut costs

Two things, and they are separable.

**The reading loop.** Everything in the magic moment is a *writing* loop, and
nothing gave the family a reason to open a memory that was already written. That
is how family archives actually die — not unrecorded, unread. The round cost one
tap and was the only part of the app that asked nothing of the 80-year-old.

**Half of that is answered, and this section claimed none of it was for two
weeks after it stopped being true.** `NewFromFamily` — built 17 Aug 2026,
docs/UX.md §6, which paid for it by closing the map — gives a reason to open a
telling that is *new and unread*, and its own source quotes the same PLAN §4.1
sentence this paragraph does. What it cannot do is visible in one line of it:
`unseen(in:me:)` is `authorID != me` minus a device-local seen list, so it is
empty by construction in a family of one and empty again the day after
everybody has looked. **The round needed nothing to arrive.** It re-presented a
telling that was old and already read, which is the half still open — and the
half that matters most for an archive whose whole risk is the year nobody
opens it.

That this section went on saying "nothing else in the app addresses it" is the
failure §1 warns about in its own words: a sentence that was true when written,
was never re-read, and reads exactly like one that still is.

**Blind confirmation, which is the larger loss.** Rule 4 says AI proposes and a
human confirms. A proposal card with the name already written on it gets tapped
"yes" without being read; somebody who was never shown the name and arrived at it
anyway has genuinely recognised the person. The round was therefore not just a
game on top of the confirmation UI — it *was* the confirmation UI, and it
replaced the standalone "confirm this proposal" screen that was consequently
never built. What is left is the orange proposal row: the weaker instrument the
round was chosen over. CLAUDE.md rule 4 now says so instead of implying
otherwise.

### The parts worth having back

**Taken up on 30 Aug 2026**, in a different shape: the deck's card asks *"kuka
tässä on?"* over the photograph the name was heard in, with the proposal unmarked
among four names. §23 records what was built and which of the pieces below went
into it. The reading loop's older half above is still unsolved; this is the
confirmation half only.

If confirmation is ever strengthened again, these are the pieces that were
expensive to get right and are recorded here rather than rediscovered:

- **The mask has to be a word, not a gap.** An em dash run reads to VoiceOver as
  nothing at all or as punctuation, so the sentence is spoken as though the name
  had simply not been said, and the card asks nothing. The accessibility label
  put a word in the hole. A round that leaks the hidden name still looks like a
  working round, which is why the masking had a check script of its own — that
  whole class of bug is silent.
- **"En muista" is an answer.** Stored with no subject, it confirms nothing and
  un-confirms nothing, and it is what stops the round coming back forever. For
  this app's user it is also the likeliest answer, and treating it as a
  non-response would have been designing for somebody else.
- **A wrong guess is kept rather than reduced to a boolean.** A family that keeps
  naming the same wrong person is telling you the extraction picked the wrong
  name.
- **One guess per person per memory.** The answer is revealed immediately, so a
  second attempt is answering a question you already know.
- **A correct guess had to survive a merge.** Confirmation compared through
  `merged_into`, or every correct guess made before a merge would quietly stop
  counting.

### One measurement it leaves behind

The round's card filled the screen at AccessibilityXXXL and pushed the photo grid
below the fold — and a `LazyVGrid` does not build rows nobody can see, so nothing
measured a photo tile at the largest text size. Two attempts to scroll first and
audit after reported contrast failures on elements the accessibility tree still
held at their pre-scroll frames. §15 recorded that as an open gap. **Cutting the
round closed it**, which is the one place where this removal made the app easier
to check rather than harder.

## 14. Settings — taking the archive out, and leaving

The honest remainder of §8's list. Two things belong here and one does not:
export and leaving are built; reporting and blocking are formally out of v1
(below).

### Where it sits

Not a fourth tab — three is the stated limit of what this user holds in mind.
The People tab's toolbar button becomes a gear that opens Settings, and the
family view moves one step down, behind a row in it.

That also closes a gap nobody had noticed: the toolbar button only appeared when
a backend was configured, so a **single-device archive had no toolbar entry at
all** — and a local archive is precisely the one with no copy on any server, the
one that needs an export most.

### The way into a family

One row, and only where the archive was *chosen* local rather than local for
want of an address (`Session.isLocalByChoice` needs the `local_only` flag and a
backend URL together). It opens `EnableSharingScreen`, which says what changes,
says that the memories already on this phone go with it, and says that there is
no way back — and then does it: `MemoryStore.markAllPending()` so the rows
travel, the onboarding fork as a sheet over the archive, with `local_only` cleared only when a family exists (`Session.store(familyID:)`, 5 Sep 2026)
and the onboarding fork comes back.

One-way on purpose. What has reached the family is on other people's phones and
cannot be recalled from this one; a switch that pretended otherwise would be
this app making a promise about somebody else's device.

Why it exists at all is in docs/UX.md §11.1: until it did, the only thing that
unmade the first form's answer was *"Tyhjennä tämä laite"*, and that mode
attempts no transcription — so a picker answered out of habit on the first
screen turned the product off for good on that phone.

### Export

One zip through the share sheet:

| In the zip | Why |
|---|---|
| `memories.html` | Every memory under its subject, dates as they were told, photos inline, audio playable — and the words as they were said, folded under the tidied text wherever the two differ |
| `photos/`, `audio/` | The originals, byte for byte — audio is never re-encoded, here least of all |
| `archive.json` | The archive as a model — subjects, memories, questions, relations; the outbox and the sync cursor left out |

**Those four names were Finnish — `muistot.html`, `kuvat/`, `aani/`,
`arkisto.json`, under `Muistoarkisto/` — until 25 Sep 2026**, on the argument
that a filename is format rather than prose and the prose describing it is
translated around it. What changed is who reads them: the demo film draws this
folder open, name by name, in the one shot whose whole argument is that the
archive outlives the app, and that film is watched and judged in English. They
are English on every phone now rather than following the device, so two members
of one family produce archives that look alike. The rename costs nothing
because **the export is one-way**: every path inside a zip is written by the
same run that writes the page referencing it, and nothing anywhere reads an
exported archive back in, so a zip made before that day keeps its own names and
its own page and still opens. Only the sentence naming the folders is
translated, and `<h1>` stays prose — *Muistoarkisto* on a Finnish phone,
*Memory archive* on an English one, which is how `export-check.mjs` tells which
language a page is in.

Four decisions:

- **Media missing from the device are fetched first.** A phone that joined last
  week holds R2 keys, not files. An export missing grandmother's voice would be
  a lie about what the word means. It costs a progress bar.

  The fetch can fail — offline is the ordinary case, at exactly the cottage
  where somebody thinks to make a copy — and until 23 Aug 2026 the failure
  was skipped in silence: the zip went out looking complete, and a memory
  whose audio never arrived even asserted *"Ääni tallessa"* over an audio
  element that was not there. The skip stays (one failed download must not
  cost the family the other two hundred files); the silence went. The build
  counts what it could not include, an alert says the number before the
  share sheet opens — *"Jaa silti"* is the ordinary answer, since the files
  are safe in the family's archive either way — and the page itself carries
  the same sentence, because the page is the copy that outlives the app and
  a gap it does not name is a gap nobody will ever know to fill.
- **HTML rather than a list of text.** The point of an export is that the
  archive outlives the app, and a browser is the one program every family
  already has. The same file carries the photos and plays the audio without
  Kinlore installed. **And the page reads in a book's order, on purpose:**
  photographs first, each with its memories beneath it, then people, places
  and events, told subjects only, and the untold named at the end rather
  than dropped. The order is the code's own — `SubjectKind.sortOrder` in
  `ArchiveExport.swift`, *"the order the family thinks in, not the
  alphabet's"* — and since 21 Sep 2026 it is a decision as well, so that
  anything ever made from this archive on paper reads in the same order as
  the page and is a second writer over the same walk, not a second
  structure.
- **The raw JSON travels beside it.** If the readable version ever lags behind
  the model, nothing has been lost.
- **The words as they were said are on the page too, since 26 Sep 2026.**
  Rule 3's second half had travelled in the JSON alone: the page carried the
  tidied text and nothing else, so a family reading the copy that outlives the
  app never saw what the tidying had changed. Now each memory whose transcript
  differs from its text folds the transcript under it — *"Alkuperäinen
  litterointi"*, a `<details>` the browser opens by itself, with no script for
  a machine in twenty years to refuse. Only where the two differ: a telling the
  tidying left alone has nothing to fold, and a typed memory has no transcript.
  `export-check.mjs` opens the demo archive and counts one fold, on the one
  demo telling that carries the words it was said in.
- **`NSFileCoordinator(.forUploading)` does the zipping**, so no dependency is
  added for one archive format.

And four more since 5 Sep 2026, from the review's finding #88 — *the export does
not carry a real family's archive, and nobody is ever told to run it*:

- **The zip carries its date.** `MemoryArchive-2026-09-05.zip`, ISO order, so
  the copy a family makes every year does not write over the last one in the
  folder they keep them in. `export-check.mjs` picks the newest by name.
- **The media are hard-linked into the export, not copied.** The export folder
  and the media store share a volume, so a link costs nothing and takes no
  room, and the zip reads the bytes through it. For an archive of a gigabyte
  the copy was a second gigabyte on the phone before the zip took a third, on
  the old phone least able to spare it. A volume that will not link still gets
  a copy. And the coordinator's zip is **moved** out of its block rather than
  copied, for the same gigabyte.
- **The zip is made off the main actor**, so *"Pakataan"* keeps drawing while
  a family's gigabyte is packed, and **"Peruuta" ends a running export** —
  the loops check for cancellation between files, and the next build starts
  clean. Until then the only way to stop one was to leave the screen and hope.
- **And one that was built and taken out the same evening.** *"Viety
  viimeksi 5.9.2026."* under the export row — when the last copy left, which an
  archive that has grown for a year since should tell the person about to make
  one. One line in that footer pushed the leave section's footer to y 729 and
  the wipe row below the fold at the default size: three audit findings and
  `WipeTests` failing to find *"Tyhjennä ja aloita alusta"*, the same wall the
  section below records for the row reverted on 29 Aug. This `List` is at its
  height limit, and the line went. So the "nobody is told" half of the finding
  stays open: nothing in the app says when the last copy left or that one is
  due. The phone is a full copy of its own since §5's `FullCopy`; the export is
  the copy that leaves the phone, and it is still made on nobody's prompting.

What is still not built from that finding: a resumable export in the background
that survives leaving the screen, and any measurement of the real thing — the
sizes above are §5's arithmetic, not a phone's.

### Emptying, and the name it got on 29 Aug 2026

**And what it says on the last copy, since 5 Sep 2026.** Its warning said *"vie
arkisto ensin"*, and the export at a cottage with no signal had just fetched
none of the media and reassured that the files were still safe and would come
along next time — while the wipe that followed forgets the identity and the
key, after which the sealed voices on R2 can be neither found nor opened
(founder's-eye review, finding #43). `FullCopy` (§5) now knows how many of the
family's files are not on this phone, so the last copy's warning carries the
number — *"…3 on vain palvelimella, eikä tyhjennyksen jälkeen niitä saa enää
auki"* — and its button says *"Tyhjennä silti"*. The export's own alert stopped
saying one sentence for three situations: while somebody else holds the
archive the files will indeed be in the next export; on the last copy the export
is not a complete copy and says so, and says not to empty the device before
one is; on a local archive a file that is not here is not anywhere.
`WipeTests` drives the warning with the copy held at three of twelve.

*"Tyhjennä tämä laite"* was true and half the story. What follows the emptying
is a **first launch**: `renewIdentity` takes a new identity with the family key
and the family id, so there is no family to return to and the app lands on the
onboarding fork — the same two buttons a fresh install meets. The store, the
question ladder, the upsell rhythm, the seen list and the deck's skips all go
with it.

Nothing said so. Somebody wanting to walk the whole arc again — photograph an
album, tell about a card, invite somebody, and then do it all a second time on
a real phone — could not tell from the label that this was already the way, and
asked for a second button that would have done the identical thing. Building it
cost three audit findings on rows that pass today, because this `List` is at
its height limit and any row added to it pushes an existing one into a slot the
audit objects to; that was measured three ways and then reverted.

So the row is **"Tyhjennä ja aloita alusta"**, and every branch of the warning
now ends on *"Sovellus avautuu ensimmäiselle näytölle."* — a dialog sentence,
which costs the screen no height at all. The cheaper fix was the better one:
the problem was never a missing button, it was a promise the app kept without
saying it.

Comments through the app still name this act *"Tyhjennä tämä laite"*. They are
describing the same act, and they were left alone rather than sweeping eight
unrelated files into one rename.

### Leaving

There is no account here, so "delete my account" would be a lie in two
directions at once. There is a device identity in the Keychain and a membership
in a family, and they are genuinely separate — so the screen names both:

- **Poistu perheestä.** The membership ends. **The memories stay.** A family
  archive exists so that what was told outlives the teller, and a member who
  leaves taking grandmother's voice with them is the exact failure this app was
  built against. An owner who leaves hands ownership to the longest-standing
  remaining member: an ownerless family could never invite anyone again. The
  last member cannot leave — there would be nothing to leave, and the archive
  would become unreachable rather than deleted.

  **The member row is marked, never deleted** (`member.left_at`). The first
  version of the route deleted it, and testing against a local D1 showed what
  that means: `memory.author_id` references the row, so the delete failed on the
  foreign key — only a member who had never told anything could leave. Had it
  succeeded it would have been worse, because the name shown on a memory is read
  from `display_name` on every pull: leaving would have quietly stripped the
  teller's name off everything they ever told. Leaving ends a membership; it does
  not unwrite the past. The same test caught the role: handing ownership on
  without taking it off the leaver left two owners, and a founder invited back
  walked in as one.

  On the device, leaving keeps the local copy and resets only the sync cursor.
  The counter is granted per family (§2.2), so a cursor carried into the next
  family would ask for "anything above 412" and silently receive nothing.
- **Tyhjennä tämä laite.** The store, the media, the ladder's state and the
  Keychain identity. Afterwards the app is a fresh install. In a family the
  memories are still on the server and rejoining brings them back — unless
  this was the last copy: the server does not let the last member leave, so
  the sealed rows stay, but the key and the identity go with the wipe and
  nothing can open them again, which is what the dialog says since 12 Sep
  2026 instead of *"poistetaan lopullisesti"*. In a local archive they are
  gone for good, and the screen says exactly that in those words rather than
  in a generic warning.

  It also **offers the export from inside the dialog** when nobody else has a
  copy. Saying "vie arkisto ensin" and then presenting one button, the
  irreversible one, is an instruction to go and do something else at the moment
  somebody has already decided to act. The warning was right and it was not
  prevention.

  Two more of its promises were found unkept on 23 Aug 2026. **The leave was
  first but not decisive**: its result was discarded, so a failed leave —
  offline, or the server refusing — wiped the store and renewed the Keychain
  identity anyway, leaving a member row in the family forever with nobody able
  to authenticate as it; the ghost even counted against the last-member check,
  so the genuinely last person could leave and strand the archive on a device
  that no longer exists. The wipe now stops on a failed leave and says so in
  the leave's own words, and `WipeTests` holds the store intact through the
  refusal. And **the last copy's wipe left the invites alive**: the invitation
  text carries the family key, so for up to seven days a live code was
  join-and-read access to an archive the dialog had just called gone. That
  wipe now revokes the family's open invites first — best effort, never
  blocking, because an offline phone must still be emptiable — and the
  dialog's sentence says it does. What it still cannot do is remove the D1
  rows and R2 objects themselves; with no members able to authenticate and no
  live codes, nothing can reach them, and server-side deletion stays a
  deliberate non-feature. Member removal, which used to stand beside it here
  as the other one, was built on 5 Sep 2026 (§4): it turned out to be the only
  remedy for an invitation that reached the wrong person.

**Verified by opening it, 16 Aug 2026.** The export is the one output that
leaves the app for good, and its promise — *"sen voi avata millä tahansa
koneella ilman tätä sovellusta"* — had never been checked against an actual
file. It was: run on the simulator, pulled out of the app container, unzipped.
The page carries the memories, `archive.json` carries the model, and a recorded
memory travels as `audio/memory-….m4a` — real M4A by `file`, not by extension —
with the page linking it as `<audio controls src="audio/…">`, a relative path
into the same folder. Opened in a browser, grandmother's voice plays out of the
zip.

The first run proved nothing and is worth recording as a trap: the demo archive
has no local media at all, so the export contained a page and a JSON and looked
complete. A second archive with a real recording in it is what tested the half
that matters.

**What it no longer carries.** The JSON was the on-disk snapshot, which means it
carried the outbox — which rows this phone had not pushed — and the server's
ordering cursor. Facts about one phone's sync on one afternoon, in the file a
family opens in twenty years, which said `dirtyGuesses` at them. It has its own
shape now: subjects, memories, questions, relations.

**Deliberately not built: deleting your own memories out of the family.** Rule 3
keeps the original audio because the speaker may no longer be around to ask, and
a tap that erases a dead person's voice from everybody else's archive is not a
feature this app should own. If it is ever needed, it belongs to the family
owner and to a conversation, not to a member's settings screen.

The pairing required by "every addition requires a removal" (CLAUDE.md):
**moderation is formally out of v1**, with one exception made on 5 Sep 2026 —
the owner can remove a member (§4), because without it a link forwarded to the
wrong person was permanent. `report` and `block` are in the schema for
Apple's rule 1.2, and §7 already said they could be cut entirely if the release
is never made. It is not being made (PLAN.md §2), this is a family's private
channel rather than a public network, and the schema keeps the tables for the
day that changes.

## 15. Contrast — the rule that was never measured

Rule 1 of the product says the primary user is 80 years old. Dynamic Type,
VoiceOver and tap targets were designed for from the start. **Contrast was not,
because contrast is not something eyes can check** — a screen looks fine, and a
screenshot looks fine, and the number is still 4.0 when the minimum is 4.5.

The guessing round's accessibility audit found it by accident: all four answers
below the minimum on a screen that had been looked at half a dozen times. So the
audit was run over the screens that could be reached without a network or a
purchase, at the default size and at the largest one
(`KinloreUITests/AccessibilitySweepTests`): onboarding, the memories grid and
its empty state, Kerro and its typing view, the people list and its empty state,
a person's card, a photo's card, the ask sheet and settings. It found the same
class of problem in almost all of them, and nearly all of it came from three
system defaults.

Not covered, and honestly so: the paywall (needs a RevenueCat key), and
Kerro's asking and processing states, which animate. This list used to be
longer — the family view (`-seed family`), the result states (`-screen
result`) and, since 23 Aug 2026, the recording screen itself have each been
brought in. The recording one deserves its account: it animates continuously,
so the settling every sweep waits for never comes, and the product's core
moment had never been measured at any size. The audit needs no settled screen
— what an animation costs is element-detection noise, so
`testRecordingInProgressIsAudited` forgives exactly that category and
measures everything else. Its first run reported two real findings on the
first screen an 80-year-old tells into: *"Paina kun olet valmis"* under the
contrast minimum within the pulsing disc's reach, and the timer clipped at
the default size. Both fixed the same day, which is the argument for the
audit in one sentence.

### Three defaults, three fixes

| Default | Measured | Replaced with |
|---|---|---|
| iOS blue `#007AFF` on white | **4.0:1** | `AccentColor` `#0B57D0` — **5.54:1 on the paper** |
| `.secondary` label | **≈4.2:1** | `Elder.supporting`, 75 % of primary — **≈6.6:1** |
| iOS orange `#FF9500` on white | **2.2:1** | `Elder.proposal` `#B23C0B` — **5.14:1 on the paper** |

Each is one place rather than thirty. The accent colour is an asset catalog
entry, so every tinted button and every tinted line of text moved at once; the
other two are constants in `Elder.swift` next to the tap target size, where the
next person will find them.

The orange one is worth naming. It marks *"the AI proposed this, nobody has
confirmed it"* — the single label in the app whose entire job is to make
someone stop and check — and it had the **lowest contrast of anything on
screen**. It has been fixed twice, which is the lesson: `#C2410C` answered the
measurement above on white, and when the ground became parchment it measured
4.43:1 against it and was under the minimum again. `#B23C0B` is 5.14:1 on the
paper it actually sits on. A colour is a ratio against a ground, not a value. The
shape of the icon has always carried the same meaning, which is why the screen
was still usable; that redundancy is what a colour fix should never be allowed
to replace.

A fourth default belongs with them: **iOS red measures 3.6:1**, and it labels
*"Tyhjennä ja aloita alusta"* — the one button in the app that destroys an
archive, called *"Tyhjennä tämä laite"* when this was measured and renamed on
29 Aug 2026.
`Elder.destructive` `#B3261E` measures 5.67:1 on the paper, 6.28:1 on card, and is
unmistakably still a warning. It read 6.5:1 here until 12 Sep 2026 — the number on
white, the same trap the orange above fell into, and the last ratio in this
section still quoted against a ground the app does not have.

### The rest

- **List headers and footers** style themselves below the minimum, so the ones
  that carry an instruction say their colour out loud.
- **`ContentUnavailableView`'s description** does the same. These are not empty
  states in this app but invitations (§6.5 of PLAN.md), and an invitation has to
  be readable.
- **The typing view's placeholder** was `.tertiary`, the faintest colour iOS
  has. A placeholder conventionally is — but this one is the sentence that tells
  her what to write.
- **VoiceOver was reading the onboarding illustration aloud as "photo.stack"** —
  the SF Symbol's own name, in English, on the first screen of a Finnish app. It
  is decoration and is now hidden from the tree.

### What is still accepted, and why

Listed in `AccessibilityPolicy`, each with a reason, rather than by narrowing the
audit — narrowing would also switch off the checks that catch real regressions in
those same categories, which is how the contrast problem survived this long.

- **Anything overlapping the floating tab bar.** iOS 26's tab bar is a
  translucent capsule that content scrolls beneath by design, and the audit
  samples the pixels it dims. Every contrast failure left at the largest text
  size was this — `Kuvat`, `Paina ja ala puhua`, `Ehdotus — vahvista henkilö` —
  the same colours that pass at every other size. Checked on screen: what fails
  is the overlap, not the colour. The rule is contrast-only and requires a real
  frame intersection, so it cannot quietly excuse a genuinely faint label.
  Above the bar, the strip its scroll-edge effect reaches into is not excused
  either but *measured*: a contrast finding there is answered by counting the
  element's pixels (`ContrastMeter`, `AccessibilityPolicy.fadeReach`). The
  strip is 120 pt since 6 Sep 2026, 60 before, and it was widened only after
  two findings outside it were measured first — the grid's *"Ilman
  ajankohtaa"* heading 83 pt above the bar and the blind card's *"Sanni"*
  button 104 pt above it, both at the largest size, 10.4:1 and 15.2:1 on
  screen against a 4.5:1 minimum. The second had been failing at HEAD on a
  quiet machine, on a screen nothing that day had touched. The meter's ink is
  the **1st** percentile of a frame's pixels — the 5th until that day, the 2nd
  until 10 Sep 2026: a 60 × 60 pt tap target around a 15 pt word is about
  three per cent ink, and the 5th percentile fell past it onto the fringe —
  the invite row's *"Poista"* read 1.59:1 that way and 6.4:1 at the 2nd, on a
  colour that is 6.4:1. The 1st is the last percentile that still finds the
  ink in a sparse target and still fails a frame with none, which is the
  property that matters and the one the audit records. The numbers are in
  `ContrastMeter`.
- **Text seen through the floating tab bar.** Element detection reads the
  picture and asks for an element under each word; under the translucent bar
  the bar is what answers, and the finding arrives with no element at all.
  Measured on the Perhe screen's audit picture, 6 Sep 2026: the two findings
  were the invite footer's lines under the bar. Allowed only with no element
  and only under a bar — a word with an element is still judged.
- The guessing round's truncated preview (§13): a teaser, whole text one tap
  away, all of it in the accessibility label.
- `Lisää sukulainen`, where a `Menu` reported a label frame smaller than the
  text it draws. Verified on screen at both sizes. Dormant since 21 Sep 2026:
  the row is a `Button` and the choice behind it a sheet of plain buttons
  (`RelativeKindSheet`), after the menu's fifth item, *Ystävä* after a
  divider, never fired on iOS 26.5 — tapped at its centre, at its edge,
  pressed, with the menu opened upward over its own row and downward clear of
  it — while the four above it fired every time. The tree's person sheet had
  made the same choice on 13 Sep for the other reason: a menu's rows barely
  grow with the text size, and no UI test here can open one.
- The photo tile's memory count, capped at `accessibility2` on purpose.
- **Anything in the fade under the navigation bar**, which is the tab bar's rule
  from the other end. iOS 26 fades content into the bar and its search field as
  it scrolls beneath. *"Muistatko kuka?"* — the primary colour at
  `.title3.weight(.semibold)`, the strongest text in the app — began failing at
  the largest size the day a search field appeared above it, and a screenshot at
  that size shows black on white. Same 24 pt margin as the bar below, same
  warning: measure before widening it.
- **`.searchable`'s own field and its clear button.** The field keeps a fixed
  44 pt box while the text in it grows, and the audit reads that as clipping —
  shortening the prompt from twenty-seven characters to four changed the finding
  not at all, which is the evidence that it is the box and not our words. The
  clear button is 19 × 19 pt and has no API to make it bigger. Accepted rather
  than answered, and it can be because nothing depends on hitting it: the
  keyboard's delete key clears the field and "Peruuta" beside it is a full-size
  target. If search ever stops being the grandchild's tool, the answer is our
  own field rather than a wider exemption.
- **MapKit's legal link.** Every `Map` draws Apple's attribution as a link
  of about 50 × 11 pt in its bottom-left corner, and there is no API to make
  it bigger or to move it. The place card never met the finding because its
  map is one element; the map of places (§18, 21 Sep 2026) cannot be, because
  its chips are the buttons that make it a screen. Accepted for the clear
  button's reason — nothing depends on hitting it, it opens Apple's notice
  about the map data — and matched two ways, because the audit hands the
  finding over in two shapes: by type and name in both languages when the
  element is attached, like the clear button, and by the audit's own sentence
  naming `MKAttributionLabel` when it is not. Measured on one screen and one
  link on 21 Sep 2026: twelve launches attached the element, the next seven
  did not.
- Settings' own footer, *"Kertomasi muistot ovat vain tässä laitteessa."* — and
  this one is worth the sentence it costs. It passed for as long as it did, and
  the moment a row was added above it the audit called the same unchanged
  sentence "partially unsupported", at the ordinary text size only. A finding
  that appears when the list grows is exactly what real clipping looks like, so
  it was screenshotted at both sizes with the new row in place: one line at the
  ordinary size, and the footers around it wrap and grow properly at XXXL.
  Giving it an explicit Dynamic Type font changed nothing, which is the other
  half of the evidence — the metrics are the List's, not our typography's.
- `ContentUnavailableView`'s own Dynamic Type behaviour, which is the system
  view's and not ours — listed string by string rather than by category, so that
  our own Dynamic Type failures still fail.
- Contrast findings the audit cannot attribute to **any element at all**, on
  screens that have a tab bar. This one is a concession to the tool rather than
  a judgement about the app: with no element there is no frame to test and
  nothing to point a fix at. Every one seen was in the same band of pixels as
  the attributable tab-bar cases above.

Two findings turned out to be neither: three "element has no description" on the
typing screen were the keyboard caught mid-animation, and they are gone once the
test waits for it to arrive. Timing, not accessibility — but the only way to
know that was to identify the elements, which is why the failure message prints
type and frame as well as the label.

**The name field nobody had measured.** The proposal rows — where a misheard
name is corrected before it becomes a person (rule 4) — could not be held still
by any launch argument, so no audit had ever opened them. `-screen result` stops
the pipeline exactly there, and the first run found two things at once: the name
field was **110 points wide**, because a `Spacer()` beside it took the room and
the field sized itself to whichever name it happened to arrive with; and it had
no accessibility label at all, because a placeholder is only drawn while a field
is empty and this one always arrives full. The field takes the row now, and it
is called *"Nimi"* whether or not it is empty.

**A second guess worth recording, because it was wrong.** When the reveal's
`Valmis` turned out to be a toolbar button that barely grows, the obvious
conclusion was that the app's other three toolbar `Sulje` buttons — the Tell
screen presented as a sheet — were the same defect waiting to be found. They are
not: the telling sheet is audited now, at both sizes, and it passes with the
toolbar button on it. The shape is not automatically the bug. Measure the screen
rather than the pattern.

**One wrong guess is worth recording.** The record button's resting glow was
blamed for *"Paina ja ala puhua"* first, and reduced from radius 14 to 8 on that
theory. A screenshot showed the caption sitting under the tab bar instead, and
the glow change was reverted — a visual the designer chose should not be altered
on a hypothesis that a screenshot could have tested in a minute.

### The seven that were left

The measurement produced tokens, the tokens were used on the screens being fixed,
and seven places went on using iOS's own colours — because nothing failed. Rule 1
names `.secondary` and `.tertiary` explicitly, and both survived: on the
confirmed-person icon, on the confirmed-relative icon, on the "Henkilö · korjattu"
caption under a proposal, and on the gallery's chevrons. They are `Elder`
tokens now.

The other three were `.green`, which the rule does not name and which is worse
than the orange that started all of this: **1.8:1** against white, carrying
*"Muisto tallennettu"* — the line that tells somebody their telling is safe — the
confirm tick on a proposal, and *"Oikein. Hän oli Aino."* at the end of a round.
`Elder.affirmative` is `#1B7136` at **5.26:1 on the paper**, still unmistakably
green. `#1E7A3A` stood here until the ground became parchment.

None of the three was ever measured, and the reason is worth more than the fix:
**the audit had never opened those screens.** The result screen had no sweep case
at all, and the guessing round's audit stopped at the question and never answered
it. Both are covered now — and the reveal's first audit immediately found a
`Valmis` toolbar button whose text barely grows with Dynamic Type, which is the
third time this app has moved an action out of a toolbar and into a row for
exactly that reason. A colour nobody looks at is a colour nobody measures.

**A disabled control is not a contrast failure.** `Tallenna` on the correction
sheet is dim because it is switched off — the sheet opens with the name already
in the field — and the audit was measuring iOS's own dimming. The contrast
minimum exempts inactive components, so the policy does too: contrast only, and
only where the element really is disabled. What keeps the disabling honest is
`NameCorrectionTests`, which asserts the button stays off until something
changes, rather than this exemption.

**Dark mode is pinned off, decided 23 Aug 2026.** The app had never been
designed for it — the launch screen is parchment, no asset has a dark variant,
the accent is one value for both appearances — and nothing forced light
either, so every phone a grandchild had set to dark got an unmeasured second
appearance of a contrast-driven app. Measured with the same WCAG arithmetic
`ContrastMeter` uses: on dark backgrounds `Elder.destructive` lands at
≈2.6:1 — *"Tyhjennä tämä laite"*, the label a person most needs to read
correctly — and the accent itself at ≈2.7:1, which is every tinted button at
once. So v1 commits to the appearance it was measured in:
`.preferredColorScheme(.light)` at the app root. Dark variants for the whole
Elder system, plus a sweep pass in that appearance, are the designed piece of
work this deliberately is not.

### The band between the two sizes, measured 30 Aug 2026

Every sweep runs a screen twice: at the default size and at
`AccessibilityXXXL`. **`Elder.textFloor` sits between them.** The configuration
it produces — `largerText` on, iOS's own size untouched — is the one an
80-year-old's phone is actually in, and it had never been audited at all.

It surfaced by accident, from a test polluting its own device. A run with the
new `Elder.forgetLargerText()` deliberately switched off left `elder.largerText`
set behind it, and the next two Settings sweeps failed on screens that had
passed minutes earlier. Measured on purpose afterwards:

| Screen | `largerText` on, system default | System `XL`, `largerText` off |
|--------|--------------------------------|-------------------------------|
| Asetukset | 1 — `Arkisto` | clean |
| Asetukset, vain tämä puhelin | 2 — `Arkisto`, `Ota perhe käyttöön` | clean |

Both findings are *"Dynamic Type font sizes are partially unsupported"*. The two
columns render text at the same size and answer differently, so **the trigger is
the floor and not the size**: the audit asks whether text follows the system
setting, and below `xLarge` it does not, because stopping exactly that is what a
floor is. The finding is the mechanism describing itself.

Recorded rather than fixed, because both available fixes are worse than the gap.
Removing the floor takes away the one thing that makes the app readable for the
person it was built for. Adding the category to `AccessibilityPolicy` would
switch off Dynamic Type detection on ordinary rows — and that detection is the
most productive check in the suite. Six screens carry a comment saying they moved
an action out of a toolbar and into a row for exactly this finding, every one of
them after the screen had already been looked at and thought finished.

**Why only those two, established the same day** over nine runs, each changing
one thing and re-measuring.

Three explanations were tried and killed:

- **Not the simulation artefact above.** The `listHeaderAndFooterText` signature
  is a finding that appears at the default size and audits clean at a real
  AccessibilityXXXL. These do not go away: with the floor on, the same two
  report at the default size, at `XL` and at AccessibilityXXXL alike. That is
  the protocol this file demands before anything is added to that set, and this
  fails it — so the set is the wrong home for them.
- **Not the position.** Swapping the sharing section with the help section moved
  the row from y 322 to y 667 and the finding travelled with the row.
- **Not `Text` against `Label`.** Written as a `Label` the row reports the same
  finding with a `Text clipped` added beside it, which is why it is a `Text`.

What it is comes in two halves.

**A row reports when its `Section` is conditionally present.** Deleting
`if session.isLocalByChoice` from around the sharing section — same row, same
construction, same coordinates — silences it. The confirming run was written as
a prediction that could have failed: wrapping the *help* section in the
identical condition should make `Näin tämä toimii` report, a row that had passed
every audit it had ever been in. It did.

This also reconciles with the older note in `SettingsScreen`, which found the
same swap moving the finding onto the help row, if that swap exchanged the rows
inside their sections rather than the sections themselves — the condition would
have stayed where it was while the row moved through it.

**List chrome reports when its section has a header.** Adding one header to the
first section, which had only a footer, made the new header report *and* woke
that footer, silent on every run before it.

The wrapping footer was left as an inference for one day and then measured, and
**the inference was wrong.** Both directions:

| Change | Prediction | Result |
|--------|------------|--------|
| Export footer shortened to one line, 32 pt — the same height as a footer that does report | starts reporting | **stays silent** |
| The reporting footer lengthened until it wrapped to three lines, 86 pt | goes silent | **keeps reporting** |

Height and line count have nothing to do with it. What the two runs leave
standing is narrower and structural: **a footer follows its section, not its own
shape.** The first section's footer is silent while that section has no header
and reports as soon as one is added — at either length. The export section has a
header throughout and its footer never reports — at either length. Two headed
sections behaving differently, with the text ruled out as the difference.

So the chrome half of the rule above is really *a header always reports, and a
footer reports in some headed sections and not others*.

**Which section is which resisted five more single-variable runs.** The two
sections were made structurally identical — one row, a header, a footer, the row
a `Toggle` bound to the same property in both — and they went on disagreeing:

| Ruled out | How |
|-----------|-----|
| The footer's own text, length, line count | Shortened to 32 pt and lengthened to 86 pt, both directions, no change either way |
| Where it sits on screen | Export section moved to the top of the `List`: its footer landed at y 301, the exact y where the other section's footer reports, and stayed silent |
| What its row is | Export row reduced to a plain `Text`, then made a `Toggle` bound to `largerText` — the reporting section's own construction — still silent |
| The section that follows it | Export section moved to sit immediately before the conditional sharing section, the position the reporting footer occupies. Still silent |
| A conditional section existing at all | With `if session.isLocalByChoice` deleted the screen reports one finding, and it is the header |

What is left is not reachable from this code. Two sections written the same way
answer differently, and every property either of them exposes has been swapped
without moving the finding.

**And a footer that does not report costs nothing.** The question worth
answering was why the two that *do* report do, and that one has an answer with a
lever in it. This one is the absence of a finding, chased far enough to say
honestly that it was chased.

**Still not fixed, and now for a better reason than not knowing.** The lever is
a conditional section, and the condition earns its place: `isLocalByChoice` is
what keeps a device-only escape hatch off the screens of families that have no
use for it. An audit finding is not a reason to show a row to people it is not
for.

**And the screen was looked at, which is what settles it.** Everything above is
frames and audit types; the question a person actually has is whether the text
comes out too small or too big. Screenshotted with `largerText` on and off, same
seed, same screen: both reported elements — the `Arkisto` header and the
`Ota perhe käyttöön` row — are drawn in full, one notch larger with the floor on,
nothing clipped, nothing overflowing, the long export footer wrapping to four
lines instead of three. Nothing on that screen is wrong to look at.

So the finding is true about the mechanism and empty about the product: below
`xLarge` the text does not follow the system setting, because that is what the
floor is for. **What is left is the coverage gap and not a defect** — and the
gap is worth naming on its own, because the band nothing measures is the one the
primary user's phone is in, and a real defect appearing there later would be
just as invisible as this non-defect was.

## 16. The memory that was interrupted

§7 says that a quota never rejects a recording: the audio is saved and the
transcription waits, because the audio is irreplaceable and the transcript is
not. Half of that was true. The audio was saved. **Nothing was ever coming for
it.**

This section is not a feature; it is the other half of a promise the app was
already making out loud. The result screen says *"Teksti valmistuu myöhemmin"*
and the memory card says *"Ääni tallessa — teksti valmistuu myöhemmin"*, and
both were describing an intention rather than any code.

### What it actually cost

Three separate failures, pointing the same way.

| # | What happened | Why it mattered |
|---|---|---|
| 1 | Nothing re-read `isAwaitingTranscription`. It was displayed in three places and acted on in none | The recording stayed a blank card for good. No body means no mentions, no date, no follow-up questions, no person cards, no guessing round — one moment without signal cost that memory *everything the pipeline makes of a memory*, permanently |
| 2 | `sync.ts` refused any memory whose `body` was empty, and the client cleared the whole pushed payload from its outbox regardless | The row never reached the server and was never retried. The recording lived on **one phone**. Its audio did reach R2 and sat there orphaned, referenced by nothing |
| 3 | "Kirjoita se itse" wrote a *second* memory beside the first | One telling became a silent recording next to a voice-less text, and neither looked like the whole thing |

Failure 2 is the one worth remembering. It was silent in both directions: the
push returned 200, the client believed it, and the only evidence was a memory
that quietly existed nowhere else. A family's archive is not supposed to be able
to lose a memory to a successful request.

### The rules

- **The row is stored without text.** A memory with audio and no body is a
  legitimate state and now says so in the schema's terms. A row with neither
  text nor audio is still nothing, and is refused.
- **An empty body never overwrites a real one.** The Keychain identity syncs
  across the user's devices, so their other phone pushes as the same author and
  the author check would not have stopped it from unwriting the transcript.
  `raw_transcript` is sticky for the same reason and for rule 3's.
- **A row the server would refuse is not offered for push.** It stays in the
  outbox instead of being sent and forgotten, and goes on the next round once
  its audio has a key — normally the same round, because media is uploaded
  before the push.
- **Only the author's device finishes its own recordings.** The server accepts a
  body only from the memory's author, so any other member transcribing it would
  spend the family's AI minutes on an update that is then refused.
- **The ladder is read, never written.** An outage is ours and not the teller's,
  and it must not cost them a level (§12).
- **Never with stubs.** The stub transcriber returns a canned sample of Finnish
  speech, which is right to develop a UI against and would be a forgery in an
  archive.

### Where it runs

On launch, on returning to the foreground, and when the family's entitlement
changes. Those are the three moments the two things that stop a transcription —
no network and no minutes — are most likely to have changed. The last one is
also the point of §9's model made concrete: **the memory the quota interrupted
is usually the exact reason somebody bought**, and it should not have to wait
for the next launch.

### When the recording is the problem

The first version of this retried everything, forever, and stopped the whole
round at the first failure. Both halves were wrong, and in the same way: they
assumed a failure says something about the *moment*.

Two failures say something about the **recording** instead, and neither is
hypothetical. A button pressed with nothing said produces a transcript with no
words in it. Audio the hallucination guard refuses (§7 of the transcribe path)
produces an error every time it is sent. Neither will ever succeed, and each
attempt is charged for whether or not any words come back.

Retrying those forever cost two things. **Money**, on every launch, for as long
as the memory existed. And worse, **the memories behind it**: the queue is
oldest first, so one recording that could never be transcribed stood in front of
every later one and none of them was ever reached.

So a failure is classified once and the answer decides both questions:

| The failure is about | Examples | The round | The recording's tally |
|---|---|---|---|
| the moment | no network, 401, quota, 429 | stops — everything else meets the same wall | untouched; none of it was its fault |
| the recording | no words in the answer, audio refused, 5xx | goes on to the next one | counted |

**Three counted failures, and the app asks again a day later — then two days
after that, four, eight, sixteen, and every thirty days for as long as the
memory exists.** Until 26 Sep 2026 the third failure was the last, and that was
right for the two failures the rule was written for and wrong for the one it
cannot tell from them. A Worker whose provider has run out of credit answers
the same 502 as the hallucination guard (`failure()` in `worker.ts`, rule 9),
on every attempt, for as long as the outage lasts; three rounds of the catch-up
inside one — a launch, a return to the foreground — retired every memory told
during it, on phones that keep the audio for exactly this case. That outage
happened, on an account that had run down to a few cents. So the tally sets a
wait now rather than an end: `TranscriptionAttempts.wait(afterFailure:)` is
nothing before the third failure, a day after it, doubling, never more than
thirty days, timed from the last failure, and `isDue` is what the catch-up asks
before it uploads. A recording that will never transcribe costs three attempts
on the day it is told, four more in its first month and one a month after
that, instead of three and nothing; and a tally the old rule left behind
carries no timestamp and reads as due at once, so the outage's memories are the
first thing the next round picks up. The count is device-local in
`UserDefaults`, for the same reason `comfort` is (§12): it describes this
phone's attempts, not a fact about the family's archive, and a count that synced
would let one phone's bad afternoon slow every other phone down.

Slowing down on the text is not giving up on the recording. The audio is kept,
uploaded and exported exactly as before — and from the third failure the memory
card stops saying *"teksti valmistuu myöhemmin"*, because a promise the app may
take a month to keep is the same false promise this whole section exists to
remove. *"Tekstiä ei saatu tästä nauhoituksesta"* is true until the day it is
not, and on that day the row changes by itself.

Counting a 5xx as the recording's fault stays, and it is drawn there on
purpose: the one 5xx this app raises deliberately is permanent for that audio,
and an uncounted permanent failure would be paid for on every launch. What
changed is the price of counting wrong. A Worker that is genuinely broken used
to cost a transcript; it now costs a day.

### What degrades, and what does not

If transcription succeeds but extraction does not, **the memory lands in the
teller's own words** rather than being thrown away and re-transcribed later.
Transcription costs the family real minutes; extraction is text, a fraction of a
cent, and deliberately unmetered (§7). So a transcript that has been paid for is
never discarded because the cheap half failed. Structure is what degrades — not
the telling.

The same rule holds where the telling actually happens, which it did not for a
while. The Tell screen answered a failed extraction with `.failed`, so neither
`save` nor `saveAudioOnly` ran: the recording was left in the temporary
directory with `persistAudio` never called, and "Voit yrittää uudelleen" meant
saying the whole memory over again. Rule 3 says the original audio is always
kept, and this was the one branch that did not keep it — while the quota and the
network, which fail far more often, both already did. It takes the verbatim
result now, and the result screen says out loud that the organising did not
happen: without that, a memory with no names and no questions on it reads as one
the model read and found nobody in, which is a different and untrue thing.

The memory's home subject is not re-chosen when the text arrives, only
described. It has been sitting in the archive under that subject and somebody
may have been looking at it; `describe` fills empty fields only, so a title
written by hand in the meantime survives. That is also why the subject is
created **untitled**: a placeholder written before anything had been read would
have been filled in by nothing, and become permanent.

### Verified

The upsert rules against real SQLite on `schema.sql`: an audio-only row is
stored, a late transcript fills in both `body` and `raw_transcript`, a stale
push from the author's other device cannot unwrite either, and another member
still cannot edit what somebody else told. End to end in the simulator with
`-defer once` (docs/SETUP.md): the recording is saved without text, the next
launch finishes it, and the memory comes back with its own audio intact, the
person it names, a dated subject and three follow-up questions.

The live path's version of the same failure with `-defer structure`, where
transcription works and every extraction fails. `OrganisingFailureTests` checks
what the archive holds afterwards rather than how a screen looks: the telling is
on the result screen and the memory is in the gallery. It was run against the
old behaviour first and fails there on all four of its assertions — a test that
would have passed either way proves nothing.

The giving-up half with `-defer silence`, which fails every attempt the way an
empty transcript does. Across four launches the tally reads 1, 2, 3 — and then 3
again: the fourth launch does not touch it, because by then the app has stopped
asking.

### No removal is owed

CLAUDE.md requires a removal for every addition. Nothing was added to the
product: §7 specified this behaviour before any of it was written, and what
existed was half of it. The one genuinely new thing is a DEBUG launch argument,
which is developer scaffolding rather than scope — and it exists because this is
the only path in the app whose whole point is what happens *after* an outage
nobody can schedule.

## 17. The name that was heard wrong

The measurement this app was built on says the recognition gets **68 % of proper
nouns right** (`backend/wrangler.jsonc`, chosen by `scripts/asr-bench.mjs`). One
name in three arrives wrong, and the family tree is built out of names.

That was known and answered: the Tell screen asks the teller to check the names
while they still remember what they said, and a correction there re-runs
extraction so the memory's text is corrected too — Finnish inflection means a
string replacement never matches "Skotlannissa". It is the right moment and the
answer is good.

**It was also the only moment.** The correction screen goes past in seconds, an
interview loop deliberately stacks its proposals up until the loop ends, and the
person most likely to notice that *Sotkamo* has become *Skotlanti* is a
grandchild who is not in the room. A name missed there was permanent: a wrong
person on the people list, in the export, and in the tree.

(The stacking itself was an intention this document stated while the code did
something narrower — found 23 Aug 2026: `save` *replaced* the list every round,
so the loop-end screen checked only the last round's names and everyone earlier
skipped straight to the person-list backstop. It accumulates now, deduplicated
by id, and `testInterviewRoundsAllReachTheNameCheck` holds a name from each
round on the final screen.)

Worse, it could become *fact*. A correct guess in a round confirms the person
(§13), and a family member who knows perfectly well who was meant will happily
recognise them under a misheard name. The archive would then hold a confirmed
wrong person, which is precisely the failure rule 4 exists to prevent — and it
had no way back out.

### What it is

A pencil on the person's and the place's card, and a sheet with the name in it.
Nothing else: photos and events are titled by the app out of a place and a year,
so their names were never heard by anybody.

The write is `MemoryStore.rename`, unchanged and already carrying the hard part
— if the corrected name is one the family already has, the two cards merge, and
the merged one stays as a tombstone with a forwarding address so that nothing
anywhere points at nothing (§2.5). The sheet says so before the tap rather than
after it, because a merge that arrives as a surprise looks like data loss.

**The memories' text is left alone**, and the sheet says that too. Re-writing
every memory that names the person would need the model and the family's
minutes, and the right name on the card matters more than the wording inside a
story — the same trade the correction at telling time already makes when
re-extraction fails.

This is not new machinery. Sync has had a conflict rule for *"a subject renamed
on two devices"* since §3 was written; until now the app could not produce that
situation outside those few seconds.

### The pairing

**`subject.blurhash` is out.** It has been in the schema from the first day as a
placeholder colour while a photo loads, and nothing has ever written it or read
it. The grid shows a grey rectangle instead, which is what it has always shown.
A column carrying an intention nothing implements is the same species of thing
as a sentence promising a rate limit that was never written — and this document
has spent enough of today on those.

### Verified

By pressing the buttons, in `NameCorrectionTests`: the card opens, the sheet
opens with the name already in it, what is typed reaches the card's title, and
Tallenna stays disabled while there is nothing to save. The audit covers the
sheet at the default size and at the largest one, which is what a text field on
a sheet most needs.
---

## 18. Places on a map — the three columns and what they cannot promise

A place subject has always been a name somebody said out loud: `subject` has had
`kind = 'place'` from the first schema, extraction has emitted place mentions
from the first prompt, and rule 3 of that prompt already says a place belongs in
the list only *"if it could be pointed to on a map by name"*. What was missing
was the point itself.

`subject` now carries three more columns — `lat`, `lon`, `geo_precision` — filled
in by `PlaceResolver` on the device. **There was no map screen until 21 Sep
2026, and that was deliberate**: the columns and the lookup cost an hour, a map
costs a phase (see PLAN.md §5), and the archive that was being recorded that
week is the one a map would eventually draw. Data first, so that the family's
places accumulate while the decision is still open. A place is already openable
like any other subject (§8).

**Since 21 Sep 2026 there is one, at the founder's request, and it is a third
door to the same card.** `PlacesMapScreen` draws every confirmed place with a
coordinate on one map, by the rule the place card already follows — a pin for
`exact`, a circle a third of the span for `town` and `region`, nothing for
`unknown` — and puts a chip on each with the name and the memory count. The
chip is a `NavigationLink` to the same `SubjectDetailScreen` the Paikat list
opens. The map is pushed on the album's own stack from a *"Näytä kartalla"*
button under the Paikat heading, shown only when there is something to draw
and not while searching — and since 25 Sep 2026 from a map icon in the
album's top bar too, in every album including an empty one, because a door
that appears only once there are places is a door nobody learns — so the
back chevron walks back through map and card alike and `isReturningFromCard`
keeps reading the path (`GalleryScreen`'s `path` became a `NavigationPath`
for it). Nothing is stored, fetched or
extracted for the screen: zero Worker rows, zero columns. The Paikat list
stays as the way in for VoiceOver and for every place without a coordinate —
nine of the ten in production on the day the map was built, read from the
13 Sep export. `testPlacesMap` audits it on the film-week archive, the one
seeded launch with three places, at both text sizes; `PlacesMapTests`
follows a chip through to the card. The phase §5 priced a map at was the
phase of a map that had to be designed; this one reuses a drawing rule, a
stack and a card, and took a session.

**At the accessibility text sizes the chips give way to the album's own rows
under a map that does not pan**, and that was measured rather than designed.
On the film-week archive at the largest size a chip is 215–290 pt wide on a
402 pt screen, Sulkava's lay across Savonlinna's at every framing tried, and
MapKit's annotation container leaves a chip that crosses the edge of the map
out of the accessibility tree — Savonlinna's was absent at 1.5, 2.0 and 2.5
times the places' spread, Puumala's at 1.5 — so VoiceOver was offered one
place of three and zooming out cannot fix what zooming out causes. The rows
are `SubjectRow`, the same rows as the Paikat list, under a 300 pt map that
is one element and does not take the drag, for the place card's reason. Two
smaller findings from the same evening: the chips' words are drawn at their
own size (`.fixedSize()`), because without it the audit reported every chip
as clipped at the default size and the finding was indifferent to everything
else that was varied, six variants on one build; and MapKit's own legal link,
about 50 × 11 pt in the map's corner, is forgiven in `AccessibilityPolicy`
the way the search field's clear button is (§15). **§5's condition that a browsable map
owes its own removal is still owed**, and that row says so.

**Since 25 Sep 2026 the same map can be an aerial photograph**, from a globe in
its top bar. It is `.hybrid` rather than `.imagery`, so that the roads and the
villages keep their names over it — a yard is recognised from above and found
by the road that leads to it — and the choice is kept on the phone as
`map.aerial` and never synced, because it is how one person likes to look and
not something the family knows. Over the photograph the circles gain a cream
line under their wax and the chips a cream edge, and that was measured rather
than assumed: a shape against a ground nobody can predict is the one contrast
the palette cannot state in advance, and a circle is drawn by MapKit rather
than being an element on screen, so the audit has nothing of it to measure. On
the film-week archive at the default size, the ground in a 4 pt band just
outside each of the three circles had a median relative luminance of about
0.12. Wax against it measured 1.03–1.07:1 at the median and reached 3:1 on
none of those pixels; cream measured 5.75–6.00:1 and reached 3:1 on
97.8–99.4 % of them, the rest being the palest ground in the band. The street
map turns this round — wax 4.09:1 at the median and at least 3:1 on 99.1–100 %
of the same band, cream 1.37:1 — which is why the cream line is drawn over the
photograph and nowhere else. `testPlacesMapAerial` audits the screen at both
sizes.

A single place keeps the map on its own card, `PlaceMapCard` (below). The
second one, the sheet that card opened from 19 Sep 2026 so that the point could
be moved by hand, went on 25 Sep: the card opens this map instead, and the point
is moved on it (*The one answer a gazetteer cannot give*, below).

**Confirmed places only, since 12 Sep 2026.** `placesAwaitingCoordinates`
skips a place nobody has vouched for. A name the extraction heard is a guess
until somebody confirms it, and a coordinate under a guess is the guess drawn
on a map — rule 4's mistake, one step further along. The lookup waits for the
confirmation and the next sweep picks the place up; nothing on screen waits
for it either way.

**Since 10 Sep 2026 it also has a position on its own card**, and the
distinction is the whole of why that was allowed. `PlaceMapCard` draws the
stored coordinate on the subject that owns it; it is not a screen of places and
you cannot browse to it. Native MapKit, so no key, no account, no quota — and
**no location permission either**, because it renders a coordinate the archive
already holds and never asks where the phone is.

**Withdrawn on 12 Sep 2026 and back on the 13th.** Decision 9.2 of the
first-run plan took the map out of v1 with the rest of *"yksi kerronta, yksi
muisto"*, as the cheapest of three options; the next day the cost showed —
the film's take of this card was already final — and the rule itself allows
the map: the lookup now waits for a person's confirmation (above), so the
card draws nothing the family has not vouched for. What stays withdrawn is
the guess: an unconfirmed place gets no lookup, no card and no map.

This paragraph used to end *"what it does not have is a position on anything"*,
which was true for three weeks and is the sentence a reader would have trusted.
Corrected here rather than deleted, because the reason it stopped being true is
the argument the rest of this section makes: **precision decides what is
drawn.** A pin only for `exact`; a circle at the right scale for `town` and
`region`; nothing at all for `unknown`, because an empty map of the wrong sea
looks like an answer. `GeoPrecision.deservesAPin` and `mapSpanMetres` hold the
numbers so they are a fact about the precision rather than a choice inside a
view, and `scripts/place-map-check.swift` asserts them without a simulator or a
network.

*Nothing at all* was, until 19 Sep 2026, nothing inside a `Section` that was
opened anyway: `SubjectDetailScreen` asked whether a coordinate existed, and
`PlaceMapCard` then asked whether it could be drawn, so an `unknown` left a
band of empty paper between the place's name and its date. The screen now asks
the same question the card does — `place?.precision.mapSpanMetres != nil` — and
the row is absent rather than blank. Two guards for one rule is how the
duplication reads; the alternative is a view that draws an invisible map, and
the check above is written against the precision either way.

### Why the device and not the Worker

`MKLocalSearch`, biased at a box covering Finland and Karelia. No API key, no
quota to meter, no Worker round trip, and **no location permission** — looking up
a name is not asking where the phone is, so `Info.plist` gains nothing and the
80-year-old is asked nothing. What leaves the device is the place name and
nothing else: not the memory, not the transcript, not who told it. Since
25 Sep 2026 the family's map has a search of its own, *"Etsi nimellä"*, and
what it sends is what somebody typed, under the same bias and the same
boundary — the family's map never asks where the phone is either, and
somebody who wants their own yard on it finds it by name or taps it.

The lookup lives in `PlaceLookup`, apart from the resolver that walks the
archive, so that both tables below can be re-measured against the shipping code:

```
scripts/geo-check.swift          # the command is in CLAUDE.md
```

Every claim in this section is a claim about somebody else's gazetteer. It can
stop being true without a line of this repo changing, and a document that cannot
be caught being wrong goes on being believed — the failure mode §1 warns about.
Both tables below were produced by that script, and it exits non-zero when one
of them stops holding.

### Why the precision column

The same reason `date_precision` exists. The lookup answers at wildly different
scales for the same kind of query, and flattening that would be inventing
accuracy:

| Told | Resolved | Precision |
|------|----------|-----------|
| `Puumala` | Puumala, Etelä-Savo | `town` |
| `Sortavala` | Sortavala, Karelia, **Russia** | `town` |
| `Viipuri` | Vyborg, Leningrad Oblast | `town` |
| `Lappi` | Lapland, the whole province | `region` |
| `Mannerheimintie 1, Helsinki` | the address | `exact` |

Karelian places resolve correctly and across the border, which matters for this
audience more than anything else on the list.

### What it cannot promise, measured

The lookup **always answers**, and a confident wrong answer is indistinguishable
from a right one:

| Told | Resolved | Why it is wrong |
|------|----------|-----------------|
| `Karjala` | a village in Mynämäki, 60.838, 22.000 | Karelia the region is what a grandmother means; the village is a real place with the same name, returned as a single unambiguous result |
| `mummola` | Mummola, Kodavere, **Estonia** | a real hamlet. The extraction's proper-noun rule keeps generic words out of mentions — this is what happens when one slips through |

No cheap rule separates these from the good ones. Result count does not: every
name above returned exactly one result. Name equality does not either — it would
accept `Mummola` and reject `Viipuri → Vyborg`, which is the one answer on the
list that is most worth having.

So a stored coordinate is **a proposal, not a fact** — rule 4, applied to a
machine lookup instead of a machine-heard name. Nothing in the app confirms
one, and since 10 Sep 2026 `PlaceMapCard` draws one anyway. **What decides the
shape is precision, not confirmation**: `deservesAPin` is `precision ==
.exact`, so an exact hit gets a `Marker` and anything vaguer a `MapCircle`
sized to its span.

**The requirement above is unimplemented — and, measured 11 Sep 2026,
currently unreachable.** `.exact` needs `placemark.thoroughfare`, a street,
and a name somebody says out loud does not come back as one. Sixteen farm,
house and hamlet names through the shipping `PlaceLookup` — `Koivula`,
`Mäkelä`, `Rantala`, `Mummola`, `Karjala` among them — returned sixteen
`town`, no thoroughfare, and not one pin. **The table of wrong answers above
is a table of circles.** The only `.exact` in this section is `Mannerheimintie
1, Helsinki`, which is a street because the speaker said a street.

So rule 5 is doing rule 4's work here, and it is doing it by accident rather
than by design — which is the reason to check it rather than lean on it.
`geo-check.swift` carries the measurement as its fourth claim: twelve names
said out loud, not one of them a street. Whoever changes `precision(of:)`, or
adds `.pointOfInterest` to `resultTypes` so that a hairdresser named Koivula
can win the query, turns that claim red — and CLAUDE.md already sends anybody
who touches `PlaceLookup.swift` to run it, which is as close to automatic as a
check that costs a network round trip gets here. What the check buys is not the
rule; it is that the day the rule starts mattering is a day somebody is told.

### The one answer a gazetteer cannot give — 19 Sep 2026

This section said until now that the confirmation it asks for, *"from a human
who knows which Karjala it was"*, does not exist, because the judgement is
about the coordinate and `PlaceHint` has no field to hold one. That was the
wrong way round. The judgement needs no field of its own: the point **is** the
judgement, once a person puts it somewhere.

So the card's map is a control. Tapping it opens `PlacePinSheet`, a full map
with a mark fixed in the middle; the map moves under the mark, and saving
writes the centre back as `exact`. The mark is still and the map moves because
a dragged pin is a pin under a finger — the one thing you cannot see while you
are placing it — and because dragging accurately is the gesture this app's user
has least of. The words in the card's corner, *"Merkitse tarkka paikka"* over a
circle and *"Siirrä paikkaa kartalla"* over a point, are what keeps the control
from being a secret.

**Since 25 Sep 2026 the card's map opens the family's map instead**, centred
on the place, and the sheet is gone. The founder's report was that the land
around a point could not be looked at without the point going with it — the
sheet was the only larger map a place had, so every look was also an edit. On
the family's map the camera is only a camera, and *"Muuta sijaintia"* in the
panel under it turns that same map into the editor: the panel asks for a tap,
and the mark goes where the finger was. A drag still only moves the map, which
keeps what the fixed mark was right about — a mark under a finger is the one
thing nobody can see while placing it, and dragging accurately is the gesture
this app's user has least of — while giving back the pan the sheet took away.
A tap on a map showing more than five kilometres across is followed by a
closer look, because at a municipality's scale a fingertip is a kilometre wide
and the miss should be seen while it can still be tapped again. The card's
corner now says where its own tap goes, *"Avaa kartta"*, and both phrases above
left the tables with the sheet. A confirmed place with nothing to draw says
*"Merkitse kartalle"* where its map would be, and opens the same editor
straight away, with the search open on its name (below).

**Nothing is saved until somebody has tapped**, measured in metres against the
point the place already has. That guard is rule 5 rather than tidiness: the
stored answer for *Puumala* is a municipality, and writing it back as `exact`
because somebody opened the editor and pressed its prominent button turns
fourteen kilometres of parish into a claim about one farmyard. Only a person
can make a point exact, and the tap is how they say so. *"Suunnilleen tällä
seudulla"* goes the other way without one, because claiming less needs no
evidence. The same panel takes a point off the map (*"Poista sijainti"*,
stored as `.unknown` under the person's word, so that no lookup puts it back)
and vouches for a point the gazetteer found as it stands (*"Sijainti on
oikein"*, the same word with nothing moved). `PlacePinTests` drives each of
these, and a drag that must move nothing.

**Two limits, both deliberate for v1.** A hand-placed point is
indistinguishable from a street address the gazetteer resolved, because the
archive holds one point per place and no field for who put it there; and
correcting the place's *name* still clears it, since the coordinates answer the
title and `MemoryStore.rename` cannot tell a point somebody stood on from a
point somebody looked up. What is not left to chance is the family's point
being replaced by a machine's: a stored `exact` is not displaced by a coarser
push under the same title (see Sync below).

**Both were lifted on 25 Sep 2026, by the field this paragraph said was
missing.** A point somebody places now carries who and when —
`geo_confirmed_by` and `geo_confirmed_at` on the row; `confirmedByID`,
`confirmedByName` and `confirmedAt` on `PlaceHint`, optional all three for
rule 10 — and the panel under the family's map says the name: *"Tarkka kohta.
Vahvisti Aino."* A corrected title keeps such a point on both sides
(`MemoryStore.rename`, the `CASE` in `sync.ts`), a merge carries it to the card
that stays, and only a newer word moves it. Sync below has the rules and what
checks them.

**VoiceOver got the screen and not the task until 25 Sep 2026.** The map was
one labelled element with a hint, the buttons were ordinary buttons, and
somebody who could not see the map could read what the screen was for and
leave the stored point as it was. Placing a point inside a landscape is visual
work, and four "move north" actions over ground nothing can name would be the
appearance of an answer rather than one — so the map in the editor is still
one element. What changed is a way in that is not visual. *"Etsi nimellä"* in
the editor's panel opens `PlaceSearchSheet`, where the answers are rows of
words: a name in bold and the line that tells two of the same name apart.
Choosing one proposes the point rather than saving it, and the panel names
the answer the mark stands on (*"Hakutulos: Koivulantie 12, 52200 Puumala"*),
which is the one sentence that tells somebody who cannot see the map what
*"Tallenna"* would save. The card's *"Merkitse kartalle"* arrives with the
search already open on the place's name, because a place with nowhere to be
drawn gives the map nothing to tap beside, and this time every answer is
shown rather than the first.

**An answer keeps the precision it came with**, which is the tap rule of the
paragraph above applied to the gazetteer. A street address the search found is
a spot and saves as one; a municipality or a province is a circle of its own
size under either row, and *"Tarkka kohta"* cannot turn it into a spot until a
tap says where in it. *"Suunnilleen tällä seudulla"* stores a province as a
province rather than shrinking it to a parish. A tap after an answer is a tap,
and the answer's name leaves the panel with it. A search that does not get
through answers differently from one that found nothing — MapKit reports
*nothing found* as an error of its own, `MKError.placemarkNotFound`, and that
one error is read as the empty list — because the two ask the person for
different things, and both sentences say that the map still takes a tap.
`-placeSearch stub` and `-placeSearch failing` give the tests three fixed
answers and a failure, since a real search needs a network and answers
differently from one day to the next; `PlacePinTests` drives each rule.

The affordance is inside the card rather than in a row beneath it, and that too
was measured. As a row it pushed the card's last memory sixty points down onto
the tab bar's edge, and `performAccessibilityAudit` then reported that text as
not supporting Dynamic Type — three runs red, against a green run of the same
test without the row on the same simulator and the same commit. An overlay
costs no height.

**The subject above the coordinate does carry a confirmation, though, and
nothing was reading it.** Every place the extraction hears is created
`confirmed: false`, exactly as a person is — `extract.ts` proposes `person`
and `place` and nothing else — and the Tell result offers it in the same
orange row, where it can be confirmed or corrected. After that one moment the
state was invisible: `SubjectRow` drew `SubjectAvatar`, which is where the
badge lives, only for `.person`, so a place nobody had vouched for looked
exactly like one somebody had, and its card drew a map either way.

That was not decided. It fell out of a decision about **avatars** — an initial
tells two people apart on a list of five where a pin only says what kind of
row it is — and the badge happened to live inside the thing that was switched
off. Corrected 12 Sep 2026: the badge is on the symbol as well, on both rows
that carry one, and `SubjectRow` says *"Ehdotus — vahvista paikka"* underneath
it. Shape and words, which is what `SubjectAvatar`'s own contract asks for and
what rule 1 means by not resting on colour.

### When it runs

At launch and on every return to the foreground, after sync — a place another
device has already resolved arrives with the pull, and looking it up again would
be work for an answer we now have. Telling must never wait on a lookup.

**And, since 19 Sep 2026, when a place card is opened.** The sweep alone was
the whole of it until then, and what that cost was reported rather than
reasoned about: a place named in a telling, confirmed in the same telling, and
opened from Albumi a minute later had a card and no map, because the only two
moments that could resolve it were both in the past. Leaving the app and coming
back fixed it, which is not an instruction anybody has. `PlaceResolver.resolve`
answers the one subject the screen is showing — unpaced and not held back by a
sweep in progress, since it is a single request and the only one anybody is
waiting for — and `SubjectDetailScreen` asks for it in a `task`. A seeded
archive still asks for nothing: the fixture guard that kept the demo family's
*"Puumala"* out of every UI test run is now a property both paths read.

It also covers the case a confirmation hook never would: a place confirmed on a
grandchild's phone arrives here through the pull with its title and no point,
and the device that opens the card is the device that looks it up.

### Sync

The coordinates follow the title, because they are the answer to it. A device
that has not looked a name up sends null and cannot wipe what another device
resolved; a device that *corrects* the title clears them on both sides, and the
next sweep looks the new name up. A tombstone is never resolved, whether it was
left by a merge or by a rejection (§3) — neither is its own place any more, and
looking one up would spend a request on a name the family has taken back. See
the `CASE` in `push()` in `backend/src/sync.ts`, and `MemoryStore.rename` for the
same rule on the client.

**And since 19 Sep 2026 a coarser point never displaces an exact one under the
same title.** A person can now place the mark by hand, which stores `exact`;
every other phone in the family is still holding the municipality the gazetteer
answered with and pushes it with the next thing anybody changes about that
place — a date, a confirmation. Without the rule the family's own point would
be replaced by the circle it was placed to correct, and nothing on any screen
would say so. Placing the mark again is `exact` over `exact`, so a correction
of a correction still works.

**Since 25 Sep 2026 a point somebody placed is their word, and it follows the
colours' rule instead.** A point with a member and a moment on it is not an
answer to the title, so both rules above come second. The first question is
whether the push carries a newer word, which then moves the point whole; the
second is whether the row already holds one, which nothing else moves — not a
corrected title, not a gazetteer, not an older build pushing a bare `exact`.
`unknown` under a word is how a place is taken off the map, and it holds for
the same reason; nothing looks it up again either, because
`placesAwaitingCoordinates` only offers a place with no point at all.

A word travels like a colouring: under the pusher's own member id, and with a
moment capped at the server's clock, so a phone whose clock runs fast cannot
hold a place for years. The one difference is that a phone may repeat somebody
else's word. It has to, because every phone pushes its whole row and a merge
carries the word to the card that stays, when that card has none of its own
(`MemoryStore.rename`) — but only a word the server already holds, on the
same place or on one merged into it, and then with the point from the row
that proves it. A pair on any other place is not taken as a word
at all, and the point under it is kept as what the server can vouch for, a
lookup's answer. On the phone, a pull that carries no word keeps the one this
phone has (`Subject.withPlace(from:)`), because a Worker that has not been
redeployed sends none, and its own rule would hand back a point the family had
just taken off the map.

Every one of those rules is silent when broken: memories still sync, places
still open, and the only evidence would be a point on the family's map
standing somewhere other than where somebody put it. So they are checked through the running Worker rather than asserted —
`scripts/place-sync-check.mjs`, twenty-three checks, no AI call and no credits
spent. The check has been checked three times. With the `CASE` replaced by a
plain `COALESCE`, case 3 fails and the script exits non-zero. Against a Worker
built from the commit before 19 Sep's rule, the older cases pass and *"a
looked-up circle does not displace a point the family placed by hand"* fails.
And against one from the commit before the placed word (25 Sep 2026), the
first eight pass and fourteen of the fifteen new ones fail; the one that
passes is a later word moving the point, which exact over exact did already.

### What the columns tell the server — a decided leak

The three columns are plaintext in D1, beside a title that lever 3 seals. That
is a real leak and it was decided, not overlooked (24 Aug 2026, the review's
finding M19): a database dump shows a coordinate pair whose name it cannot
read, which for a family's most-told places — the summer cottage, the home
village — is the name in different clothes.

It stays for v1 because sealing it costs more than the honesty it buys today:

- The Worker's *"rubbish is refused"* check (`coordinate(lat, 90)` in
  `sync.ts`, case 4 of `place-sync-check.mjs`) reads the numbers. Sealed
  blobs would move that guarantee into the client — the one place this
  section says silent rules must not live alone. That is the real cost; the
  storage itself would not even need a migration, since SQLite's `REAL` is
  affinity rather than a constraint and stores a text blob as it is.
- The rename rule itself would survive: it compares titles, which are already
  deterministic ciphertext. So the v1.1 route is known and small — seal the
  pair as one opaque blob, keep null as the only server-visible state — and it
  is recorded here so it is a decision to revisit rather than a discovery to
  make twice.
- Only `PlaceMapCard` and `PlacesMapScreen` read a coordinate on screen,
  and both read the local archive rather than D1, so what accumulates before
  v1.1 is bounded and re-sealable by the same sweep that resolved it.

`InviteShare`'s doc comment beside the invite text already says the smaller
thing lever 3 promises about the key; this paragraph is where the whole of
what a dump yields is written down. Sealed: memory bodies, raw transcripts,
subject titles, question text, and the R2 bytes. In the clear: the family's
own name and its members' display names, timestamps and the carefully kept
dates with their precision (rule 5), subject kinds, memory sources and audio
lengths, sequence numbers, relationships, the mention graph — which memory
names which subject — and points for places, with who placed them and when.
Anyone weighing the app against that list is weighing the truth.

**Corrected 9 Sep 2026, in one claim and several omissions.** The mention graph
does *not* travel "with the model's confidence", as this paragraph said until
now. `mention.confidence` is declared in the schema and written by nothing: the
push binds `(memory_id, subject_id)` and stops. `relation.confidence` is dead
in the same way. Every synced mention and relation row carries a NULL there, so
what a dump yields is the edge and not the model's opinion of it — which is
less than the paragraph promised, in the direction that favours the family.

Also in the clear, and absent from the list above: a question's `level` and
`status` (its text is sealed, its place on the ladder is not), the `author_id`
on questions and memories, `subject.merged_into` — which is the merge graph, so
a dump shows that two cards were decided to be one person even though it cannot
read either name — and `subject.r2_key`, which is the family id and a UUID.
None of them is a surprise given the design; the point of this paragraph is
that the list is complete, and it was not.

**Three more since 25 Sep 2026** (§11): `prompt_question.target_member`, who a
question is asked of, and `answered_memory_id`, the telling that answered it —
both in the schema from the first day and empty until then — and the
`push_token` table, one APNs device token per phone that has let the app notify
it, beside the member it belongs to. The notifications themselves carry no
question and no telling; the asker's display name, already on the list, is the
most one says.

## 19. The telling that was not meant

Two ways out were missing, and they are the same one seen from either side of the
save.

**While recording.** The recording screen had one button and it both stopped and
saved. A false start, the wrong story, somebody walking into the room — the only
answer the app had was to finish the telling, wait for it to be transcribed, and
then live with it. There is now a quiet second action beside the big button, and
it asks before it does anything. The recorder keeps running while it asks: saying
no has to be the cheap answer, because it is the one somebody who tapped by
mistake will choose.

**A third way out existed and was unguarded**, found 23 Aug 2026: the Tell
screen presented as a sheet — from a photo or person card, or from an
idle-screen question about another subject — carried a "Sulje" both presenters
attached themselves, unguarded in every phase, and nothing disabled the swipe.
One tap in the middle of a recording deallocated the model and the running
recorder: telling gone, no question asked, past the exact guard the hidden tab
bar and the confirmed discard put on the other exits. The button is now the
screen's own (`onClose`), because only the screen knows which phases an exit
destroys: a running recording gets the same "Hylätäänkö tämä kertominen?" the
in-screen discard uses, a typed draft is let go the way its own Peruuta lets
it go, an interview between rounds ends the way "Riittää tältä erää" ends it,
and the swipe is disabled in exactly the two phases where it loses words —
transcribing and organizing finish on their own after a dismissal, so they
stay dismissable.

**And the world can end a telling from outside.** A phone call, an alarm, the
screen auto-locking two minutes into a five-minute story: the system pauses
`AVAudioRecorder`, and everything on screen — the waveform that is the only
"the device can hear you" feedback, the timer, "Kuuntelen" — froze while
looking exactly like a working microphone listening to a quiet room. The
elder kept talking to a dead recorder, and pressing stop saved the partial
file as the whole memory with nothing to say anything was lost. Three
mechanisms close it, all in `AudioRecorder`: the idle timer is held while
recording, so auto-lock — the commonest cause — cannot happen at all; the
interruption notification is observed, resuming into the same file when the
call ends with permission to resume, and finishing-with-what-was-captured
when it does not; and a watchdog in the metering tick treats two seconds of
a system-paused recorder outside any signalled interruption as a cut, so
even the interruption iOS never announces ends as a saved memory instead of
a frozen screen. A cut finishes exactly as if stop had been pressed — the
words already said are kept, which is rule 3 applied to the half of a
telling that survived.

**After saving.** Nothing in the app removed a memory. The result screen — the one
moment when the app knows for certain whose telling it is looking at — now offers
it, behind a confirmation. It takes with it what only that telling explains: the
people it proposed, when nobody confirmed them and no other memory names them,
and the subject free dictation created to hold it, when the telling was all it
ever held. Never a photo or a person the family already had. The question it
answered goes back to being open, because it was answered by something that is no
longer there.

### Rule 3 is not bent

"The original audio and the raw transcript are always kept" is about the
**pipeline**: a quota, an outage or a failed extraction must never decide that
something told is worth throwing away. It was never a promise that a person could
be held to words they did not mean to give — and an archive that cannot be
corrected by the person who filled it is a harder promise than the rule makes.

The removal is a tombstone, exactly like a rejected person (§3): `deletedAt` is
set, the row stays so the removal reaches the family, and nothing reads it. The
audio file stays on the device and in R2 the same way. What changes is that
nothing anywhere shows it — not the subject's card, not the gallery, not a
guessing round, not the export.

Only the teller's own, and the server is what makes that true rather than the
app's good manners: the memory upsert matches on `author_id`, so a tombstone for
somebody else's memory is refused. Nobody gets to tidy away what grandmother
said. She is the one person who may.

### What it costs

This is an addition, and CLAUDE.md asks for a removal to pay for it. Nothing is
removed. The argument for making an exception is that an emergency exit is not a
feature but the absence of a trap: the app asks an 80-year-old to press a big red
button and start talking, and until now that button could not be un-pressed. If
the trade is refused, the half to cut is the taking-back after saving — the
recording screen's way out is three lines and answers the more likely mistake.

### Verified

`TakingBackTests`, by pressing the buttons: a saved memory is taken back and the
gallery is empty afterwards rather than merely missing a row, and a recording
abandoned mid-telling leaves nothing behind at all. The second one really records
and answers the microphone prompt rather than working around it. The first was
also run with the orphaned-subject cleanup switched off, where it fails on the
gallery — the assertion that matters is the one about what is left, and it had to
be shown to be load-bearing.

The sheet exit has its own test in the same file: mid-recording, a swipe does
not dismiss and "Sulje" asks in the discard's words before anything is lost.
The interruption machinery is the one piece a UI test cannot drive — nothing
can place a phone call into a simulator from XCUITest — so its account above
is backed by the build and by reading, and the phase E visit is where a real
interruption will happen whether anyone schedules it or not.

## 20. Small promises the app was not keeping

Each of these is one line of code and one thing the app said it did.

**A merge now asks.** Correcting a name onto somebody the family already has is
not a rename: the two cards become one, this one's memories move across, and a
tombstone with a forwarding address is left behind (§2.5). It happened on the
same tap as an ordinary rename, warned about by a footer — and a footer is read
by somebody who is already looking for it. A rename can be undone by renaming
back; nothing in the app undoes a merge. So the heavier of the two acts asks
first, and the lighter one still does not.

**"Backendin osoitetta ei ole määritetty."** was written for whoever configured
the build and shown to the person holding the phone, who can do nothing with the
word *backend* except conclude that they broke something. It says that the
family service cannot be reached and that the memories are safe on the device,
which is what is actually true. `"Palvelin vastasi virheellä 500"` went the same
way: the code moved to `RemoteError.debugText`, English, for the console.

**And Settings said nothing at all when leaving a family failed.** `leaveFamily`
returns false and puts the reason in `session.lastError`; the screen read
neither, so the dialog closed and the family stayed. A refusal that looks like
nothing happening is the worst possible answer to a deliberate act — it is now
an alert with its own title, beside the export's.

The same reasoning had been applied to leaving and skipped for its neighbours,
found 23 Aug 2026. **Creating an invite** failed as a brief spinner and a
resting button, on the flow UX.md calls the path to the product's second user;
**revoking one** — the boundary's one remedy for a link gone astray — changed
nothing on screen at all, not even when the server answered. Both say so now,
in the leave alert's shape and register, and `SilentFailureTests` drives both
failures. `Session.revokeInvite` returns whether the server heard it; a server
that answers `revoked: false` is deliberately not a failure, because that code
was already dead and the refresh clears the row either way.

**Three smaller ones joined the list on 23 Aug 2026.** A telling the app was
killed under vanished without a trace — the recorder writes into tmp and
nothing referenced the file until stop() — and is now swept in at launch as
the same audio-only memory a quota outage leaves, with the catch-up writing
its text (`RecordingRecovery`). A question you asked the family came back at
you as a pinned *"Minä kysyy"* prompt — wrong in conjugation and in direction
— and the Tell screen's offers now exclude their own asker, while the subject
card keeps the question listed without the asker line. And a device the
server has stopped knowing (a 401 — realistically the shared Keychain, after
*"Tyhjennä tämä laite"* on another phone of the same Apple ID) was shown as
waiting for the network forever; it is its own sync state now, the gallery
note stops promising it fixes itself, and the Perhe screen says what
happened.

**And that device had no way back** — found by the founder's-eye review of
3 Sep 2026 (finding #57), fixed 5 Sep. The state showed on Muistot only inside
the outbox note, so a reader's phone with nothing to send fell silent for good;
the Perhe row four taps away had no action; and the documented way back,
*"Poistu perheestä"* and then a new invitation, ran through the very server
that was refusing the device — as did the wipe, which stops on a failed leave.
Now Muistot carries the note whatever the outbox holds and whether or not the
archive is empty, with *"Liity uudella kutsulla"*: the join form over the
archive, calling `Session.rejoin`, which joins the same family again as a new
member row and changes nothing on the phone — the rows, the key and the mode
stay, and the next round goes through. The same family only: a lever-3
invitation carries its family's key, and a key that differs is another
family's and is refused before any request. A fresh link tapped on that device
opens the same form with the code in it instead of the wrong-time alert, and
the wipe skips the leave there is nothing to make. What it does not fix is the
cause: two phones on one Apple ID share one identity by design (§4), so
emptying either one renews the other's — that stays a design question, written
down here rather than patched.

**And the key did not come back with it** — found 26 Sep 2026. The wipe also
forgets the family key, which sits in the same synchronizable Keychain, so the
other phone lost it too. `SyncEngine` read a missing key as *seal nothing*
rather than *send nothing*: a fallback from 16 Aug 2026 (`0efbc6a`) for
families from before lever 3, which production has never held. And
`Session.rejoin` compared keys but never took one, so the way back above
returned a phone that pushed the family's words, and uploaded its recordings,
in the clear. A family with nobody else was worse: nothing left the server,
nothing refused the phone, and the next round sent everything as told. Now a
round gets its key only through `SyncSeal`, which a missing key cannot make.
The round is held as `.keyMissing`; the Perhe screen's sync row and Albumi's
note say so in their own words, the note with the same *"Liity uudella
kutsulla"*; and the rejoin takes the invitation's key once the server has
placed the code in this family. One pull
is still asked for and thrown away, because that is how a forgotten phone
learns it is refused before a wipe tries to leave. A phone whose family had
nobody else has nobody to send the key back, so it stays held with its archive
intact on the phone, which is the honest side of that trade.
`scripts/keyless-sync-check.swift` drives the road in verify.sh; on 26 Sep 2026
it failed 22 of its 42 checks against the code before the fix and passed all
42 after it.

**And where the AI filed a telling could not be corrected.** The placement line
is the most important piece of the result — the organising the teller would
never do herself — and it was the one thing on that screen nothing could change:
grandfather's war years filed under *"Kesä Puumalassa"* stayed there for good,
while a misheard name got a whole correction flow (founder's-eye review,
finding #27; fixed 5 Sep 2026). *"Siirrä toiselle kortille"* under the line, and
on the memory's own row the day after, opens one sheet of the family's people,
places and events; `MemoryStore.move` refiles the telling, keeps its mentions,
and takes an auto-made moment with it when nothing is left under it, exactly as
taking the telling back does. The server's memory upsert now carries
`subject_id` from the author — it never had, so a move would have stayed on one
phone — and `memory-rules-check.mjs` presses on both halves: the teller moves
it, another member cannot move it back. Deployed 6 Sep 2026 (`f7643e4d`), and
the check ran against production straight after, 14 of 14 — the first time it
was ever pointed there, which is how it was found to be sending the local-only
`CF-Connecting-IP` header the invite check had already stopped sending.

**And a recording that could not be kept was called kept.** `persistAudio`
moves the file out of the temporary directory, and until 5 Sep 2026 a failed
move returned nil: the memory was saved without its audio, the row looked like
every other voice memory, and the screen said *"Äänesi on tallessa"* over a
file that was gone — rule 3 broken in silence on the one input the app calls
irreplaceable (founder's-eye review, finding #58). The move is tried again as a
copy, and nil is an answer now: a telling with no words and no recording is
not saved at all and the screen says *"Nauhoitusta ei saatu talteen"* with
*"Kirjoita se itse"* beside it while the words are still in mind; a telling
whose words arrived is saved as text and the result says the recording did
not. `-audio-lost` drives both in `SilentFailureTests`, and the sweep measures
the screen.

**And the launch sweep lost the telling it ran beside.** `RecordingRecovery`
listed tmp for itself late in the launch task — once the calls ahead of it
there had waited on the network, as late as the network made it — and the
recorder writes into the same directory under the same prefix. A
telling started in the meantime was deleted mid-recording, while the file is
still a 28-byte header nothing can open, or adopted between its stop and its
save, after which `persistAudio` cleared the adopted copy out of its own way.
Both ended at *"Nauhoitusta ei saatu talteen"*, and `export-check.mjs`, which
records at launch, came back with no audio in the export (26 Sep 2026). The
list is taken in `KinloreApp.init` now, before `body` has built the screen
that records, so nothing a launch writes can be on it however late the sweep
runs. `-recovery-sweep` runs the sweep at both moments in `SilentFailureTests`,
and `-recovery orphan` checks that what an earlier launch left behind is still
taken in.

**And a swipe deleted a relationship on the spot.** A swipe is easy to make by
accident, `swipeActions` is invisible until it happens, and what it removed was
a fact somebody had confirmed about their own family. It asks now — and the
dialog says the relationship can be added back from the same card, because the
recovery exists and is not obvious.

For sixteen days it did not ask, and nothing said so. The swipe button carried
`role: .destructive`, and on iOS 26.5 that role is a promise that the row is
about to go: the system animates it away before the button's action has done
anything, and the alert the row presents never comes up — measured 21 Sep
2026, `alerts.count` 0 after the tap and the card unchanged, by the first test
that ever swiped a relationship row. The role is gone from the swipe button
(`Elder.destructive` as its tint, since the system red measures 3.57:1 on this
paper) and stays on the alert's own *"Poista"*, the button that deletes.
`FriendTests` taps the swipe, reads the question and answers it.

**And every confirmation in the app had lost its cancel button** — found
5 Sep 2026, when the family sweep tapped *"Peruuta"* on the new member-removal
dialog and no such button existed. On iOS 26 a `confirmationDialog` attached
to a list comes up as a popover anchored to the list's top edge, 240 pt wide
under the navigation bar, and a popover adaptation draws no cancel action: the
Settings screen's *"Poistutaanko perheestä?"* was screenshotted with *"Poistu
perheestä"* as its only button, the way out being a tap in the dimmed area
that nothing on screen mentioned. Eleven dialogs presented that way, and no
test had ever tapped a cancel button, so every one of them passed. All of them
are alerts now: an alert draws both buttons, and the way out is one the person
rule 1 is about can see and VoiceOver can name. The alerts themselves are not
audited — measured, that reports iOS's own capped scaling on the alert's title
and message and nothing of ours — and the screens under them are.

The other half of that finding is left alone on purpose: the gesture is still
the only way to reach the removal. Relationships arrive as proposals from the
extraction and are added from a picker, both of which are the grandchild's end
of this app rather than grandmother's. If that stops being true, the answer is a
visible affordance and not a wider gesture.

---

## 21. The words

Three sessions have added buttons to this app, and the words held up better than
they had any right to. This section is why they should keep holding: for an
80-year-old a **new word is a new thing**. Somebody who has learnt that "Valmis"
ends a screen has not learnt that "Selvä" does, and finding out costs her a tap
she is afraid to take.

So: **a new word requires a new act.** Not a new screen, not a new author — a new
act. What follows is the vocabulary as it stands, arrived at by reading every
`Button` and `Label` in the app rather than by taste.

| The act | The word | Where |
|---------|----------|-------|
| Leave, having done the thing | **Valmis** | The result and saved-audio screens when the Tell screen is a sheet, the camera, the share sheet — never on the Kerro tab, which has nothing to close |
| Leave, without doing it | **Sulje** | A sheet's toolbar |
| Move on, having answered | **Jatka** | The blind card, after the answer is shown |
| I have read this notice | **Selvä** | The export alert, the skipped-photo note, the saved-audio screen in free dictation |
| Back out of a dialog | **Peruuta** | Every confirmation |
| Take a thing away | **Poista** | A memory, a person, a relationship, an invite |
| Throw away what was never saved | **Hylkää** / **Älä tallenna tätä** | The recording in progress |
| Speak | **Kerro …** | Everywhere it starts: *Kerro tästä muisto*, *Kerro hänestä*, *Kerro toinen muisto* |
| Type instead of speaking | **Kirjoita sen sijaan** | The Tell screen, the refused microphone |
| Supply the text that never arrived | **Kirjoita se itse** | The saved-audio screen |
| Accept what the AI proposed | **Vahvista** | Person rows, relationship rows |

Two distinctions in that table are load-bearing and easy to flatten by accident.

**Valmis / Sulje / Selvä are three acts, not three moods.** The first says the
work is finished, the second that it never started, the third that nothing was
being asked of her at all. The saved-audio screen chooses between the first and
the third by whether it was opened as a sheet — which looks like a wobble in the
code and is the right word in both cases.

*By whether it was opened as a sheet* is the presenter's closure, and since
12 Sep 2026 both screens read exactly that. Before, they read the subject: a
telling with a subject was a sheet, because only a sheet ever had one — until
the deck (§23, 29 Aug) gave the Kerro tab a subject too. From then
on a telling about the deck's card ended on a *Valmis* whose `dismiss()` had
nothing to dismiss, and the saved-audio screen, which has no other way off it,
held the same dead button. Found by a thumb on a phone; `DeckTests` now asks
both sides of the rule.

**Perhe is not suku.** *Perhe* is the people who use this app together: who can
see the memories, who gets the invite link, whose entitlement is shared. *Suku*
is the web of relations the archive describes, and most of it is dead. They are
different sets, they are different words, and neither should be used for the
other. **Ihmiset** is a third thing again — the list of person subjects, which is
what the tab is called, so the empty state under that tab now says *ihmiset* too
rather than answering in a word the person did not tap.

**Ystävä is not suku either, since 21 Sep 2026.** A friend is a person card
in the archive like anybody else, joined to somebody by `friend_of`, and the
word for the line is *ystävä*, decided over *kaveri* on the day it was built:
the one word for it that fits every age the archive holds. The card lists them
under *Ystävät*, below *Suku* and never inside it; the row that adds one keeps
its name, *Lisää sukulainen*, and its sheet offers *Lisää ystävä* after a gap; and the
tree's caption over them says *Ystävät* where the band below says *Ei vielä
sukupuussa*. English says *friend* and *Friends*.

**Albumi, not Muistot, since 13 Sep 2026.** The tab where the family's
photographs and tellings are looked at was called *Muistot*, and beside *Kerro*
both names read as the place where the memories are: looking at the app as a
buyer would, the founder could not say why there were two tabs. *Albumi* is the
object a grandparent already knows, the photographs and what has been said about
them; *Kerro* stays the place that picks what to speak about next. It holds the
same things it did, so this is a clearer name for an old place rather than a new
word for a new act. English says *Album*. Older text in this file, the other
documents and the code's comments still calls it *Muistot*, and means the same
tab.

**Sukupuu, not Ihmiset, on the phone that is shown one, since 19 Sep 2026.**
The same pass over the two names left standing answered them differently.
*Kerro* stays: it is the only verb in the bar and the only word that says what
this app is for, and it stays true on a grandparent's phone, where the tab is
the button and nothing else. *Ihmiset* had stopped naming what was behind it.
Since 13 Sep the tab opens the drawn tree on a family member's phone, and the
screen under the word *Ihmiset* was titled *Sukupuu* — so the one place the app
names itself before anybody taps it hid the part of it that took the most work.
That is the Muistot fault the other way round: not two words for one thing, but
one word too small for the thing.

The word now follows the same signal the content already follows. `PeopleTab`
in `RootView.swift` is that single decision — a grandparent's phone (the text
floor) and VoiceOver keep the list, and so keep *Ihmiset*; a family member's
phone draws the tree and the tab says *Sukupuu*, *Family tree* in English, with
the toolbar switch's own `tree` icon rather than a second drawing of the same
destination. Nobody confirmed is nothing to draw, so the first minute on a new
phone keeps the older word as well. Both the tab and the screen's title read
that one function, which is what stops them drifting apart a second time.

One case is deliberately left to disagree. A search is always answered as a
list, and the title says *Ihmiset* while the tab still says *Sukupuu*: a tab
that renamed itself under a typing finger is the worse of the two faults.
`FamilyTreeTests` pins both phones, and the grandparent's test now asserts the
tab bar as well as the screen.

**Litterointiaika, not kertominen, for the monthly meter, since 26 Sep 2026.**
Rule 2 says telling is never limited, and the words said it was: the free
tier's monthly allowance was *kertomisaika* on Help and *kertominen* on the
family screen and in every sentence about running out, so an English phone
read *"the month's free telling is used up"* one screen away from *"Telling is
always free"*. What runs out is the time in which speech is turned into text,
and that is now its only name — *litterointiaika*, *transcription time* — on
the family screen's row, the result screen, the waiting row and note on
Albumi, and the notice after a telling. It is a new word, which this section
asks a reason for, and the reason is that it names a thing the old word
misnamed. Help's *Mikä maksaa* explains it once; nothing else does. The same
pass took *rajoja ei ole* off the offer card and Help: the paid tier's
fair-use ceiling is written down and not enforced (PLAN §9), and *enemmän*
stays true either way.

What the survey changed, in full: *"Mitätöi"* on an invite became *"Poista"* —
the register of an authority annulling a document, in an app whose every other
removal is *poista* — and the People empty state stopped calling its own list
*suvun henkilöt*. Everything else was already consistent.

What it deliberately left alone:

- **"Riittää tältä erää"** ends the interview loop. It is a unique act — *stop
  asking me things* — and the one sentence in the app that sounds like a person
  rather than a product. A unique act may have a unique word.
- **"Tallenna tai lähetä arkisto"** on the share sheet, beside *"Vie arkisto"* on
  the row that opens it. Two steps of one act, and the second names the choice
  iOS is about to offer rather than repeating the first.
- **"Kirjoita se itse"** beside *"Kirjoita sen sijaan"*. Instead of speaking is
  not the same as instead of the transcription that never came.

One coupling worth knowing before changing any of this: the empty states are
duplicated as strings in `AccessibilityPolicy.systemEmptyStateText`, because a
`ContentUnavailableView` caps its own description and the exemption is matched on
the label. Change the sentence on the screen and that list changes with it, or
`testPeopleEmpty` goes red. That is the coupling working.

**Three words are reserved**, which is the one kind of row the table above
cannot hold: an act that must not get a word. Counted in both `.strings`
tables on 12 Sep 2026.

- **"Jaa" points inward, always.** The verb appears three times — *"Jaa
  kutsu"*, *"Jaa silti"*, and *"jaa se vain omille"* in the note under the
  invite — and every one of them hands something to the family. It is never
  the word for making something public. A third meaning would teach her that
  the word she has learnt also publishes things, and there is no unlearning
  that.
- **"Tarina" is not used at all.** Zero in both tables. A *tarina* is told for
  effect, or made up; what this app collects is *muistoja*, and the difference
  is the product.
- **"Vanhus" appears nowhere she can see.** Zero in both tables. Nobody wants
  to be called one, and the app has never needed the word: its strings say
  *isovanhempi* — a relation, not an age — and since 12 Sep 2026 the site says
  the same in English, *a grandmother*, where it used to say *an old person*.
  The developer documents still describe the primary user by age. They
  describe her to an engineer and do not address her, which is a different
  register.

---

## 22. The one blue button

The same problem as §21, one layer up. A word teaches a thing; a **prominent
button teaches "this is what you do here"**, and a screen with four of them has
taught nothing. For a user who is slow to trust a phone, the blue button has to
mean one thing.

The survey was mechanical: every `.buttonStyle(.borderedProminent)` in the app,
mapped to the view that owns it rather than to the file. Every screen had exactly
one — the gallery, the person card, the ask sheet, the
onboarding, the refused microphone, the failure screen, the saved-audio screen.

**Except the result screen, which had three**, and four on a free archive:
*"Korjaa nimet myös muistoon"*, *"Jatketaan jutellen"*, *"Avaa koko arkisto"* in
the upsell card, and *"Kerro toinen muisto"* at the bottom — four full-width blue
buttons down one scroll, on the screen that ends the magic moment and is most of
the demo video.

Two of them are now quieter:

- **The name correction** confirms something typed into the row above it. It is
  the row's own button, not the screen's purpose.
- **"Kerro toinen muisto" is prominent only when nothing above it already is.**
  With follow-up questions on screen the blue button is *"Jatketaan jutellen"* —
  carrying on about the memory she has just told is worth more than starting a
  second one, and it is the loop this app was built around (§10). With no
  questions, there is nothing above to defer to and telling another is all that
  is left. `View.elderPrimary(_:)` in `Elder.swift` is where that condition
  lives, so the next person to add a button finds the choice already made rather
  than making it again.

**The framed exception is the offer card** — the paid archive, or since
17 Aug 2026 the invitation while the family is one person (docs/UX.md §3.2);
one slot, one card at a time, so the exception transfers rather than
multiplies. It keeps its prominent button because it is not competing for the
same act: it sits inside its own tinted card, it is an offer rather than a
step, and its position is deliberate — the moment a memory finishes is where
perceived value peaks (§8.6). A card is its own decision. If a second card
ever appears on one screen, this exception is the thing to re-open.

Two things this rule is **not**. It is not "one button per screen": the result
screen still offers *Valmis* (on a sheet) and *Poista tämä muisto*, quietly, because a screen
that hides its way out is worse than one that ranks its actions. And it is not a
shared vertical position across screens — that is held constant only through
idle → recording → asking, where the record button must not move because those
three states are one act with one control, and the comment in `AskingView` says
so.

**Since 12 Sep 2026 the screen claims nothing it inferred.** It opened with
where the AI had filed the memory — *"Sijoitin sen kohteeseen Kesä
Puumalassa"*, a moment it had also named from the first place and the date —
and that was one telling asserted as an arrangement: the founder's second
launch showed an archive that knew a summer, a lake and two people from a
minute of speech. Now a telling names nothing (`TellViewModel.placeSubject`):
a photograph keeps its own name or none, a free dictation is its own moment
shown under its day (*"Kerrottu 12.9.2026"*, `Subject.displayTitle`), and
*"Nimeä hetki"* and *"Siirrä toiselle kortille"* are the person's. Only a move
the person made is announced. The names stand under one heading, *"Kuulin
nämä"*, each with the sentence it was heard in — recognition rather than
recall on the row where a wrong name is caught — with the rows to check first
and the familiar names quieter below them, exactly as before. Two questions
show rather than three; the third is stored and the loop asks it.
`ResultScreenTests` pins it.

**And when it happened, asked here since 19 Sep 2026.** The date row was the
subject's card and nowhere else, which is two screens from the one moment it
is known — somebody has just said *"se oli kesäkuussa 1957"* out loud, and the
way to record it was to leave the result, find the photograph and open its
card. Rule 5 stores uncertainty rather than rounding it, and a date nobody
walks two screens to give is not stored at all: the rule was kept by the
schema and lost by the geometry. The row sits under *"Siirrä toiselle
kortille"*, opens the same `DateSheet`, and shows only for a photograph or a
moment — the card's own `datable` rule, kept twice rather than shared, because
a person's date would have to mean birth or death and `date_start` does not
say which. It reads the store (`placedNow`) and not the subject the view model
captured when the telling was saved, which is the half that fails silently: a
date given here would be written and the button would go on inviting one.
Measured rather than assumed, and it changed the test: the canned telling
already carries a decade, so the row opens reading *"1950-luku"* and what the
screen really does is sharpen the model's answer rather than add the first
one.

**And the lists, the same day.** Ihmiset lists confirmed people only; the
names the extraction heard and nobody has checked wait behind one quiet row
at the bottom — *"2 nimeä odottaa tarkistusta"* — on a screen of
their own (`HeardNamesScreen`), each with the sentence it was heard in and
the two answers the result screen's row already had, *Vahvista* and
*Poista*; the name opens the card, where *Korjaa nimi* is. The orange
*"Ehdotus"* row that stood among the family is gone from both lists: Muistot
shows confirmed places only, and a moment is told apart by its first words
under its day. The telling itself carries *"Kuulin nämä"* on its row, so a
proposal ignored at the result is answered where the sentence is rather than
nowhere. A place's card kept its map after one day without it — a confirmed
place's map asserts nothing (§18). `HeardNamesTests` pins the three.

Measured: `testResult` and `testResultWithProposals`, both text sizes, green —
which is what checks the new `.bordered` labels against the contrast minimum,
the one thing eyes cannot check (§15). The no-questions branch was also read off
the screen: one blue button, the quiet removal beneath it. The other branch's
buttons sit below the fold on a phone-sized screen and were verified by the
audit rather than by eye.

## 23. The card, and why the front door was a blank page

*"Kerro mitä muistat"* over a button is a blank page, and a blank page is the
most reliable way there is to get nothing from anybody — especially from
somebody who does not believe they remember anything worth saying. The app has
believed this since the question ladder was written: §12 opens by saying that
*answering* a question is easy and *telling something* is hard. But the ladder
only has questions once there is something to ask about, so on the one screen
that matters most it had nothing, and fell back to exactly the blank page its
own reasoning rejects.

**A photograph is a question that needs no writing.** That is the whole idea,
and almost all of it was already built: the Tell screen has been able to open
on a subject since it was written — `target` is what makes the title *"Kerro
tästä kuvasta"* and the starter *"Kuka tässä kuvassa on?"* appear — and
`QuestionLadder.starters(for:)` has carried starters for all four `kind` values
from the beginning. What was missing was somebody choosing the subject when
nobody had navigated to one. `Deck` is that somebody, and it adds no screen, no
tab and no state.

### What the card is

Picture, question, button, and two ways on. In that order and nothing else:

- **The question is the title.** Not a heading with the question in a box
  below it — the ordinary title, the reassurance, the caption and a question
  card together left the question itself under the tab bar, with a 200 pt
  record button above it. The card asked nothing on the screen built to ask.
- **The big button answers it** rather than starting free dictation, through
  the same `answer(_:)` the question cards use, so the ladder still learns.
- **The reassurance is dropped.** *"Puhu ihan rauhassa ja vapaasti"* exists to
  make a blank button approachable. A photograph is not a blank button.
- **The picture is what gives way.** Capped at 200 pt, and the number is the
  screen's rather than the picture's. Worth knowing before changing it: while
  the content still fitted, shrinking it moved nothing at all — it sits between
  two spacers in a full-height frame, so a smaller picture only fed the spacers.
- **Both ways on share a line**, and neither is tinted. Stacked, the second
  went under the tab bar; tinted, the audit measured one of them at 3.48:1 and
  the other at 3.52:1 against a 4.5:1 minimum, inside the bar's fade. The same
  call the gallery's *"Kerro tästä"* row already made.

### What the deck is allowed to do, and what it is not

**A question a family member asked always outranks it.** *"Ville kysyy"* turns
a prompt into a request from a person, which is the strongest thing this app
can put in front of anybody — and the deck hides it silently if allowed to,
because giving the screen a subject makes it offer *that subject's* questions.
It did, for one commit; `VideoSceneTests` caught it, because the demo video's
fourth scene is that question being answered aloud. `DeckTests` now says it
directly rather than leaving the rule to a film.

**A family member's, and nobody else's — decided 12 Sep 2026.** The guard
counted every open question, and the extraction makes two or three from each
telling, so the first card told about took the deck off the screen until its
own follow-ups were answered: a pack meant to go from photograph to photograph
stopped at one, and nothing failed, because the blank button with questions
under it is a screen this app has. Found by the test written for the dead
*Valmis* (§21), which expected the next card and met the questions. Now
`openQuestions(onlyAuthored:)` is what the deck and both blind cards ask. The
follow-ups lose this one screen and nothing else: the interview loop asks them
the moment the telling ends, the Tell screen opened from that photograph
offers them again, and the idle screen returns to them once the deck has
nothing left. `testTheDeckGoesOnPastTheTellingsOwnQuestions` pins it.

Otherwise: photographs nobody has spoken about, free from the `subject` table,
which is where that decision pays. **People stopped being cards on 12 Sep
2026.** They ranked after the photographs, and a person's card is a name and a
question — *"Kerro hänestä – Toivo"*, *"Kuka Toivo oli sinulle?"* — where the
name is mostly the extraction's and unconfirmed. The founder met exactly that
on the second launch: a name nobody had vouched for, asked about as if it were
somebody. Rule 4 says an unconfirmed name is never fact; the front screen
asserting it as a subject was the same mistake one step earlier.
`testTheDeckNeverOffersAName` pins it, on the plain archive's Aino.

**And it stops.** `Deck.patience` is three pushes aside per session. This is
the failure mode the whole idea has to be designed against and it is a silent
one: nothing crashes, she simply meets a run of pictures she cannot place and
concludes that an app built to tell her she remembers a great deal has decided
otherwise. The ladder already holds the same opinion in numbers — one strained
answer costs a whole level, because for this user one wall costs more than a
run of easy questions.

Skips are device-local, like the ladder's comfort and `NewFromFamily`'s seen
list: *"she does not recognise this one"* describes the person holding the
phone. Her sister should still be asked.

### The blind confirmation, built 30 Aug 2026

The strongest thing this shape could do, and until now the thing §13 recorded
as lost with the cut guessing round: a card that shows the photograph and asks
*"kuka tässä on?"* **without showing what the extraction guessed**. Four names,
the proposal unmarked among them, and *"En muista"*. `BlindConfirmation`.

**The join was already in the model.** `Memory.subjectID` is what a telling is
about and `mentionedSubjectIDs` is who it named, so "the photograph this name
was heard in" is a query and not a column — `memories(mentioning:)`, the other
half of the `memories(for:)` this store has always had. That is the same reason
the deck itself needed no schema, and it is why this could be built in an
afternoon after being described as the next expensive thing.

**The photograph is why this is cheaper than what was cut.** The round hid a
name inside a sentence, and hiding it properly was most of its cost: an em dash
run reads to VoiceOver as punctuation, so the card asked nothing at all to the
person most likely to be listening rather than looking. A picture has no name in
it to leak. What is left of that lesson is one accessibility label —
*"Valokuva, jossa on joku"* — and a test that walks every element on screen
looking for a name.

What §13 asked to have back, and where each piece went:

- **A choice of four, three at the fewest.** Two is a coin. An archive with too
  few people gets no card at all, which is correct: there is nothing to
  recognise her *against*.
- **The seats do not move.** Their order comes from the enum's own string hash
  and not Swift's, which is seeded per process — and this is recomputed on every
  render, so anything unstable would shuffle the buttons under a finger already
  reaching for one.
- **Nobody named in the same telling is a decoy.** They may be in the photograph
  too, and a question with two right answers teaches the archive nothing.
- **"En muista" is an answer.** It confirms nothing, un-confirms nothing, and it
  is what stops the card coming back for ever.
- **One per person, one per session.** The first because a second attempt
  answers a question you have just been shown; the second because this card asks
  nothing — one tap, no telling — and a screen built for telling must not become
  a quiz.
- **A correct answer survives a merge**, because both sides are resolved through
  `store.subject(id:)`, which follows the chain.

**And a wrong answer is not called wrong.** The app does not know who is in the
photograph either; saying so would be the guess asserted as fact one screen
after the whole point was not asserting it. Both non-confirming answers get the
same sentence — *"Kiitos. Tämä jää toistaiseksi avoimeksi."*

**Two things the first build got wrong**, both caught by looking at the screen
rather than by a test. `.buttonStyle(.bordered)` paints its label from the tint
*after* the label is built, so `foregroundStyle` underneath it did nothing and
four names arrived in the system blue — the colour rule 1 names outright, in the
band where the audit has measured that accent at 3.52:1. And at the outer
stack's 24 pt spacing the fifth row, the way past a face she cannot place, was
drawn underneath the floating tab bar at the *ordinary* text size. 18 pt, and
`.buttonStyle(.plain)` over a `Color.primary` capsule with `Elder.cream` on it
— not a tint. A tinted style picks its label colour out of the tint *after*
the label is built, which is the overwrite that turned the names blue in the
first place, so the one thing that has to be certain here would have been the
system's decision rather than ours.

**And the same row went under the same bar again, on her album.** Since 5 Sep
2026 the card sits on Albumi (Muistot until 13 Sep) on a grandparent's phone —
the text-floor signal — where it is one thing under a large title rather than
the screen's only thing (`BlindCardView`, one view in both places). Measured
there on 19 Sep 2026 with `-seed blind -elder.largerText YES`: the search field
iOS 26 draws under the title (§8.12) pushed the photograph down, the photograph
took its full 200 pt, and the fourth name was drawn under the tab bar with
*"En muista"* below the screen — three of four names in front of the one person
the instrument exists for, and the way past a face she cannot place not on the
screen at all. No audit sees this. `performAccessibilityAudit` reads the tree,
and the tree holds all five rows whether or not the screen does;
`testMemoriesWithTheBlindCard` was green throughout. The album now carries no
search field at the floor and passes `photoHeight: 150` — the Kerro tab keeps
200, having the screen to itself — and at the floor the photograph, the
question, four names and *"En muista"* all sit above the bar, from a screenshot
and not from a tree. At accessibility sizes the card was already capped at 150
and scrolls, as it always did.

**The card is held in state, not recomputed.** It was a computed property first,
and that was wrong in a way only the *correct* answer showed: confirming writes
to the store, the store is `@Observable`, the view rebuilds, the query says
there is no card any more — and the card vanished under the finger that had just
answered it, before its one sentence could be read. A wrong answer writes
nothing and so kept its card, which is the same bug wearing the opposite face.

## 24. Colours by the telling

A black-and-white photograph holds no colours to bring back, and a model asked
to add them is guessing — a confident, good-looking guess in the one shape
nobody reads as a guess. So the app does not add them on its own. Somebody who
has told something about the photograph asks, the model is given those words,
and what comes back waits for a person to answer it. Decided and built on
13 Sep 2026, a fortnight before submission and against PLAN §5's rule that an
addition needs a removal; §5 carries it as the first thing to cut.

### The flow

A photograph's card offers **"Väritä kerronnan mukaan"** once something has been
told about it (`colourable` in `SubjectDetailScreen`), and never on a
grandparent's phone — the text-floor signal — because there the question has to
come before the colours, and that card is not built. The footer under the button
says what leaves the phone: the photograph and the memories told about it. It is
the one place in the app a photograph leaves without being sealed first (lever
3), and the words go with it the way a transcript does.

So it is not offered at all on a phone whose archive was kept to itself. That
phone's onboarding promised *"Perheen palvelimelle ne eivät lähde"*, and the Worker
refusing a phone with no family would come after the photograph had already
left. The first build offered it there anyway, and nothing but reading the
promise beside the gate found it; `ColourTests` holds it now, through the same
`isLocalByChoice` that keeps transcription off that phone.

`ColourSheet` shows the colouring and asks **"Näyttääkö tältä?"**:

- **"Kyllä, tallenna värit"** keeps it, beside the photograph and never in its
  place, with the name of whoever said yes.
- **"Ei, kerron lisää"** opens the telling for the same photograph, and the next
  colouring reads the correction first: the tellings go to the model newest
  first, and its instruction says the first of two quotations that disagree is
  the one to follow.
- **"En tiedä"** keeps nothing. Rule 5 stores uncertainty rather than rounding it
  into a yes.

`ColourTests` holds all three by what the card shows afterwards, which is the
one thing the question screen itself cannot show. The two answers that are not
"Kyllä" are ink inside an ink outline rather than `.bordered`. The sheet first
drew all three in the system blue, the blue §23 met on the blind card, and the
audit failed two of them outright, "En tiedä" at 3.05:1. With the accent named
it still reported "Ei, kerron lisää" on `.bordered`'s tinted wash as *nearly
passed* — which is a failure that happens to be close.

### What the model is trusted with, which is the hue

`ColourLock` does not keep the model's picture. It keeps the photograph's own
CIELAB `L` and takes only `a` and `b` from the reply, so every edge and every face
keeps the original's lightness. On the measured reply the chosen model had moved
the lightness of half the picture by more than three and a half points in a
hundred, and of a twentieth of it by sixteen; with `L` put back, ninety-nine
pixels in a hundred sat within a third of a point of the photograph. That was
the probe's arithmetic. `colour-lock-check.swift` holds `ColourLock`'s own to a
99th percentile of 1.5 and a largest difference of 6, over a reply painted
brighter the way the measured ones were.

That holds only while the reply's shapes sit where the photograph's do, so the
edges are compared first — the correlation of two Sobel maps at 256 pixels wide
— and below **0.85** a reply is refused rather than laid on. The line sits in
the gap the measurement left: the two models that kept the picture scored 0.971
and 0.964, the one that changed the shape of its frame by two per cent 0.683,
and the one that redrew every face in it 0.125. A photograph whose ratio the
model does not accept is centred on a canvas of the nearest ratio it does, and
the grey is cut away again before anything is compared.

The mark is in the pixels: a palette in the bottom-left corner of the kept
image, because a caption does not travel with a screenshot or a print.

### Cost, and whose allowance a round comes out of

`google/gemini-3.1-flash-lite-image`, chosen by measurement against three others
(the table is in `wrangler.jsonc`): **3.39 c a round**, read from the reply's own
`usage.cost`. Every round counts, a "not quite" included, because each is a whole
new image upstream. Five a month on the free tier, on a counter of their own —
`usage_counter.colourisations`, never the telling minutes, because the payer is
not the teller and a grandchild's colouring must not spend a grandmother's time
to talk. Unlimited when paid, like telling.

The route refuses before it spends: nothing told is a 400, a spent month is the
meter's own 402 with no request upstream, and a round that failed upstream is
not counted.

### Sync

A yes travels whole — the file, the confirmer and the moment — and only with its
file: until the upload has a key, the colours stay on the phone. The server
keeps the newest yes and nothing else. An older phone's push without the fields
changes nothing, an older yes arriving late does not replace a newer one, a
member can put only their own name on a yes, the key must be one of the family's
own objects, and a moment in the future is held to now, so it cannot lock out
every later yes. On the phone, `Subject.withColours` keeps the two things only
the phone can: a pull that says nothing about colours — a Worker that has not
been redeployed — takes nothing away, and a yes not yet uploaded is kept over
whatever arrives. The file is sealed like the photograph (`media.ts`, kind
`colour`), sits outside the photo limit, and `FullCopy` fetches it after the
photographs.

### Checked

| Claim | Check |
|---|---|
| Only the hue is laid on, moved shapes are refused, a ratio is framed and not stretched | `colour-lock-check.swift` — 5 deliberate breakages, 5 caught |
| What the model is told, what is believed back, the meter, and rule 8 on the image call | `colourise-check.mjs`, `data-collection-check.mjs` — 12 breakages, 12 caught |
| The route's doors in order, and a failed round not charged | `colourise-route-check.mjs` |
| Rule 9 on a failed colouring | `leak-check.mjs` |
| The server's newest-yes rules | `subject-rules-check.mjs` — 6 breakages, 6 caught |
| The phone's merge, and a yes sent only with its key | `colour-sync-check.swift` — 5 breakages, 5 caught |
| The three answers, no offer on a phone kept to itself, and the sheet at both text sizes | `ColourTests` — the local-mode gate deleted, caught; `AccessibilitySweepTests.testColourSheet` |

### Not yet

- **One photograph is not a sample.** The model, the edge line and the cost were
  all measured on one synthetic photograph. A grainy print may score below 0.85
  and have a colouring refused that kept every edge; the first real family
  photographs are the measurement that matters.
- **The correcting round has not been measured.** The instruction's last
  sentence, which of two disagreeing tellings to follow, was written after the
  measurement, and no model has been shown a correction yet.
- **No way to take a colouring back.** A later yes replaces an earlier one;
  nothing removes one.
- **The grandparent's own card**, where the question comes before any colour.
- **The export and the full copy carry it by code, not by check.**
  `export-check.mjs` and `full-copy-check.swift` were not extended.
- **Paid colouring has no fair-use number** beside PLAN §10's five hours of
  telling.

## 25. A face on the card

A person's card, the people list and the tree drew an initial in a disc, and
the disc's own comment said the app had no portraits and could not get any:
`imageFilename` is written only for photographs, so there was no face on file
for anybody the archive knew by name. Since 21 Sep 2026 there can be. A
person's card points at one of the family's photographs and a spot in it,
and every phone cuts the disc from its own copy of that picture. Nothing new
leaves the phone, nothing is uploaded, no quota moves: what travels is a
reference and two fractions. Built as the second phase of letting friends
into the archive (the plan itself stays outside the repository, as unbuilt
plans do) — a friend on the list is one more initial among many, and a face
is what tells her apart.

### The flow

The person card's first row is the disc, at the card's size, with **"Valitse
kasvot"** beside it, or **"Vaihda kasvot"** once there is a face. It opens
`FacePickerSheet`: the photographs this person has been told about in come
first, under *"Kuvat, joissa hänestä kerrotaan"* — the same join the blind
card reads, `memories(mentioning:)` — and the rest of the archive under
*"Muut kuvat"*. Only photographs on this phone are offered; a picture another
phone added is a key with no file until the full copy fetches it, and a face
cannot be tapped on a key. A tap on a tile opens `FaceFocusScreen`: the
photograph at the width of the screen, a ring over the square the disc will
show, *"Napauta kasvoja kuvassa."*, the card's own disc beside *"Näin kasvot
näkyvät kortilla."*, and **"Tallenna"**. *"Poista kasvot"* is on the picker,
and it is not red: nothing is deleted, the photograph stays, the card goes
back to the initial.

What is stored is `portraitSubjectID`, `portraitFocusX`, `portraitFocusY` and
`portraitSetAt` on the person's row (`Subject`, all four Optional for rule
10). Never a crop. `SubjectAvatar` looks the photograph up through
`MemoryStore.portraitPhoto(for:)`, which answers only with a live photograph
of the archive whose file is on this phone, and cuts the disc from the
600 px thumbnail with `Portrait.crop` — half the photograph's shorter side
around the spot, clamped inside the picture, drawn through `UIImage.draw`
rather than a pixel crop so a camera's orientation flag is honoured. The
cuts are kept in `PortraitCache`, keyed by file and spot, so a list of forty
decodes each picture once. When the picture is not on the phone, or was
rejected, or merged, the initial is drawn as before, silently: the server
keeps the choice and the phone may catch up.

Half the shorter side is one number and it is a decision about the
interaction rather than the picture: one tap and no zoom is the whole of
what an 80-year-old is asked for, so the square has to be right for the two
kinds of photograph a family actually has. In a portrait of one person it is
the head and shoulders; in a row of six at a table a face is about a tenth
of the width, and half the height shows it with the people either side. It
was measured on the fixture's photograph and reasoned about for the row of
six, and *Not yet* below says so.

The face disc keeps an ink ring, two points of `Elder.supporting`, where
the initial's disc has none. A photograph's border pixels can be as pale as
the paper — sky, a wall, an overexposed print — and the ring is what gives
the disc a shape (WCAG 1.4.11), in the same ink at 75 % the filled disc
measured against both grounds in §15. An unconfirmed person keeps the
proposal ring and the badge over the face, as over the letter.

What VoiceOver gets here is the screen and not the task, as it did on the map
in §18 before that screen had a search. Each photograph is a button with its
name, the picture on the focus screen says *"Kasvot otetaan kuvan keskeltä,
ellei muuta kohtaa napauteta"*, and the spot is the middle until somebody who
can see the picture taps elsewhere — so *"Tallenna"* is never disabled and a
face can be saved without a tap nobody can aim. The avatar itself stays
hidden from the accessibility tree, as every avatar is: the name is in the
row beside it, and "image" is all a face could add.

### The rules on the wire

Four columns on `subject`, `portrait_subject_id`, `portrait_focus_x`,
`portrait_focus_y` and `portrait_set_at`, added like the colour columns in
§24 and with the same shape of rule in `sync.ts`: **the newest moment wins,
whole**, and a NULL moment is never later than anything. That one line is
what lets three different pushes mean three different things. A choice is a
photograph under a moment. A removal is **no photograph under a new
moment**, and it wins over the older choice — which is how it travels at
all. And a phone that never saw the face pushes its whole row as every phone
does, with no photograph and *no moment*, and changes nothing. Without the
moment a removal and an ignorant phone would send the same two NULLs, and
either the removal could not travel or every stale phone would undo it.

The Worker does not believe the reference. The INSERT looks the photograph
up as it runs — a live one, of the pusher's own family — and anything else
becomes no photograph and, in the same statement, no moment: **no opinion**,
which the rules leave alone. Another family's photograph, a person, a
photograph the family has rejected, a photograph the family does not have:
each is measured in `subject-rules-check.mjs` and each changes nothing.
Because the lookup runs inside the batch, the push sorts photographs before
everything else, so a person given a face from a photograph that arrives in
the same request finds it already there. A spot outside the picture is
stored as none and the phone draws the middle.

Two consequences are recorded rather than fixed. A photograph rejected
*after* it was chosen stays on the person's row — the decision is a fact
about the family, the phone draws the initial when the picture is gone, and
un-rejecting the photograph would bring the face straight back. And there
is no `FOREIGN KEY`, for the same reason: soft deletion keeps the row.

The phone's half is one keep rule, `Subject.withPortrait(from:)`, the
colours' rule from §24 again: a pulled row with no moment takes nothing
away, because a Worker that has not been redeployed sends none and would
otherwise wipe every face the family had chosen on the first pull after an
update. A choice this phone has not pushed yet needs no rule — the row is
dirty and `applyRemote` skips it whole.

The blind card (§23) draws no avatar and never may: a face chosen for one
of the four names would be cut from a photograph, possibly the one on the
card, and a disc of it beside a name would answer the question in pixels.
`BlindConfirmationTests` reads every picture's label on that screen for the
four names and pins that one picture, and only one, is described as the
card's photograph. Not a count of all of them: the tab bar's icons are
pictures, and the Kerro tab keeps a photograph of its own in the deck above
the card — the first run of that line counted five.

The face row sits above the memories, and the audit's default-size
simulation reported the memory rows the moment it did: the story at y
595.67 and the byline at y 624, on the person card with a face and without
one, in the suite and alone, `MemoryRow` untouched and both screens clean at
a real AccessibilityXXXL. That is the `listHeaderAndFooterText` signature of
§15, fifth appearance, and the first whose label cannot be listed — a
story's words are the family's, and the byline carries the day.
`AccessibilityPolicy.isMemoryRowSimulationArtefact` forgives `.dynamicType`
on the row's two identifiers, `memory.body` and `memory.byline`, and the
sweep passes it in on its first launch only, where the audit simulates the
scaling; the second launch measures the real layout with nothing forgiven.
`scripts/audit-exemption-check.mjs` pins the two identifiers, the one type
and the one launch.

Widened on 26 Sep 2026 and renamed `isDefaultSizeSimulationArtefact`, after
the two person-card sweeps that were red on `main` alone —
`testPersonCardWithoutAStory`, seven findings, and `testPersonCardWithAFriend`,
one — were measured the same way on a private simulator: each alone twice with
frames identical to the decimal, at the default size only, the real
AccessibilityXXXL launch clean, and no contrast, hit-region or timeout finding
on either. The same row's other three texts (*"Kuulin nämä"*, the heard name's
kind, the listen button's words), the card's last section (the empty state's
sentence and *"Poista henkilö"*, which also reported clipping) and the relative
row's caption (*"Ystävä"*): each hidden-above arm audited clean with the
element's own code untouched, and the loss probe held all five of the
story-less card's elements in the tree at the largest size, where they audited
clean. The gate reads two identifier sets now — `.dynamicType` on eight
identifiers, `.textClipped` on the two that reported it — on the first launch
only, and the check pins both sets, both types, that every identifier is set on
a view, and the launch. The friend sweep reaches the row rather than its
heading at the largest size, because reached by the heading the row was never
in the tree there: five of sixteen labels gone, the friend's name among them.

### Checked

| Claim | Check |
|---|---|
| The four fields go and come back, a row with no moment keeps the face, a removal under a moment takes it, and `applyRemote` lays the rule on | `sync-fields-check.swift` — 7 checks added |
| Newest moment wins, a removal travels, an ignorant phone changes nothing, and what the Worker refuses: another family's photograph, a person, a rejected photograph, one the family does not have; photographs first in a request; a spot outside the picture; a moment in the future; only a person has a face; a photograph rejected after the choice stays on the row | `subject-rules-check.mjs` — 14 checks added, over the local Worker and D1 |
| Chosen by tapping the face, and the row flips; taken off from the same row, and it flips back | `FaceTests` |
| The list with a face, the card with a face, the picker and the spot, each at both text sizes | `AccessibilitySweepTests` — 4 sweeps |
| No picture on the blind card's screen carries a name, and one is described as the photograph | `BlindConfirmationTests` |
| The memory row's exemption reads two identifiers and one audit type, the row sets both, and the sweep passes it in on the first launch only | `audit-exemption-check.mjs`, in `verify.sh` |

### Not yet

- **Production.** The four `ALTER TABLE` statements and the Worker deploy
  are a decision taken at the keyboard, not in a commit; this section
  records the date when it has happened.
- **No zoom, and the square was measured on one photograph.** The first
  real family photographs are the measurement that matters; a face in a
  crowd of twelve may need a tighter square than half the shorter side.
- **The export does not carry the face.** The photograph is in the export;
  which of them is somebody's face, and where, is not
  (`ArchiveExport` is unchanged).
- **A face chosen on another phone is the initial until the full copy has
  fetched the photograph.** By design, and unmeasured on a real family.
- **Places have no face**, and a photograph is its own picture.
- **The tree at 48 points has not been looked at with a real face in it.**
