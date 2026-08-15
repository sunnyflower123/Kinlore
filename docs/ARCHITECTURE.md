# Architecture — the remaining half

This document designs what had not been built yet. The finished part is
described in [PLAN.md](PLAN.md) §7 and in the code.

---

## 1. Where things stand

An honest inventory, not a wish list:

| Part | State |
|------|-------|
| Dictation, typing, extraction, name correction | **Done and tested** |
| Photo import, gallery, person cards | **Done** |
| `subject`, `memory`, `mention`, `prompt_question` | In use |
| Identity, family, invite links | **Done and tested** |
| Sync (`/sync` pull and push) | **Done and tested** |
| Media to R2 (`/media`) | **Done and tested** |
| Quotas (`/usage`, limits on the server) | **Done and tested** |
| Deferred transcription — the interrupted memory finishes itself | **Done and tested**, see §16 |
| RevenueCat, shared family entitlement | **Done and tested** |
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
| Whether a telling has reached the family, on screen | **Done and tested**, see §3 |
| Rate limiting on the two unauthenticated writes | **Done and tested**, see §4 |
| Accessibility sweep over every screen | **Done** — 20 screens at both text sizes, out of 41 UI tests, and they audit the screen they are named after |
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

**The queue is drained when the app is opened and when it comes back to the
foreground**, not on a timer and not with backoff. An earlier version of this
document promised backoff; it never existed, and it should not. iOS suspends a
backgrounded app, so a retry timer is a thing that mostly does not fire, and the
one moment worth retrying at — the phone being in someone's hand again — is a
lifecycle event the system already delivers. A failed sync leaves everything
queued and says nothing to the user, because a network error is not her problem.

The one row the outbox deliberately holds back is a memory whose audio has not
reached R2 yet: the server would refuse it, and a refused row is cleared from
the outbox exactly as a stored one is. See §16.

Operations are **idempotent**: everything is an upsert keyed by a client
generated UUID. The same operation twice breaks nothing, which makes retrying
safe without coordination.

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

This is a point where simplicity and security genuinely conflict, and the choice
is deliberate: ease wins, because a login wall would drive away exactly the user
the app exists for.

### The shape of the invite link — a known shortcoming

The link is `memorize://join?code=...`. **iOS shows a confirmation dialog for
custom URL schemes** ("Open in Memorize?"), which is in English and is one extra
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
registered, and `memorize://join?code=…` reaches the app cold and warm. The tap
on the system dialog itself could not be automated here, so what happens after
Open rests on the code rather than on a run.

### The identity survives deleting the app

Keychain entries persist across app deletion, and `kSecAttrSynchronizable`
carries them via iCloud to the user's other devices. Verified: the same member
id across three launches, including after deletion and reinstallation.

That is the correct behaviour for this audience. Accidentally deleting the app
must not mean losing the family.

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

**The original audio is always uploaded**, including on the free tier. It is the
core of the product, not an extra.

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
| Refund | The webhook drops the right immediately. |

The rule **"downgrade never deletes"** is absolute. A family that loses memories
when the payment ends never comes back, and that is not a product worth building.

### Where the paywall goes

Right after the first AI-structured memory is finished. That is when perceived
value peaks. Not in onboarding, not in settings.

**Telling is never paywalled.** The limits apply to the photo count and AI
minutes.

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

    The pairing "every addition requires a removal" asks for is **not paid**.
    Nothing was removed for this one; it is an addition, and the decision to
    take it was made deliberately rather than by forgetting the rule.

Not built:

12. **Family tree** — a drawn graph. **A trap.** Relationships are lists on the
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

## 13. The guessing round

*One person tells a story, the others guess who it was about.*

Everything above this section is a **writing** loop: a question arrives, someone
tells a memory, the memory generates more questions. It works, but it asks for
effort from exactly the family members who have the least of it, and it gives
nobody a reason to open a memory that is already written. Family archives do not
usually die because nothing was recorded. They die because nothing is ever read
again.

The round is the reading loop. It costs one tap.

