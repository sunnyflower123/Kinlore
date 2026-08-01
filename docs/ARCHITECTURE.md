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
| RevenueCat, shared family entitlement | **Done and tested** |
| Audio playback, open questions, relationships | **Done and tested** |
| Paywall | Built — unverified, needs a RevenueCat key |
| Interview loop (questions asked aloud) | **Done** |
| Asked questions (a person asks, the name travels) | **Done** |
| Repo in English | **Done** |
| Moderation (`report`, `block`) | Not started — on the cut list, PLAN.md §5 |
| Demo video | Remaining |

The critical path is open: family and sync work, so media, quotas and moderation
can be built on top of them. The remaining work is parallel and cuttable.

**Verified rules.** Confirmation is one-way, merges are sticky, only the author
edits their own, and another family can neither see nor write. The outbox
survives the app being closed, and a locally changed row is not lost underneath
the remote version.

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

### The client's outbox

Local changes are recorded in an `outbox` queue: operation, target id and
payload. The queue is drained in the background with exponential backoff.

Operations are **idempotent**: everything is an upsert keyed by a client
generated UUID. The same operation twice breaks nothing, which makes retrying
safe without coordination.

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

- The code is long and random, not meant to be read by a human
- It expires, and the owner can revoke it at any time
- Join attempts are rate limited (Cloudflare `ratelimits`, as in Hetkio)
- The family view shows who has joined and when

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
minutes reset or the family goes paid. The same applies to a network error.

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
2. **Family** — members, sharing the invite link, usage.
3. **Audio playback** — the memory card's "Listen in her own voice". Emotionally
   the product's strongest detail and small to implement.
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

Not built:

7. **Settings** — export, account deletion, reporting and blocking. The
   moderation half is on the cut list (§7); export and deletion are not, and
   they are the honest remainder of this list.
8. **Family tree** — a drawn graph. **A trap.** Relationships are lists on the
   person card: the same information, works at the largest text size and is
   readable with VoiceOver. The graph gets built only if everything else is done.

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

### Tone

No score, no streak, no timer, no leaderboard, and "En muista" is a first-class
answer — for this app's user it is the most likely one. These are memories of
people who have died. The reward is that grandmother's memory card says *"Ville
tunnisti hänet"*: her sister was recognised. Nobody wins.

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
- **Tyhjennä tämä laite.** The store, the media, the ladder's state and the
  Keychain identity. Afterwards the app is a fresh install. In a family the
  memories are still on the server and rejoining brings them back; in a local
  archive they are gone for good, and the screen says exactly that in those
  words rather than in a generic warning.

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
