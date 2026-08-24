# Architecture — the remaining half

This document designs what had not been built yet. The finished part is
described in [PLAN.md](PLAN.md) §7 and in the code.

**If you read one section, read [§1](#1-where-things-stand)** — an inventory of
what is built and what is not, ending in a warning about why that inventory has
been wrong before. Sections 15 to 20 are each one bug: what it was, how it hid,
and what found it.

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
[22. The one blue button](#22-the-one-blue-button)

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
| RevenueCat, shared family entitlement | **Built** — the binding rule is checked (§6); the REST verification and the webhook need keys and are unrun |
| Audio playback, open questions, relationships | **Done and tested** |
| Paywall | Built — unverified, needs a RevenueCat key |
| Interview loop (questions asked aloud) | **Done and tested** — runs hands-free round after round |
| Asked questions (a person asks, the name travels) | **Done** |
| Places, reachable rather than only stored | **Done and tested**, see §8 |
| Coordinates for places — stored, nothing drawn yet | **Done**, see §18 |
| Correcting a misheard name afterwards | **Done and tested**, see §17 |
| Soft deletion — a rejection that is final | **Done and tested**, see §3 |
| A telling taken back — mid-recording, or after it is saved | **Done and tested**, see §19 |
| Search over what was told, not only over titles | **Done and tested**, see §8 |
| A date given by hand, at the precision somebody actually has | **Done and tested**, see §8 |
| Whether a telling has reached the family, on screen | **Done and tested**, see §3 |
| What the family told while this phone was away, on screen | **Done and tested** — the same promise's mirror, see §3 |
| Rate limiting on the two unauthenticated writes | **Done and tested**, see §4 |
| Accessibility sweep over every screen | **Done** — 32 sweep tests, each auditing one screen at the default text size and again at the largest, out of 62 UI tests, and they audit the screen they are named after. `scripts/verify.sh` counts both and fails if this sentence drifts from the source again |
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
own, and the sole automatic edit is the text update made by name correction.

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
| A subject renamed on two devices | The higher `seq` wins |
| One confirms, the other does not | Confirmation always wins (§2.4) |
| One merges, the other adds | The merge redirects, nothing is lost (§2.5) |
| One deletes a memory, the other reads it | Only the author can delete |

Everything else is resolved by the higher `seq`. There are deliberately few
rules — every extra rule is a place where data can silently go wrong.

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

Eleven assertions, and none of them is visible when it breaks. A memory whose
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

Adding it also showed that the suite had grown into its own rate limit. Creating
a family is five a minute per address, and the seven checks that need one create
eleven between them, so whichever ran last failed with `429` — a message that
reads like a broken Worker and is not one. Each check now knocks from an address
of its own via `CF-Connecting-IP`, which Cloudflare sets from the connection and
ignores from the client, so it is local only. Seven scripts, twice through with
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

Ten assertions, and the neighbours in that statement are checked beside it:
confirmation is one-way, a merge is sticky, a rejection cannot be revived.

**Shown to be load-bearing** without a mutation, because the bug was real: run
against `origin/main` before the fix, on a Worker and database of its own, the
two date cases went red and the other eight stayed green.

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
GET  /family              → members, own role, invite link status
DELETE /family/invite/:id → revoke a link
```

**The invite link is the entire security boundary.** Anyone who receives the
link sees all of the family's memories. Therefore:

- The code is long and random, not meant to be read by a human — 16 random
  bytes, 128 bits, base64url. Guessing it is not a threat model
- It expires, and the owner can revoke it at any time
- **Creating a family and joining one are rate limited**, per IP, with
  Cloudflare's `ratelimits` binding: 5 and 10 a minute. They are the only two
  routes in the Worker that write without a member identity, so they are the
  only doors an uninvited caller can knock on — and both insert rows. The limit
  is aimed at that unmetered write rather than at the guess, which the entropy
  above already answers
- The family view shows who has joined **and when**. The date was decoded from
  the server and never drawn until it was looked for: a stranger in the list is
  a question, and a stranger who arrived last Tuesday is an answer about which
  link went astray. Invites show how many times each has been used beside it

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

## 5. Media

Photos and audio go to R2, metadata to D1.

```
POST /media          → upload a file, returns r2_key
GET  /media/:key     → download (checks family membership)
```

The local filename and the R2 key are **different fields** (`imageFilename` and
`r2Key`). The same photo has a different filename on each device but the same
key, so one field would not be enough.

Upload happens **before push**, so rows travel with their keys. Otherwise the
other device would see the memory but not the photo it belongs to.

Fetching is **on demand**: a family may have hundreds of photos, and they are
not fetched at launch. The grid fetches only what is visible.

**In the MVP the file passes through the Worker.** Photos are about 300 kB
(downscaled to 2048 px) and 90 seconds of audio about 200 kB, so that is
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
| The payer leaves the family | The right lapses on the next webhook. Another member can buy. |
| Two payers | The longest expiry wins. Both are shown in the family view. |
| Refund | The webhook drops the right immediately. There is no REFUND event: it arrives as CANCELLATION with `cancel_reason: CUSTOMER_SUPPORT`, which is the only cancellation that revokes. |
| Auto-renew switched off | Nothing, until the EXPIRATION event ends the period that was paid for. This was assumed wrong once — a plain CANCELLATION revoked at once, locking the family out of a paid month — and `webhook-revocation-check.mjs` now pins the split. |

The rule **"downgrade never deletes"** is absolute. A family that loses memories
when the payment ends never comes back, and that is not a product worth building.

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
seven checks fail, which is how it was shown to be worth having.

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
`UpsellRhythm.card` decides which card, the rhythm above decides when the slot
shows at all, and the check script covers both halves. The argument is
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
- The family owner can remove a member

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

   The form behind the first one asks two things, and the second one is not
   about the family: **whose phone is this.** Setting up takes a grandchild a
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
   rows, and a button on one of them was renamed (§21) without anything drawing
   it once. `-seed family` (DEBUG) gives `Session` a canned family with no
   network: three members, one used invite and one open one, a part-spent free
   quota. Same hole as `-mic denied` and `-screen result`, same shape of answer.

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
6. **Paywall** — RevenueCat's own, not a hand-built one: it is configured
   remotely, so prices and wording change without shipping a build. Two ways in,
   both of which only exist when a RevenueCat key is configured — a dead button
   is worse than no button. The primary one is the moment a memory finishes,
   where perceived value peaks; the second is the family view, so a grandchild
   looking at the limits does not have to go and dictate something to find it.
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

9. **The refused microphone** — a screen of its own rather than a message.

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

10. **"Näin tämä toimii"** — the help page, behind the gear.

    The app explains each step where the step happens, which is the right order
    and was the whole of it. Three things are true of the app rather than of any
    screen, and one of them a person cannot discover by using it at all: **the
    recording leaves the phone.** It goes to our Worker, which sends it on to be
    turned into text. Nothing anywhere said so — the microphone prompt talked
    only about keeping the voice for the family, and it says both things now.

    The other two are what somebody asks before trusting an app with their
    family: who can see this, and can I get it back out. Six short sections, no
    disclosure triangles — a person who opened a help page is already looking
    for the answer, and making them hunt twice is how help becomes decoration.

11. **Search**, on Muistot and Ihmiset.

    It searches **what was told**, not only titles. A photograph has no title
    until somebody says something about it, so a search over titles would find
    least on exactly the archive that most needs finding — and what a person is
    looking for is "the one about the cottage", never a name nobody gave it. One
    query runs over the subject's own title and the text of every memory on it,
    in `MemoryStore.subjects(of:matching:)`, so both screens ask the same
    question of the same rule.

    Out of the way by design: `.searchable` keeps the field above the list until
    somebody pulls down. The grandchild looking for one name in forty finds it;
    grandmother never meets it. A fruitless search gets its own dead end rather
    than the empty archive's invitation — offering *"lisää kuvia"* to somebody
    who searched for a word answers a question nobody asked.

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

12. **A date by hand**, on a photograph or a moment.

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

Not built:

13. **Family tree** — a drawn graph. **A trap.** Relationships are lists on the
   person card: the same information, works at the largest text size and is
   readable with VoiceOver. Formally out of v1 since §10.

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
the loop — the app reads the top question with the device's own Finnish voice
(`InterviewVoice`), starts recording when the sentence ends, and the answer
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
hurt, the cap belongs in the store, not here.

The pairing required by "every addition requires a removal" (CLAUDE.md): the
drawn family-tree graph, already last in line in §8, is now formally out of
v1. The person-card lists carry the same information.

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

`prompt_question.target_member` (aim a question at one person) has existed in
the schema from the start and stays unused: routing to a specific member needs
a picker and a visibility explanation, and the family-wide version already
carries the emotional core.

## 12. The question ladder

Some people cannot start with "tell me about this photo". The first thing this
app asks of a person has to be small enough that failing at it is impossible —
and it has to grow as they get used to being asked.

Today it does neither. Questions are not selected at all: `openQuestions` takes
the three oldest unanswered ones and the interview loop takes
`newQuestions.first`, whichever the model happened to emit first. Extraction
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

**Starters** fill the blank-button gap. A subject with no memories offers two or
three level-1 questions derived from its `kind`, with no LLM call, no network
and no AI minutes. They are **not stored and not synced**: thirty imported
photographs would otherwise put ninety rows into the family's open-question list
and make the list worthless. A starter is a prompt, not a debt.

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

As a side effect this closes the open edge left in §10: the open-question list
grows by three every round, and ordering plus the return of skipped questions is
exactly the cap that was deferred to "the store".

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
tap and was the only part of the app that asked nothing of the 80-year-old. That
problem is now unsolved again, and nothing else in the app addresses it.

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

If confirmation is ever strengthened, these are the pieces that were expensive to
get right and are recorded here rather than rediscovered:

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

### Export

One zip through the share sheet:

| In the zip | Why |
|---|---|
| `muistot.html` | Every memory under its subject, dates as they were told, photos inline, audio playable |
| `kuvat/`, `aani/` | The originals, byte for byte — audio is never re-encoded, here least of all |
| `arkisto.json` | The store exactly as it sits on disk |

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
  Kinlore installed.
- **The raw JSON travels beside it.** If the readable version ever lags behind
  the model, nothing has been lost.
- **`NSFileCoordinator(.forUploading)` does the zipping**, so no dependency is
  added for one archive format.

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
  memories are still on the server and rejoining brings them back; in a local
  archive they are gone for good, and the screen says exactly that in those
  words rather than in a generic warning.

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
  deliberate non-feature beside member removal (§14's moderation pairing).

**Verified by opening it, 16 Aug 2026.** The export is the one output that
leaves the app for good, and its promise — *"sen voi avata millä tahansa
koneella ilman tätä sovellusta"* — had never been checked against an actual
file. It was: run on the simulator, pulled out of the app container, unzipped.
The page carries the memories, `arkisto.json` carries the model, and a recorded
memory travels as `aani/memory-….m4a` — real M4A by `file`, not by extension —
with the page linking it as `<audio controls src="aani/…">`, a relative path
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
shape now: subjects, memories, questions, relations, guesses.

**Deliberately not built: deleting your own memories out of the family.** Rule 3
keeps the original audio because the speaker may no longer be around to ask, and
a tap that erases a dead person's voice from everybody else's archive is not a
feature this app should own. If it is ever needed, it belongs to the family
owner and to a conversation, not to a member's settings screen.

The pairing required by "every addition requires a removal" (CLAUDE.md):
**moderation is formally out of v1.** `report` and `block` are in the schema for
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
| iOS blue `#007AFF` on white | **4.0:1** | `AccentColor` `#0B57D0` — **6.4:1** |
| `.secondary` label | **≈4.2:1** | `Elder.supporting`, 75 % of primary — **≈6.6:1** |
| iOS orange `#FF9500` on white | **2.2:1** | `Elder.proposal` `#C2410C` — **5.2:1** |

Each is one place rather than thirty. The accent colour is an asset catalog
entry, so every tinted button and every tinted line of text moved at once; the
other two are constants in `Elder.swift` next to the tap target size, where the
next person will find them.

The orange one is worth naming. It marks *"the AI proposed this, nobody has
confirmed it"* — the single label in the app whose entire job is to make someone
stop and check — and it had the **lowest contrast of anything on screen**. The
shape of the icon has always carried the same meaning, which is why the screen
was still usable; that redundancy is what a colour fix should never be allowed
to replace.

A fourth default belongs with them: **iOS red measures 3.6:1**, and it labels
*"Tyhjennä tämä laite"* — the one button in the app that destroys an archive.
`Elder.destructive` `#B3261E` measures 6.5:1 and is unmistakably still a warning.

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
- The guessing round's truncated preview (§13): a teaser, whole text one tap
  away, all of it in the accessibility label.
- `Lisää sukulainen`, where a `Menu` reports a label frame smaller than the text
  it draws. Verified on screen at both sizes.
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
`Elder.affirmative` is #1E7A3A at **5.4:1**, still unmistakably green.

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

**Three counted failures and the app stops asking.** The count is device-local
in `UserDefaults`, for the same reason `comfort` is (§12): it describes this
phone's attempts, not a fact about the family's archive, and a count that synced
would let one phone's bad afternoon stop another phone from ever trying.

Giving up on the text is not giving up on the recording. The audio is kept,
uploaded and exported exactly as before — and the memory card stops saying
*"teksti valmistuu myöhemmin"*, because after the app has stopped trying that
sentence is the same false promise this whole section exists to remove.

Counting a 5xx as the recording's fault is the debatable line, and it is drawn
there on purpose: a Worker that is genuinely broken spends three attempts before
the app gives up on a transcript it might later have got, whereas the one 5xx
this app raises deliberately is permanent for that audio. An uncounted permanent
failure is the loop being closed here.

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
in by `PlaceResolver` on the device. **There is no map screen yet, and that is
deliberate**: the columns and the lookup cost an hour, a map costs a phase (see
PLAN.md §5), and the archive that is being recorded this week is the one a map
would eventually draw. Data first, so that the family's places accumulate while
the decision is still open. A place is already openable like any other subject
(§8); what it does not have is a position on anything.

### Why the device and not the Worker

`MKLocalSearch`, biased at a box covering Finland and Karelia. No API key, no
quota to meter, no Worker round trip, and **no location permission** — looking up
a name is not asking where the phone is, so `Info.plist` gains nothing and the
80-year-old is asked nothing. What leaves the device is the place name and
nothing else: not the memory, not the transcript, not who told it.

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
machine lookup instead of a machine-heard name. Today nothing in the app
confirms one, because nothing displays one. **When a map is built, an
unconfirmed place must not be drawn as a pin that reads like a record**, and the
confirmation has to come from a human who knows which Karjala it was. Anything
else buries a guess in the archive as fact, which is the failure mode this whole
architecture is built to avoid.

### When it runs

At launch and on every return to the foreground, after sync — a place another
device has already resolved arrives with the pull, and looking it up again would
be work for an answer we now have. A place told *during* a session is therefore
resolved on the next sweep rather than immediately, which costs nothing while
nothing displays a coordinate. Telling must never wait on a lookup.

### Sync

The coordinates follow the title, because they are the answer to it. A device
that has not looked a name up sends null and cannot wipe what another device
resolved; a device that *corrects* the title clears them on both sides, and the
next sweep looks the new name up. A tombstone is never resolved, whether it was
left by a merge or by a rejection (§3) — neither is its own place any more, and
looking one up would spend a request on a name the family has taken back. See
the `CASE` in `push()` in `backend/src/sync.ts`, and `MemoryStore.rename` for the
same rule on the client.

Every one of those rules is silent when broken: memories still sync, places
still open, and the only evidence would be a point on a map nobody has built
yet. So they are checked through the running Worker rather than asserted —
`scripts/place-sync-check.mjs`, five cases, no AI call and no credits spent.
The check was itself checked: with the `CASE` replaced by a plain `COALESCE`,
case 3 fails and the script exits non-zero.

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
- Nothing displays a coordinate yet (§18 above), so what accumulates before
  v1.1 is bounded and re-sealable by the same sweep that resolved it.

`InviteShare`'s doc comment beside the invite text already says the smaller
thing lever 3 promises about the key; this paragraph is where the whole of
what a dump yields is written down. Sealed: memory bodies, raw transcripts,
subject titles, question text, and the R2 bytes. In the clear: the family's
own name and its members' display names, timestamps and the carefully kept
dates with their precision (rule 5), subject kinds, memory sources and audio
lengths, sequence numbers, relationships, the mention graph — which memory
names which subject, with the model's confidence — and points for places.
Anyone weighing the app against that list is weighing the truth.

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

**And a swipe deleted a relationship on the spot.** A swipe is easy to make by
accident, `swipeActions` is invisible until it happens, and what it removed was
a fact somebody had confirmed about their own family. It asks now — and the
dialog says the relationship can be added back from the same card, because the
recovery exists and is not obvious.

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
| Leave, having done the thing | **Valmis** | The result screen, the guessing card after the reveal |
| Leave, without doing it | **Sulje** | A sheet's toolbar, the guessing card before the reveal |
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

**Perhe is not suku.** *Perhe* is the people who use this app together: who can
see the memories, who gets the invite link, whose entitlement is shared. *Suku*
is the web of relations the archive describes, and most of it is dead. They are
different sets, they are different words, and neither should be used for the
other. **Ihmiset** is a third thing again — the list of person subjects, which is
what the tab is called, so the empty state under that tab now says *ihmiset* too
rather than answering in a word the person did not tap.

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

---

## 22. The one blue button

The same problem as §21, one layer up. A word teaches a thing; a **prominent
button teaches "this is what you do here"**, and a screen with four of them has
taught nothing. For a user who is slow to trust a phone, the blue button has to
mean one thing.

The survey was mechanical: every `.buttonStyle(.borderedProminent)` in the app,
mapped to the view that owns it rather than to the file. Every screen had exactly
one — the gallery, the person card, the guessing sheet, the ask sheet, the
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
screen still offers *Valmis* and *Poista tämä muisto*, quietly, because a screen
that hides its way out is worse than one that ranks its actions. And it is not a
shared vertical position across screens — that is held constant only through
idle → recording → asking, where the record button must not move because those
three states are one act with one control, and the comment in `AskingView` says
so.

Measured: `testResult` and `testResultWithProposals`, both text sizes, green —
which is what checks the new `.bordered` labels against the contrast minimum,
the one thing eyes cannot check (§15). The no-questions branch was also read off
the screen: one blue button, the quiet removal beneath it. The other branch's
buttons sit below the fold on a phone-sized screen and were verified by the
audit rather than by eye.