### It is not authored, it is derived

The obvious way to build this is to let someone compose a riddle. That is the
wrong app: this one's primary user is 80, and asking her to tell a story while
deliberately leaving the name out fights the entire extraction pipeline, which
exists precisely because she says names.

So nothing changes about how she tells. What changes is how the family reads.
Extraction already produces `mention` rows; a memory that names exactly one
person is already a question with an answer. Hiding the name turns it into a
round, and there is no round table — the round is computed on the client from
data that already exists. Storing rounds would mean deciding in advance which
memories become questions, and that decision goes stale the moment a misheard
name is corrected or two people are merged. Only the answers are stored, in
`guess`, because only an answer is a fact about a human being rather than about
the current state of the archive.

### Why it earns its place: blind confirmation

Rule 4 of the product is *AI proposes, a human confirms*. The weakest possible
implementation of that rule is a card with the answer already written on it and
a "Yes" button — people tap it without reading. It is a confirmation UI that
manufactures confirmations.

A guess cannot be tapped without reading, and the guesser was never shown the
name. When someone who did not tell the story arrives at the same person the
extraction did, that agreement is real evidence, and it is stronger evidence
than the proposal card would ever have produced. So a correct guess confirms the
person (`subject.confirmed = 1`). A wrong one confirms nothing, un-confirms
nothing, and is still kept: a family that keeps naming the same wrong person is
telling us the extraction picked the wrong name, which is worth more than a
boolean.

Relationships are deliberately left alone. A guess is about identity, not about
who someone's mother was, and a wrong relationship is worse than a missing one.

Two server rules protect that evidence, verified with curl against a local D1:

- **The guesser is the session, never the payload.** A device that pushes a
  guess in another member's name has it recorded under its own id instead —
  otherwise one phone could manufacture family-wide agreement and confirm a
  person nobody recognised.
- **A guess is final.** `ON CONFLICT DO NOTHING`, because the answer is revealed
  the instant it is given; a second push is someone answering a question they
  already know.

And one client rule that is easy to get wrong and fails silently: **a guess is
compared to the answer through the merge chain, not by raw id.** The guess is
stored against the subject as it stood when it was made, so a later merge
(*Aune → Aino*) leaves it pointing at the tombstone. Comparing ids directly
would make every correct guess made before the merge quietly stop counting —
exactly the class of bug `merged_into` exists to prevent (§2.5).

### "En muista" is an answer

It reveals the answer like any other choice, and it is **stored**, with a NULL
`subject_id`.

Both halves matter. Revealing, because learning who it was is the entire payoff
and the person who did not know is the one who most needs telling. Storing,
because a round that is not answered is offered again — and since only one round
is shown at a time, a single unanswerable memory would stand in front of every
other one forever. It also records something true: nobody in this family
remembered her.

### The masking problem

The round is only safe if the name is genuinely gone, and in Finnish a string
replacement is not enough: it removes "Aino" and leaves "Ainolle" standing two
words later. This is the same inflection problem the correction prompt solves in
`extract.ts`, but it cannot be solved the same way — asking the model would cost
an AI call and a quota per round.

Matching is on the stem instead, guarded on both sides: the word must be
capitalised **in the text**, which is how an inflected Finnish name is written
and how "ainakin" survives, and it must not be much longer than the name, which
keeps "ainoastaan" from vanishing because it starts the same way. Surnames in
`-nen` get their own rule, because "Virtanen" → "Virtasen" already differs at
the sixth character.

It is a heuristic about a language, so it is checked against the language:
`scripts/guess-mask-check.swift` compiles the real `GuessRound.swift` and runs
Finnish cases through it. This is the one part of the feature that fails
silently — a round that leaks the answer still looks like a working round.

### What refuses to become a round

A round is only built when it is both safe and fair, so most memories are not
rounds. Two named people (the question is ambiguous), a memory told about the
answer herself (her card is the subject), your own story, fewer than four people
in the archive, a name that does not appear in the text, less than fifteen words
left after masking, or a text that is more than a quarter gaps — each of these
returns nothing. No photo is shown in the round for the same reason.

The three decoys are drawn from the people the family has **actually talked
about**, and only then from the rest. A round between one real relative and three
names nobody has ever said out loud is not a question: the answer is whichever
name you recognise. Within each group the order comes from a stable hash of the
memory and subject ids, so every family member sees the same four options in the
same places — Swift's own `hashValue` is seeded per process, and "which option
moved since last time" would itself be a clue.

### Finding out that a round is waiting

The app opens on Kerro, and nobody goes looking for a game in a photo gallery, so
the Muistot tab carries a badge with the number of rounds waiting. It is the only
signal, it appears only when there is something to do, and it disappears when
there is not.

The count is capped at nine, because it is not free: knowing whether a memory is
a round means building the round, masking included. A family with eleven waiting
and a family with nine are the same thing to the person looking at the badge.

### What VoiceOver gets

Rule 1 calls VoiceOver part of the product, and it was the one rule with no way
to check it. VoiceOver reads the accessibility tree; XCUITest queries the same
tree, so `MemorizeUITests` is the check: every answer is a named button, "En
muista" exists and leads to the reveal, and the verdict is in words rather than
in a colour or a checkmark alone.

The round needs one thing the other screens do not. **Its content is
deliberately incomplete** — the answer is a gap in a sentence — and a run of em
dashes is read as punctuation or as nothing at all. Spoken, the story would
simply sound as if the name had never been said, and the screen would ask
nothing. The accessibility label puts a word in the hole instead: *"…kun joku
tuli mökille…"*. The test asserts both halves — that the dashes never reach the
label, and that the name never does either.

`performAccessibilityAudit()` runs over the same screens at the default and at
the largest text size, and it found what the screenshots did not: **all four
answers failed the contrast minimum.** They were `.bordered` buttons, and that
style writes its label in the accent colour — blue on its own grey fill. Four
primary controls, below the minimum, on the screen for the one user whose
eyesight this app is built around. They are now plain buttons with a filled
background and a primary-coloured label; the fill still says "button".

Three audit findings are decisions rather than defects and are listed by name in
the test, each with its reason: the card's truncated preview (a teaser, with the
whole text one tap away and all of it in the accessibility label), the photo
tile's capped count badge, and the gallery heading that passes under the
translucent tab bar at the largest size.

### Tone

No score, no streak, no timer, no leaderboard. A wrong answer is stated plainly
and left alone — no "väärin", no red — because the person guessing may be the one
whose own memory is going. These are memories of people who have died. The reward
is that grandmother's memory card says *"Ville tunnisti hänet"*: her sister was
recognised. Nobody wins.

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
- **HTML rather than a list of text.** The point of an export is that the
  archive outlives the app, and a browser is the one program every family
  already has. The same file carries the photos and plays the audio without
  Memorize installed.
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
(`MemorizeUITests/AccessibilitySweepTests`): onboarding, the memories grid and
its empty state, Kerro and its typing view, the people list and its empty state,
a person's card, a photo's card, the ask sheet and settings. It found the same
class of problem in almost all of them, and nearly all of it came from three
system defaults.

Not covered, and honestly so: the paywall (needs a RevenueCat key), the family
view (needs a backend), and Kerro's recording, processing and result states,
which need a microphone and a live pipeline. The fixes below are app-wide
constants, so those screens moved with the rest — but they have not been
measured.

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

**Dark mode is not covered.** The app has never been designed for it — the
launch screen is parchment, no asset has a dark variant, and the accent colour
is deliberately one value for both appearances. Running the sweep in dark mode
would find real problems and they would be the first dark-mode problems anybody
has looked at, which is a different piece of work.

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

**The framed exception is the upsell card.** It keeps its prominent button
because it is not competing for the same act: it sits inside its own tinted card,
it is an offer rather than a step, and its position is deliberate — the moment a
memory finishes is where perceived value peaks (§8.6). A card is its own
decision. If a second card ever appears on one screen, this exception is the
thing to re-open.

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
