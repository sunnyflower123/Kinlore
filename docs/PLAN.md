# Plan — Shipaton 2026 / Next Gen

Name: **Kinlore** (decided 15 Aug 2026, §10)
Contest: RevenueCat Shipaton 2026, 1 Aug – 30 Sep 2026
**Target category: Next Gen Award** (student category, $15,000). The store route
was a conditional option to be decided on 10 Sep; **closed for good on
24 Aug 2026** — see §2.1. Next Gen is the only target.

---

## 1. What this is

A family's shared memory archive where an old person gets to ramble and the AI
turns it into structure.

The problem: **grandparents know, but cannot explain in a structured way.** They
do not fill in forms, do not tag photos and do not draw family trees. They talk.
Existing album and genealogy apps demand structured input from the one person
who will never produce it, and so the knowledge disappears at the funeral.

## 2. Why Next Gen only

Releasing on the App Store would have opened up the Peace Prize and the Design
Award, but it would cost: an App Store Connect record, the Paid Applications
Agreement (bank and tax details), real subscription products, screenshots, a
privacy policy, App Review and a rejection round — and the deadline would
tighten from 28 Sep to 18 Sep.

On top of starting upper secondary school and running another project, that is
the wrong trade. **The store route is dropped.** That is not settling; it is the
only way to make the magic moment of §4 genuinely good.

What this saves:

| Removed | Effect |
|---------|--------|
| App Store Connect, Paid Applications Agreement | ~1 week + unknown waiting time |
| Real subscription products | RevenueCat **Test Store** is enough — it is designed for exactly this |
| Screenshots, privacy policy, age rating, support page | ~1 day |
| App Review + rejection round | Removes the biggest uncertainty in the schedule |
| Apple 1.2 UGC obligation | Reporting and blocking move to the "nice to have" list |
| Deadline 18 Sep → **28 Sep** | +10 days |

Roughly **two weeks of work removed and ten days added.** The name does not even
have to be locked in advance, because no App Store Connect record is created.

## 2.1 The store route, reopened as an option — 15 Aug 2026, closed 24 Aug 2026

§2 remains the default, but two of the things it priced in turned out not to
exist:

- The Apple account being used already has an **active Paid Applications
  Agreement** with current bank and tax details. The week of paperwork is gone.
  What is left is the DAC7 compliance form, and for this app it is a single
  **No** — the personal-services question ends the flow, because Kinlore sells
  a software subscription and not anyone's labour.
- The **Peace Prize does not judge scale.** Its criteria are Impact and
  Feasibility, and adoption appears only as *"any early evidence of
  usefulness"*. Few users is not a disqualifier; no store release is.

So the store route now costs roughly **6–8 September evenings**, not two weeks:
Apple 1.2 reporting and blocking (cut item 6 of §5 comes back), real StoreKit
products in place of the Test Store, a privacy policy and the App Privacy
answers, and screenshots and metadata.

**The rule that decides it:**

> **On 10 Sep, look at the Next Gen submission. If it is in a state you would
> send as it stands — the app demo-able, the repo clean — then the rest of
> September may go to the store route. If it is not, the store route is
> dropped, and it is not discussed again.**

The order is the point: the safe thing is finished before the optional thing is
started. Shipping does not threaten Next Gen *eligibility* — it is additive, and
the Apple account holder is not a member of the submitting team — but it does
threaten Next Gen *quality*, and Next Gen judges *"technical care in
presentation"*. The prize money is the same and the field is far smaller, so
Next Gen is the target and the Peace Prize is the option, never the other way
round.

If the rule opens the route, the dates are fixed: **17 Sep** is the last day to
submit to App Review — it leaves room for exactly one rejection, not two — and
the app is live by **25 Sep**. Phase F in §3 is unchanged.

Keeping the option open until 10 Sep costs one DAC7 click and locking the app
name and bundle ID before an App Store Connect record exists (§10). Nothing
else, and nothing in August.

**Closed 24 Aug 2026, ahead of its own checkpoint.** The developer decided it
directly — no App Store release, Next Gen only — on a rested day in August
rather than at the 10 Sep sitting, and a rested day is the better place to
decide anything. What follows from the closing: the 10 Sep rule never fires and the 17/25 Sep App Review dates
are void; the 6–8 September evenings the route would have cost go to phase D's
craft and to phase E instead; the DAC7 click is not needed; and the name and
bundle id never meet an App Store Connect record, so the reservation moment
§10 pointed at does not exist. §2's original reasoning stands in full. Do not
reopen this, and do not re-price it — both prices are already written down
above.

## 3. The schedule is built around school

The decisive fact: **upper secondary school starts around 11 Aug.** Before that
there is full capacity; after it, evenings and weekends. One holiday week is
worth roughly three school weeks.

That is why **the heaviest work happens before school starts**, not after. An
earlier version of this plan scheduled the magic moment for the week school
began — that was backwards.

| Phase | Days | Goal | Capacity |
|-------|------|------|----------|
| **A** | 31 Jul – 3 Aug | **Kill the risks.** ASR test on real elderly speech. RevenueCat account + Test Store. ~~GitHub public + licence~~ — moved to the day of submission on purpose, see §5 row 4. | holiday |
| **B** | 4–10 Aug | **Backbone + magic moment.** Photo picking, memories, dictation → transcription → extraction → follow-up questions. The last week of the holiday goes to the hardest part. | holiday, full |
| — | **~11 Aug** | **School starts** | |
| **C** | 11–31 Aug | Person cards + relationships. Confirmation UI for proposals was dropped in favour of the guessing round, which was then cut itself — see §4.1. | evenings |
| **D** | 1–14 Sep | RevenueCat Test Store + paywall. Craft: animations, waveform, empty states, accessibility. | evenings |
| **E** | 15–24 Sep | Testing with a real grandparent — **installed from Xcode on a visit**, see below. Fixes. **Repo in English.** | evenings |
| **F** | 25–28 Sep | **Demo video** and Devpost submission. | weekend |

If phase B succeeds, the rest is downhill. If it does not, everything else is
pointless — which is why it sits in the holiday and not alongside school.

### Phase E does not go through TestFlight

This row said "TestFlight" and contradicted §2, which drops App Store Connect
for want of time. **TestFlight *is* App Store
Connect** — there is no route to one without the other — and it costs more than
the app record. A grandmother is not a member of the developer team, so she is
an *external* tester, and the first build of every version then waits for Beta
App Review. Making her an internal tester avoids the review but means giving a
family member a role on the developer account, which is more access than testing
needs. (Checked against Apple's own documentation on 16 Aug, not from memory.)

None of it is necessary, because of what this test is for. §8 says the open
question is whether an 80-year-old's real voice, in a real kitchen, comes back
well enough to be recognised, and that the three recordings which answer it come
from here. A real kitchen means being in the room — **and in the room, Xcode
installs the build onto her phone directly.** No App Store Connect, no review,
nothing between the build and her phone but a cable.

What it costs instead, so that it is not a surprise on the day: her phone has to
be paired to this Mac once, over a cable, and **Developer Mode has to be turned
on in her Settings** — which takes her passcode and a restart of her phone. That
is done with her, once, before anything is installed. A build installed this way
also expires eventually and has to be put on again, which costs another visit
rather than another submission — the right way round for this.

The fallback, if a visit turns out to be impossible, is TestFlight with her as an
external tester and a day or two of review built into the schedule. It is written
down here so that the choice is made now rather than on 15 September.

## 4. The magic moment — the one thing

> Grandmother presses a big button and rambles for 90 seconds about an old
> photo. The app returns: the memory in her own voice and in readable words,
> attached to the photo; the names and places it heard, each with the
> sentence it was heard in, waiting for a person's yes; the time as she said
> it — and two questions back.

*Reworded 13 Sep 2026.* The first version of this paragraph promised *person
cards for the relatives mentioned, year and place information* and three
questions, and the app built exactly that: after one telling it had made a
moment and named it, put a place on the map, listed two people it had only
heard of, and offered one of them as the next thing to talk about — nothing
the family had confirmed. The magic moment is the same screen and it is
quieter: what the app heard, offered rather than asserted. The arc around it
is *"yksi kerronta, yksi muisto"* (ARCHITECTURE §12, §18, §22, §23; UX §6).

The demo video needs to be essentially this one screen. The judging criterion
says *"meaningful progress toward a working app with clear core functionality"* —
narrow and excellent beats broad and half-finished.

**The original audio is always kept and is playable from the memory card.**
Grandmother's voice is itself the inheritance, not a step on the way to text.

## 4.1 The guessing round — built, then cut

*One person tells a story, the others guess who it was about.* A memory naming
exactly one person was shown to the rest of the family with the name taken out,
and four person cards to choose from.

**It was cut on 16 Aug 2026**, as §5 row 8 said it would be. What it was for and
why it worked is kept in [`ARCHITECTURE.md` §13](ARCHITECTURE.md#13-the-guessing-round--built-then-cut);
this section records the hole it leaves, because the hole is not where it looks.

It was built to answer a real problem: everything in §4 is a **writing** loop,
and nothing gave the family a reason to open a memory that was already written.
That problem is still there. Cutting the round does not solve it; it postpones
it, and a family archive dies unread more often than unrecorded.

**And it took the confirmation mechanism with it.** §4.1 used to say the round
*was* the confirmation UI and a better one — a card with the name already on it
gets tapped "yes" without being read, a blind guess cannot be. That argument was
right, and it was the reason the standalone "confirm this proposal" screen was
never built. So confirmation was the orange proposal row and nothing else —
the weaker instrument the old section rejected — until 30 Aug 2026, when the
blind card took the stronger half back in a cheaper shape: the photograph the
name was heard in, four names, the proposal unmarked among them
(`BlindConfirmation`, ARCHITECTURE §23). Rule 4 in CLAUDE.md carries both now,
with the orange row as the weaker of the two and the answer to a name that
arrived with no face to put in front of anybody.

Why it went anyway: §5 fixed the order in advance so nobody has to choose while
exhausted, and levers 2 and 3 of §10 are two additions that owed a removal. This
is that removal.

## 5. Cut order for when time runs out

It will. This is decided in advance so that nobody has to choose while exhausted.

**Never cut:**
1. The magic moment (dictation → extraction → follow-up questions)
2. RevenueCat Test Store + paywall — a rule requirement, but small work
3. The demo video
4. Repo in English + OSS licence visible in GitHub's About section — **on
   the day of submission, and deliberately not before** (§3 scheduled it in
   phase A and that schedule is superseded, not slipped). On 28 Sep 2026 the
   date moved from 28 Sep to the day of submission.

**Cut in this order, from the bottom up:**

| # | Target | How |
|---|--------|-----|
| 11 | **A question asked by name, and its two notifications** | Built 25 Sep 2026 by the user's decision, an addition with no removal beside it — so it is the first to go. The Kerro tab goes back to offering every question to everyone by dropping the `viewer:` argument in `TellScreen`, and *"Kenelle?"* leaves `AskQuestionSheet`; the columns and `push_token` cost nothing while unused, and the notifications need the paid Apple program before they can arrive at all (SETUP). ARCHITECTURE §11 |
| 10 | **A face on the card** | Built 21 Sep 2026, an addition with no removal beside it like the row under it, so it is the first to go: one `if subject.kind == .person` section in `SubjectDetailScreen` and `FacePickerSheet` with it; `SubjectAvatar` draws the initial on its own when nothing points at a picture, and the four columns cost nothing while unused. ARCHITECTURE §25 |
| 9 | **Colours by the telling** | Built 13 Sep 2026 by decision, as an addition with no removal beside it, which is exactly what §4.1 says an addition owes — so it goes right after the face above it. Hiding it is one condition, `colourable` in `SubjectDetailScreen`; the Worker's route and its counter cost nothing while unused. ARCHITECTURE §24 |
| 8 | ~~**Guessing round**~~ | **Cut 16 Aug 2026.** The isolation claim was half true: the two call sites really were one line each, but the round also owned two files, a model, a table, sync rows in both directions, a check script, a test file and 165 lines of §13 — about 1 100 lines in all. Budget a session, not a line |
| 7 | Family tree / relationships | Person cards without edges. **The drawn tree was built on 13 Sep 2026** instead of cut: on family members' phones only, with the lists on each person's card kept for a grandparent's phone and VoiceOver. Ihmiset opens on it there since the same day, with the list one tap away. Cutting it now means taking out `FamilyTreeView` and the tree/list switch in `PeopleScreen`; the edges on the cards stay. A friend — `friend_of`, 21 Sep 2026 — goes with it: the *Ystävät* section on the card and the band in the tree, while the rows in the table stay readable |
| 6 | Reporting and blocking | No longer mandatory without App Review |
| 5 | **Real invite link and join flow** | **First thing to simplify.** Deep links and join screens are an expensive part. The data model already supports multiple members (`memory.author_id`), so **a demo family can be seeded** — the video shows several relatives' memories on the same photo without the join flow being built |
| 4 | Person cards | Memories only on photos |
| 3 | Uploading photos to the cloud | Local photo picking is enough for the video |

Note the difference: **the concept is not cut, the implementation is.** Shared
family memory shows on the video even if the join flow is seeded — but if the
magic moment is missing, there is nothing to show.

## 6. Design principles

1. **The primary user is whoever wants to tell, often an older person.**
   Dynamic Type up to XXL, VoiceOver, large tap targets. Accessibility *is*
   this app's design.
2. **Never paywall telling.** The paywall limits photos and AI minutes.
3. **Uncertainty is a first-class state.** "Sometime in the fifties" is stored
   as a range.
4. **AI proposes, a human confirms.** A wrong relationship is worse than a
   missing one.
5. **Gaps are shown.** An empty person card is an invitation, not an empty state.
6. **No login screen.** See `SETUP.md`.

## 7. Architecture

**SwiftUI + XcodeGen** ‖ **Cloudflare Workers + D1 + R2**.

A single **`subject`** table with a `kind` (photo | person | place | event), and
a **`memory`** that attaches to any subject. That makes *"write a memory about
this photo"* and *"tell us what grandmother was like"* the same screen and the
same code path. The family tree is the edges between person subjects. Schema:
[`backend/schema.sql`](../backend/schema.sql).

This is the repo's single best argument under the "technical choices" criterion —
it is written out in English in [`ARCHITECTURE.md`](ARCHITECTURE.md).

```
audio → ASR (Finnish) → raw_transcript (kept verbatim)
                             ↓
                     LLM extraction (structured output)
                             ↓
     ┌───────────────────────┼───────────────────────┐
memory.body           mentioned subjects      follow-up questions
(cleaned text)        (confirmed = 0)         (prompt_question)
```

## 8. Risks

| # | Risk | Action |
|---|------|--------|
| 2 | **Finnish ASR on elderly speech.** The whole app rests on this. | **Half done — see below.** The engine was chosen by measurement; the go/no-go was never actually run. |
| 4 | **School takes more time than expected** | The cut order in §5 is decided in advance. The heaviest work is in the holiday. |
| 5 | **The demo video is left to the last evening** | It has its own phase (F). The video is a deliverable, not an afterthought. |
| 6 | ~~**The repo stays in Finnish**~~ | **Done.** Translated, and the boundary is written down in CLAUDE.md so it stays. |

### Risk 2, honestly

This is the one the plan called risk #1 and told itself to close *before any
other code*. What actually happened is worth writing down, because the two
halves are easy to mistake for each other.

**What was measured.** `scripts/asr-bench.mjs` was run over
`scripts/make-synthetic-samples.py` output: three Finnish texts at four
degradation steps, five engines. That chose `gemini-3.6-flash` on 31 Jul 2026.
The same three texts were run again on 30 Aug beside an English set of the same
shape (§10), and that second run's numbers are in `backend/wrangler.jsonc`
beside the setting they justify. As an engine comparison this is sound —
relative ranking is exactly what the generator says it is good for.

**What was not.** The samples are text-to-speech. The generator says so in its
own header: *"TTS does not produce dialect, stammering, self-correction,
overlapping speech, or a sentence trailing off. A real elderly speaker does all
of that. These figures are therefore optimistic."* The tripwire — *below ~80 %
on proper nouns, rethink the concept* — is about absolute quality on real
speech, and no real speech has been scored against it. `samples/LUEMINUT.txt`
has said what is needed from the beginning: three recordings of an actual
elderly voice.

**And the optimistic numbers already missed both bars.** 68 % on Finnish proper
nouns against a tripwire of 80 %, and a word error rate of 37.8 % against the
bench's own *"above 30 % is not usable"*, in the run of 31 Jul; 65 % and 37.3 %
in the run of 30 Aug. On audio that is kinder than the real thing.

**Why the concept was not dropped anyway**, which is a decision and should read
like one: the app is built for exactly this. The original audio is kept forever
and is playable, so nothing rests on the transcript being right. The raw
transcript is kept beside the cleaned text. Names are checked by the teller in
the seconds after telling, which is the only moment anybody still knows what was
said — and, since [ARCHITECTURE.md §17](ARCHITECTURE.md), can be corrected from
the person's card long afterwards. One proper noun in three being wrong is the
premise the name-correction step was written for, not a surprise.

**What is still open.** Whether an 80-year-old's real voice, in a real kitchen,
comes back well enough that the family recognises what she said. Three
recordings answer it, the phase E test with a grandparent is where they come
from, and until then this row is a measurement that has not been taken rather
than a risk that has been retired.

On the weekend of 26–27 September 2026 my grandparent spoke into the app on a
real iPhone, running the production build against the production Worker. A
measured result of that session does not exist.

**One sentence from it was kept**, reported on 30 Sep 2026:

> *"Mistä tiedän että se on tallessa?"* — How do I know it's saved?

That is the question the visit below says no number answers, whether the
teller believed the memory was saved, and the app had no answer to give. Between
stop and the result, `ProcessingView` shows *"Kuuntelen mitä sanoit"* and then
*"Järjestelen muistoa"* over a spinner, for as long as the two calls take —
`AppServices` waits four and a half minutes for both on a telling of a minute,
and half an hour at most on the longest — and nothing on it says the voice is
kept. Nor is it yet: the recording sits in the temporary directory until
transcription returns, and only then does `persistAudio` move it where a memory
can point at it. After a spoken first telling that raised a question, the
conversation begins with no *"Muisto tallennettu"* in between.

Fixed the same day: at stop the recording leaves tmp for a waiting folder in
Documents that the launch sweep also reads (`RecordingRecovery.keep`), and only
once that move has succeeded does the screen say *"Äänesi on tallessa tässä
puhelimessa"*, above the spinner. The conversation's missing *"Muisto
tallennettu"* is left as it is.

A separate change, not drawn from that session: since 30 Sep 2026 the idle
screen's reassurance says *"Puhu ihan rauhassa ja kuuluvalla äänellä"* where it
said *"vapaasti"*. The words are written by a model that hears only the
recording, and what it cannot make out it cannot write down: a reply with no
words leaves the telling as audio alone, and in the conversation after the
first telling `AnswerWatch` counts anything under −40 dBFS as silence. It is
said before the press rather than during the recording, which has no room left
at the largest size, and it is not there when a photograph stands on the card,
which drops the reassurance altogether. A hint that appears only when the voice
is quiet would reach the one who needs it and spare everyone else, but it needs
a threshold, and none has been measured: the three recordings in ARCHITECTURE
§10 put the room at −51 to −64 dBFS and speech near −15, and none of them is
known to be a quiet voice.

### The visit that takes the measurement

Written before the day rather than on it, because half of what follows cannot be
done afterwards at all.

**Before the door.** This sentence used to assert the whole thing; it has two
halves and only one of them can be checked from here.

**The Mac's half is measured, 12 Sep 2026.** The app compiles for arm64 —
`BUILD SUCCEEDED` with signing skipped. Signing does not resolve by itself: a
device build needs a development team, which `project.yml` does not name and
`ios/Signing.xcconfig` takes from an untracked `ios/Signing.local.xcconfig`;
[SETUP.md](SETUP.md#ios-app--signing-for-a-real-device) says how to write that
file and what a build does without it. That was worth measuring because
**nothing in this project had ever been built for a device**: every build in its
history targeted the simulator, so §3's promise that "in the room, Xcode
installs the build onto her phone directly" rested on nobody having tried it.

**Her half cannot be measured from here**, and it is the part to do with her,
once, before anything is installed: the phone paired to this Mac over a cable,
and Developer Mode turned on in her Settings — which takes her passcode and a
restart of her phone. Plus there is something to write on. `scripts/asr-bench.mjs` says what it
needs and has said so from the start: three real samples, and *"the correct text
for each by hand"* beside them. `samples/` is gitignored — her voice does not go
into a public repo.

**Ask before the microphone, not after.** She is told where the audio goes — to
our own server, which turns it into text — and whether any of it might be heard
in a demo video in September. If the answer is that none of hers will be, that is
decided in the kitchen, not in the edit.

**The cold handover.** Hand her the phone and say as little as it takes. Start a
clock. **Every question she asks out loud is a sentence missing from a screen**,
so write each one down in her words — those are the findings, and they are worth
more than any opinion offered afterwards, including hers. Help only once she has
asked twice, or after two minutes, whichever comes first.

**The transcript is written in the room.** Nobody can reconstruct later what she
actually said, which is the premise rule 3 already rests on — and without a
correct text the recordings cannot be scored at all, so the measurement stays
untaken with three files to show for it. Write it while she is still there to be
asked "mitä sanoit siinä".

**What the numbers then answer**, against the tripwires already in this section:
80 % on proper nouns and 30 % WER, now on speech that is not kind. Above them,
risk 2 is retired. Below, the answer is the one this app already built —
correction in the seconds after telling, and from the person's card afterwards
(ARCHITECTURE.md §17) — and the honest conclusion is about the engine rather than
about the concept.

**What no number answers.** Whether she pressed the button a second time without
being asked, and whether she believed the memory was saved. Both are worth a line
in the notes the same evening, while it is still true rather than remembered.

**And one question for the room rather than for her**, added 9 Sep 2026. Ask
whoever else is there, in these words:

> *"Kun te olitte siinä tilaisuudessa muistelemassa — mikä olisi saanut teidät
> kertomaan?"*

The question has an antecedent and it is where this whole product came from: a
memorial for a grandmother, about twenty-five people, plenty of photographs on
the table, and nobody able to tell any of it properly. That is §1's premise one
level up — a room that knows collectively and cannot get it out — and it is the
densest hour of memory a family ever has.

Ask it because of what it is *not*. It does not ask what the app should do,
which is a question people answer with features they have seen elsewhere. It
asks **what was in the way**, in a room they were actually in, and the answer is
a fact about people rather than a preference about software. Nobody in this
project knows it yet, including the person who was there.

It costs nothing: the visit is already in the schedule, and unlike the
recordings this needs no setup, no clock and no transcript — one line in the
same evening's notes. Write down their words, not the paraphrase.

What hangs on it: whether the gathering is a *mode* this app should ever have
(one phone round a table, one photograph, several tellings — `memories(for:)`
already models it and no screen does), and whether the group size this is
metered for, four to eight, is the right size at all. Both are large decisions
and neither should be made from a founder's memory of one afternoon.

## 9. The core of monetisation

**The payer is not the beneficiary.** Grandmother does not buy a subscription —
the grandchild does, and the whole family channel opens for every member.
RevenueCat grants the entitlement to the buyer; the backend maps it to a
channel-level right (`family.entitlement`).

The right moment for the paywall: **as soon as the first AI-structured memory is
finished.**

## 10. Open decisions

- ~~**Licence.**~~ **Decided: Apache-2.0**, canonical text in `LICENSE`, verified
  identical to the reference copy apart from the copyright line. AGPL-3.0 was
  the alternative and would have made commercial copying unattractive, but it is
  effectively incompatible with App Store distribution — and this plan
  deliberately leaves a store release open for v1.1 (see `SETUP.md`). The
  protection AGPL buys matters for server software; here the moat is in the
  product decisions, not the code.

  This row said MIT and was closed on 16 Aug 2026. It was reopened and changed
  on 17 Aug at the author's decision — Apache-2.0 says the same thing about
  copying and adds an explicit patent grant, which costs nothing here. The
  copyright line is `Kinlore contributors` rather than a personal name. That is
  deliberate; do not replace it with one.
- ~~**Name.**~~ **Decided 15 Aug 2026: Kinlore.** *Lore* is knowledge that moves
  by being told rather than written, which is §1's claim in one word, and *kin*
  scopes it to the family without promising genealogy — so row 7 of §5 can be
  cut without the name turning into a lie. Backups, in order: *Lorehouse*,
  *Long Ago*. Bundle ID `com.kinlore.app`, changed in `project.yml`
  on 15 Aug together with the target, scheme, source directories and the
  `kinlore://` invite scheme. **RevenueCat needed nothing**, which is worth
  writing down because the opposite was assumed first: a Test Store app is
  identified by its API key and has no bundle-id field at all — *"Test Store
  works automatically with the RevenueCat SDK, no additional configuration is
  required beyond using your Test Store API key."* The bundle id becomes a
  RevenueCat field only when an **App Store** app config is added — which,
  with §2.1 closed on 24 Aug 2026, never happens. So the rename cost nothing
  here at all.

  The Cloudflare worker, D1 database and R2 bucket keep the name `memorize` on
  purpose: a bucket cannot be renamed, only recreated empty, and rule 3 of
  CLAUDE.md lives in that bucket.

  Two of the five names this list used to carry — *Heirloom* and *Kinfolk* —
  are taken outright, by apps doing this same thing (*Heirloom4Life: Voice
  Keeper*, *Kinfolk – Connect with family*). They had never been checked.

  **How to check a name**, because it is cheap and was skipped for a year:
  `itunes.apple.com/search?term=<name>&entity=software&country=<cc>` returns a
  storefront's apps as JSON, and an exact `trackName` match means the name is
  gone. It has two blind spots, and both of them bit during this exercise:

  1. **Reservations are invisible.** A name reserved in App Store Connect and
     never shipped does not appear in search — likely for any short, desirable
     word.
  2. **The API sees only the App Store.** *Saga* looked free in seven
     storefronts, while Saga plc sells insurance, cruises and personal alarms to
     2.7 million over-50s in the UK — the same demographic as this app. *Vellum*
     looked free while being well-known book-formatting software sold outside
     the store.

  So search availability is a filter, never a clearance. The authoritative check
  happens once, when the record is created and the name is reserved — which is
  why all three names were to travel to that moment rather than one. With §2.1
  closed (24 Aug 2026) no record is ever created, so the question never gets
  its authoritative answer and never needs one: a name only has to be free on
  the store if the app goes there.

  And the name does not have to explain the product. The App Store subtitle and
  the Devpost tagline do that, and the demo video explains more in ten seconds
  than any name can.
- **ASR implementation.** Resolved by the phase A test.
- ~~**A map of the places.**~~ **Decided 17 Aug 2026: no map in v1.** The data
  half exists and keeps accumulating — `subject` carries `lat`, `lon` and
  `geo_precision`, and place names are looked up on the device as they are
  told — so deciding the screen away loses nothing that is being collected.
  The decision is the removal that paid for the *"Uutta perheeltä"* section
  (docs/UX.md §6): the guessing round's cut left the reading loop unanswered
  (§4.1), and an archive that is read is worth more than an archive that is
  drawn. The §5 row 7 slot the map would have taken stays empty. If a map
  returns in v1.1, read `ARCHITECTURE.md` §18 first: the lookup always
  answers, a confident wrong answer is indistinguishable from a right one,
  and a map that draws every answer as a pin publishes guesses as fact.

  **The decision stands, and something narrower shipped anyway — 10 Sep 2026.**
  A place subject's own card now draws its stored coordinate (`PlaceMapCard`).
  That is not the row above being overturned: what was refused is *a map of the
  places*, a screen you go to and browse, and there is still no such screen.
  What shipped reads a column on one subject that was already being collected,
  on a card that already existed.

  **And the condition this row set is the reason it was allowed.** The sentence
  above is not a prohibition, it is a prohibition with a gate — read §18 first,
  because a map that draws every answer as a pin publishes guesses as fact. The
  gate was honoured rather than argued past: a pin only for `exact`, a circle at
  the right scale for `town` and `region`, and **nothing at all for `unknown`**,
  because an empty map of the wrong sea reads as an answer. The numbers sit on
  `GeoPrecision` rather than in the view, and `scripts/place-map-check.swift`
  asserts them with no simulator and no network. That is rule 5 made visible
  instead of rounded away.

  **The payment is not reneged.** This row's removal bought the *"Uutta
  perheeltä"* section, and what it spent was the §5 row 7 slot — which is still
  empty, because a card is not a phase. If a browsable map is ever proposed
  again, it owes its own removal and this paragraph is not a precedent for it.

  **Proposed again and built, 21 Sep 2026 — with the removal still owed.** The
  founder asked how the archive could be browsed on a map and then asked for
  it to be started, and it was built the same day in the cheapest shape it
  has: `PlacesMapScreen`, one screen on the album's own stack, every confirmed
  place with a coordinate drawn by the card's rule and each one a chip that
  opens the card the Paikat list already opens (ARCHITECTURE §18). It reads
  what this row said would keep accumulating and adds nothing to the Worker,
  which is why it took a session rather than the phase this row priced. What
  this row asked for and did not get is the removal: nothing was taken out
  beside it. Which addition pays is the founder's decision, and this
  paragraph does not make it — it records the debt as open, so that the next
  reader does not take a built map for a paid one.

  **Grown again on 25 Sep 2026, and the debt left open by decision.** The
  founder asked for the map to be somewhere a person finds it without looking
  — the album's top bar, in every album — and reported that the land around a
  point could not be looked at without the point moving with it. Both were
  answered on the one screen, with no second map: looking moves nothing, and
  *"Muuta sijaintia"* turns the same map into an editor where a tap puts the
  mark down. A point somebody places now carries who and when, the first
  columns this row's map has ever added to the Worker, and the map gained an
  aerial photograph and, in its editor, a search by name (ARCHITECTURE §18).
  Asked what should go to pay for it, the founder answered that nothing is
  removed now. So the removal is still owed, and it is now owed by a decision
  somebody took rather than by an oversight nobody noticed.
- ~~**Prices.**~~ **Changed 28 Sep 2026: a month at 39.99 and a year at
  149.99, each bought by one member for the whole family. The archive for
  ever goes and the monthly plan comes back.** That reverses the two
  central choices of the 12 Sep decision below, which is kept as written
  because it is the record of how the shape was reached. Four things in it
  no longer hold. The gift ratio of 1.6 and the 54 € net belonged to the
  archive for ever and describe nothing on sale. The fair-use worst case of
  10.8 € a year now stands against a yearly price three times the old one,
  not against a single payment that had to cover five years. The case
  against a monthly plan is an argument the founder has overruled, not a
  rule this file keeps. And phase E's question, whether the one real
  grandchild would pay eighty once, has no product behind it. The
  perpetual-purchase path described below stays in `entitlement.ts`, with
  no product in the offering to exercise it.

  **Done in the dashboard the same day.** `monthly_3999` (a monthly
  subscription at 39.99) and `yearly_14999` (a yearly subscription at
  149.99) were created, attached to the entitlement, and put into the
  `default` offering's `$rc_monthly` and `$rc_annual` packages, and
  `$rc_lifetime` was taken out of it once the redrawn paywall was
  published. `yearly_50` and `lifetime_80` join `yearly`, `lifetime` and
  `monthly` as products attached to no offering. The paywall has two
  cards: *"A year for the family / Billed once a year"* first, badged
  *"BEST VALUE"* and selected by default, then *"A month for the family /
  Billed every month"*. Each shows RevenueCat's price-per-period variable
  rather than a typed price, so a card cannot disagree with its product.
  The Finnish locale gained both cards, and its subtitle, which still
  promised *"Rajoja ei ole"* after the English had dropped *"No limits"*,
  now uses the offer card's own sentence. ARCHITECTURE §6 and §1's paywall
  row were rewritten the same day from the editor's computed styles; the
  app's pixels have not been measured since the redraw.

  One thing learnt on the way, twice. The builder writes an edit into
  whichever of a text's *Default* and *Selected* tabs was clicked last,
  whatever the panel shows after moving to another component, and an edit
  in *Selected* creates an override with no Finnish, which the builder
  reports only as a missing localisation. Click *Selected* and then
  *Default* before typing, and read the canvas back afterwards.

  **Decided 12 Sep 2026: two purchases, each made once — a
  year at 50 € and the archive for ever at 80 €. The monthly plan goes.**
  Free stays as it is and as `wrangler.jsonc` has it: 20 photographs in
  total and 10 minutes of transcription a month, per family. On the Test Store the
  numbers are nominal and read in US dollars — it has no currencies
  (ARCHITECTURE §6) — and they are what the paywall shows in the video.

  This row read *"~€9.99/month or €59.99/year"*, and the monthly plan was
  what was wrong with it. The photographs arrive in a burst — a shoebox is
  digitised in a month — and after that what is left is telling, which the
  free tier nearly covers, and reading, which is free for ever because a
  downgrade never deletes (ARCHITECTURE §6). A sensible family pays for one
  month and cancels, so a monthly plan earns from the family that forgets
  to, and that is not a product this app wants to be.

  **Metering was considered and refused** — photo packs, minute packs, a
  price per unit — for three reasons. A photograph costs about a thousandth
  of a cent a month to keep (R2, ~0.6 MB at 2048 px), so a price per
  photograph prices nothing and makes a family count photographs at the
  kitchen table, when the whole idea is *put everything in*. A price per
  minute lands on the teller and not the payer (§9): *"minutes left"* would
  sit on grandmother's screen, which keeps rule 2 to the letter and not in
  spirit. And consumable credits are a ledger the backend does not have —
  grants, pooling across the family, refunds, and a check for each — where
  `entitlement.ts` is built for one tier and one date.

  **What the shape is for is a gift.** The category's two survivors,
  Storyworth (69–199 $ a year, its help page read 21 Sep 2026) and Remento
  (99 $ a year), both sell a gift year with a printed book at the end, and
  neither meters anything. Kinlore has no book, so its year sits below
  theirs. Eighty once against fifty a year is a ratio of 1.6, which is what
  makes the archive-for-ever the one most people take, and that is the
  intended outcome: nothing to cancel and nothing to lapse. Rounded prices
  because a gift is a rounded sum; Apple has allowed rounded endings on
  every purchase type since 2023. Net of Finnish VAT at 25.5 % and Apple's
  small-business commission at 15 %: 34 € from the year, 54 € from the
  archive.

  **The running cost that matters is telling, and a one-time price needs a
  ceiling for it.** Transcription costs about 0.3 c a minute (Gemini 3.6 Flash
  through OpenRouter: 0.75 $ per million audio tokens at 32 tokens a second,
  plus the text out) and everything else but colouring rounds to nothing — a
  thousand photographs are a cent a month. So the paid archive carries a fair-use
  ceiling of **five hours of transcription a month per family**, the same for both
  purchases so that there is one rule. Worst case 10.8 € a year against the
  54 € net, which the price covers for five years; a realistic twenty
  minutes a month is 0.72 € a year, which it covers for decades. **The
  ceiling is a sentence and not code.** Nothing enforces it: `quota.ts`
  reads the paid tier as unlimited. Since 26 Sep 2026 the app's own words
  are true either way — the offer card and Help say the paid archive has
  *more* transcription time (*"enemmän litterointiaikaa"*), where the card
  used to say *"rajoja ei ole"*; and the Perhe screen's usage rows tell a
  paid family what it has used, where both used to say *"rajaton"*. The
  paywall caught up on 28 Sep 2026: its subtitle said *"No limits"* and
  now carries the offer card's *"More room for photographs and more
  transcription time"*. It is RevenueCat dashboard copy and not in this
  repository. When the ceiling becomes one number in `quota.ts` (v1.1),
  no screen has to change with it, and `quota-check.mjs` grows a case.

  **Colouring is a second running cost, and on the paid archive it has no
  ceiling either.** Added 13 Sep 2026 (ARCHITECTURE §24): about 3.4 c a
  round, the price of eleven minutes of transcription. The free tier gets five a
  month on a counter of their own, and `quota.ts` reads the paid tier as
  unlimited here as well. A hundred colourings are about 3 € of the archive's
  54 € net; nothing yet stops a thousand.

  **The code for a perpetual purchase exists, and one path in it is worth
  knowing.** `entitlement.ts` reads a null `expires_at` as perpetual, the
  two-payer rule keeps the furthest date and a perpetual one is the
  furthest, a refund revokes it through the webhook like any other
  (CANCELLATION with `CUSTOMER_SUPPORT`), and `entitlement-sync-check.mjs`
  pins the perpetual case. But **the webhook does not grant it**: a
  `NON_RENEWING_PURCHASE` event carries no expiry, and `handleWebhook`
  ignores an event with neither an expiry nor a revocation, deliberately, so
  that a null cannot end a tier the event was not about. The
  archive-for-ever is therefore granted by `/entitlement/sync` — the app
  reports the purchase from the paywall, and again at launch and on
  returning to the foreground — and by reconciliation, which asks
  RevenueCat directly. That is enough, because the buyer is in the app when
  they buy; it is written down so that nobody reads the webhook's
  `no_expiration` as a defect, or the missing grant as covered.

  **Done in the dashboard the same evening, with one thing learnt on the
  way.** A Test Store product's price is fixed when the product is created
  — the form says so, and the product page has no control to change it —
  so a new price is a new product. `yearly_50` (a yearly subscription at
  50) and `lifetime_80` (a non-consumable at 80) were created, attached to
  the entitlement, and put into the `default` offering's `$rc_annual` and
  `$rc_lifetime` packages; the `$rc_monthly` package was removed. The old
  `yearly` (79.99), `lifetime` (99.99) and `monthly` (9.99) products still
  exist, attached to no offering, and can be archived once nothing refers
  to them. The paywall drawn that morning (ARCHITECTURE §6) was redrawn as
  a draft with the two packages — *"The archive, for ever / One payment.
  It never ends."* above *"A year for the family / Billed once a year"*,
  the badge on the first — and given a Finnish locale that uses the app's
  own words where it has them (*"Avaa koko arkisto"*, *"Kertominen on
  aina ilmaista. Sitä ei rajoiteta koskaan."*). Those words live outside
  `localisation-check.mjs` and every audit, so the English screen is
  screenshotted by hand before filming. Publishing the draft is a button
  the developer presses; §6's paragraph on the paywall is rewritten from
  the pixels once it has been, and §1's paywall row with it.

  Whether fifty or eighty is too much for a first purchase cannot be
  answered here: there are no users, and no money moves before a store
  listing (§2.1). What can be said is that the buyer has already seen the
  app work on the free tier, that the offer appears after a finished telling
  and never before, and that not buying loses nothing. The measurement is
  phase E: ask the one real grandchild whether they would pay eighty once
  for this, and write down their words rather than the paraphrase.

  **History, kept because it explains the shape.** Two products stood here
  from 16 Aug 2026, when a third was removed: the Test Store had `monthly`,
  `yearly` *and* `lifetime` in its `default` offering — the trio RevenueCat
  proposes when a project is created — so `lifetime` had arrived as a
  default and not as a decision, and an undecided price is worse than a
  decided one. The note left behind said the case for it was real and
  emotional rather than commercial, *"this is forever"* suiting an archive
  better than a monthly bill, and to price it here first if it ever won. It
  won, and it is priced here.
- **The cloud — custody, not only adoption.** Raised 15 Aug 2026 as a question
  about whether anyone would join: who hands a dead parent's voice to somebody's
  server? **Reopened 16 Aug 2026 as the larger half of the same question** —
  not whether they will hand it over, but what happens when what they handed
  over is taken. A breach here does not spill email addresses. It spills a
  family's memories of dead relatives, in their own words and in their own
  voice, and the person who could consent to that is often the one who has died.
  Undecided. It was attached to the 10 Sep sitting, which went when §2.1
  closed (24 Aug 2026), so it stands on its own: v1's answer is lever 3 of
  §10, built and since proven through production, and the custody question —
  Apple as holder via an iCloud packet — remains a recorded v1.1 alternative,
  not a September decision.

  **What is in the cloud today**, measured rather than assumed:

  - `memory.body` and `memory.raw_transcript` are D1 columns, so the words of
    every memory are on a server the moment sync runs. R2 holds the files.
  - The audio leaves the device even with R2 off, because transcription happens
    in the Worker — it goes as a base64 `input_audio` part (`transcribe.ts`).
    Rule 7 puts the model key there and nowhere else. **No arrangement of the
    storage changes this**, which is the fact that rules out most of the easy
    answers below.
  - So does a photograph somebody asks to colour, with the memories told about
    it (`colourise.ts`, since 13 Sep 2026) — on that request only, said at the
    button before anything is sent, and never from a phone kept to itself.
  - What keeps those words out of somebody's training set is one flag,
    `provider: { data_collection: "deny" }`, and rule 8 says it is unconditional
    rather than a per-call choice — "as a flag it would be forgotten on some
    call". That is a rule about *every* request, which reading cannot keep:
    there are three call sites today and the fourth will be written in a hurry.

    It also cannot be checked by making a request. A real call costs credits,
    and the one thing a check must never do is send a family's words upstream
    to prove they are being protected. So `scripts/data-collection-check.mjs`
    builds the request and does not send it: `complete()` is imported straight
    out of `openrouter.ts` — Node runs TypeScript as it is — and `fetch` is
    replaced with something that keeps the body. What is asserted is the actual
    bytes the Worker would have sent, on a plain call, a structured one and one
    carrying the recording itself, plus that the key is in the header and in
    neither the body nor the address.

    **Shown to be load-bearing** twice. Rebuilding `body.provider` in the
    structured branch instead of adding to it — the realistic way this breaks,
    since that branch already reaches into the object — reddened only the
    structured case. Turning the rule into an option with a safe default
    reddened only the case that asks for collection and is refused: every
    existing call site would still have looked correct, which is precisely
    what rule 8 predicts.
  - **Workers Logs was a third store, and nobody had counted it.** Found and
    closed 16 Aug 2026. `observability` is on in `wrangler.jsonc`, and
    `extract.ts` logged the first 300 characters of the model's reply — the
    structured version of what had just been told — while `openrouter.ts` logged
    300 characters of the upstream error body, which on several provider errors
    quotes the request back. Rule 9 of CLAUDE.md sent both there deliberately:
    it says the cause of an error never reaches the *client*, and it was read as
    though the log were not a place. It is a place. It is the one place a family
    cannot export, cannot delete with *"Tyhjennä tämä laite"*, and never agreed
    to. All three sites now log shape, status and codes; `worker.ts` logs the
    error's name and message, which puts a standing rule on the messages —
    an error message must not interpolate content.

    A standing rule kept by reading is kept until somebody stops reading, and
    the leak was one interpolation. `scripts/leak-check.mjs` now drives the
    failure itself: a Worker of its own with **no key**, so `complete()` throws
    before it touches the network — no request, no credits — through exactly the
    same `failure()` a real upstream error takes. It asserts that the app is
    told `upstream_failed` and nothing else, that the failure did reach the log
    at all (an absence in an empty log is not evidence), and that a transcript,
    a name being corrected and the audio appear in neither place.

    Load-bearing, twice. Putting the 16 Aug line back — 300 characters of the
    telling into `console.error` — reddened the log half and left the client
    half green, which is exactly how the original bug presented: the app never
    saw it. Handing the cause to the client instead reddened the client half
    alone.
  - **A local mode already exists.** `Session.mode` has `.local`, and sync is
    gated on `.inFamily` (`Session.swift`). The machinery for "nothing leaves"
    is built.
  - But onboarding offers **two** choices, *Aloita perheen arkisto* and *Liity
    kutsulinkillä*, and nothing else. The only place the user is ever told the
    audio leaves the phone is the microphone permission prompt — which comes
    *after* the archive has been created. The choice is asked before the
    consequence is explained, and that part is the order rather than the
    architecture.

  **The realistic attack paths, in order of probability.** Worth writing down
  because not one of the three is fixed by moving the data somewhere else:

  1. **A secret in the public repo.** By far the likeliest. Rule 7 exists for
     this, and it is a discipline rather than a technology.
  2. **The Cloudflare account.** A password or an API token. Two-factor auth and
     scoped tokens are the entire defence, and they cost minutes.
  3. **The Worker's own auth.** In reasonable shape: the member secret is hashed
     specifically so that a database leak grants no direct access (`auth.ts`),
     and `family_id` is checked on every query rather than only at join time
     (ARCHITECTURE §3).

  **This entry used to call end-to-end encryption "incompatible with server-side
  transcription". That was wrong**, and it was wrong in the direction that
  closed off the best answer. It conflated two different things: data in transit
  for processing, and data at rest. **A breach dumps the database. It does not
  dump audio that passed through a Worker in June.** So nearly all of the
  protection is available without touching the ASR path at all.

  And it is available because **the server never reads the content**. Checked
  16 Aug 2026 against `sync.ts`: memories are stored and echoed back, the only
  conditions on `body` are emptiness tests, and the quotas count seconds and
  photo rows rather than words. Encrypt `body`, `raw_transcript` and the R2
  objects on the device under a family key the server never sees, and what a
  dump yields is UUIDs, sequence numbers and timestamps.

  Two things would have to be solved and both are small: the coordinate rule
  compares `subject.title` to decide whether a rename invalidates the point, so
  it would compare a hash instead; and `display_name` is joined server-side onto
  every memory and question, so either the names stay in clear or the client
  resolves them.

  **One thing would not be small, and it is the whole decision:** losing the key
  loses the archive — for everyone, permanently, as ciphertext nobody can open.
  Rule 3 keeps the original audio because the speaker may no longer be around to
  ask, and an archive that cannot be decrypted has failed rule 3 more completely
  than one that was never encrypted at all. The key would live in the Keychain
  under `kSecAttrSynchronizable`, the mechanism ARCHITECTURE §4 has already
  verified survives deleting the app, and travel in the shared invite *text*
  rather than in the server-issued code. That is a mitigation and not an answer,
  and it should be weighed as one.

  Four levers, in rising cost:

  0. ~~**Hygiene.**~~ **Done 16 Aug 2026.** The logs, and the account: two-factor
     on Cloudflare and on the GitHub account it signs in through. That second
     one is the part worth writing down, because it was nearly missed — this
     Cloudflare account uses GitHub social login, so GitHub is the door and
     Cloudflare's own 2FA sits behind it rather than in front. The same account
     owns the repository, which makes it paths 1 and 2 in one place. Minutes,
     not evenings, and the only lever that touches either path.
  1. ~~**Say it in onboarding.**~~ **Done 16 Aug 2026** (`a047273`).
     `WhereMemoriesGo` sits on both paths, creating and joining, and says that
     the recording is sent for transcription and that the original audio is
     kept. It repeats the microphone prompt's own sentence rather than
     paraphrasing it, and it says what happens rather than what does not — for
     an 80-year-old this is a dignity question as much as a privacy one, and
     informed consent is the whole of it. `testOnboarding`,
     `testCreateFamilyForm` and `testJoinFamilyForm` pass at both text sizes.
  2. ~~**A third option: "Vain minulle, tälle puhelimelle."**~~ **Done 16 Aug
     2026** (`df65d5b`). Asked on the create form as *"Keiden kesken"* rather
     than as a third button on the screen before it, which has room for two at
     the largest text size and no more. `local_only` outlives the launch and
     beats the configured address; `SyncEngine` was already gated on
     `.inFamily`, so the queue simply never runs. It says plainly that the audio
     *still* travels for transcription — *"Äänitys lähetetään **silti**
     palveluumme"* — because fixing the barrier with a promise that is not kept
     would be worse than the barrier.

     **That sentence stopped being true on 24 Aug 2026** (`0c68d76`,
     `192bbe9`). Once a build carried the production address, a kept-here
     archive had no member the server knew, so its transcription could only
     ever answer 401. The attempt is now skipped
     (`TellViewModel.stopAndProcess`) and the notice says what happens
     instead: nothing is sent, nothing is written down, and the memory can be
     written by hand.

     **No longer a question since 30 Sep 2026.** The family is the default,
     and the single-phone archive is a quiet button under *"Luo arkisto"*,
     *"Pidä muistot vain tässä puhelimessa"*, whose confirmation carries that
     notice before *"Vain minulle, tälle puhelimelle"* sets `local_only`.

     **Two things it does not do**, both deliberate and both worth knowing
     before this is called finished:

     - **It is not reversible from inside the app.** Nothing turns a
       single-phone archive into a family one; the only way back is *"Tyhjennä
       tämä laite"*, which clears the answer along with everything else and
       offers the export first. That is defensible for v1 and it is not
       obviously right — a Settings row that hands the archive to a new family
       is the honest version, and it is not built. **Built 29 Aug 2026**
       (`04efe50`): that row now leads to `EnableSharingScreen`, one-way, and
       the rows already on the phone travel with it (UX.md §11.1).
     - **It does not encrypt anything.** What stays on the phone stays because
       nothing sends it, not because anything is unreadable. That is lever 3.
  3. ~~**Encryption at rest under a family key.**~~ **Built 16 Aug 2026**
     (`eec08b6`, `6469de2`). `FamilyKey` makes a 256-bit key when a family is
     created and carries it to everyone else inside the invitation; `body`,
     `raw_transcript`, subject titles, question text and the R2 objects are
     sealed on the device. The store on disk stays plaintext — it is behind the
     device passcode and it is what the export is written from — because a
     breach dumps the database and not the phone. Titles seal deterministically
     so that `sync.ts` can still tell a rename from a re-push without a schema
     change; what that leaks is exactly what the comparison already needed.

     **It is not end-to-end, and it must not be called that where a user can
     read it.** Five things stay outside it, each for a named reason:

     - **Transcription still sends the recording in clear.** Rule 7 puts the
       model key in the Worker and a model cannot write down speech it cannot
       hear. What lever 3 changes is what is *left behind* — the rows and the
       objects, which is what a dump contains.
     - **Colouring sends the photograph in clear**, with what was told about
       it, for the same reason: a model cannot colour a picture it cannot see.
       Only when somebody asks, and the colouring that is kept is sealed like
       any photograph (ARCHITECTURE §24).
     - **Extraction sends the transcript in clear**, with the title, date and
       place of the subject it is filed under, the names already linked to it,
       the questions still open on it and, since 19 Sep 2026, the photograph
       of a photo subject (`ExtractionContext`, ARCHITECTURE §12). A model
       cannot structure words it cannot read, and `/extract` stores none of
       it.
     - **The invitation carries the key**, so whatever app delivered that
       message has it. The server does not, which is the design; that is a
       smaller claim than end-to-end and `InviteShare` states it where the
       invite text is built.
     - **Place coordinates stay plaintext beside their sealed titles** — a
       point is a name in different clothes, and this one is a decided v1
       leak, not a necessity: the Worker's range check reads the numbers and
       the columns are `REAL`. The reasoning and the v1.1 sealing route are in
       ARCHITECTURE §18 (finding M19, decided 24 Aug 2026).

     **The round trip ran on 24 Aug 2026 — the day the Worker deployed — and
     passed whole.** `scripts/lever3-roundtrip-check.swift` drives the app's
     own transforms (`SyncPayload.sealed`, `SyncPullReply.opened`,
     `FamilyCrypto`) as two identities against the real Worker: the key
     crossed only in the invite text, every stored text carried the seal and
     none of the told words, the R2 bytes travelled sealed, and the second
     identity opened everything byte for byte. Production D1 was read back
     directly as well: the stored body begins `k1.`. This row is now a thing
     that is working, not merely built — and the check runs against local
     `wrangler dev` in verify.sh so it stays true.

     The timing was luck worth naming: there is **no production data**, so this
     needed no migration. Landing it in v1.1 would have meant re-encrypting a
     live archive.

  **Two alternatives were raised on 16 Aug and are recorded here rather than
  built.** Both were attempts at the same instinct, and both trade worse:

  - **One device, nothing shared at all** — the family gathers round
    grandmother's phone and does the telling and the guessing in the room. It
    takes the breach risk to zero and buys a worse risk with it: the archive
    then exists in exactly one place. A stolen or drowned phone is final, and
    she may not be there to tell it again. A breach is humiliating and
    notifiable, and the memories still exist the next morning; loss is the one
    failure this app was built against. It would also collapse §9 — with one
    device there is no *"the payer is not the beneficiary"* left to implement.
    The honest version of this idea is lever 2, which is already on the list.
  - **A data packet shared over iCloud instead of a database.** Closer than it
    sounds: the export (ARCHITECTURE §14) is already most of the packet, and the
    model was built to merge — appended not edited, one-way confirmation, merges
    that redirect, idempotent upserts keyed by client UUIDs. The genuine gain is
    custody rather than cryptography: Apple becomes the holder, and the breach
    and its notification duty stop being a schoolchild's. The costs are that
    `seq` is server-granted (§2.2) and would need replacing with per-device
    counters; that a shared file written from two phones produces conflicted
    copies, so it would have to be append-only per device; and that Advanced
    Data Protection — the part that would make it end-to-end — is off by default
    and no 80-year-old is going to switch it on. Kept as a v1.1 direction beside
    lever 3, not as a September plan.

- ~~**English as a language the app HEARS, not only one it reads.**~~ **Done
  30 Aug 2026**, the same day it was raised — the entry below is what it cost and
  is kept because the reasoning is what makes the numbers legible. Raised when the interface got English so that the app could be shown to
  people who do not read Finnish — the judges, and the video. That half is done
  and it is only the interface: the pipeline was not touched, and this is what
  touching it would cost.

  **The blocker is a number, not a prompt.** `MAX_WORDS_PER_SECOND = 4` in
  `backend/src/transcribe.ts` is the hallucination guard, and it is load-bearing:
  above it the transcript is thrown away and logged as fabricated. That is the
  right call — on poor audio a model does not fall silent, it pours out a wall of
  text nobody said, measured once at 135× reality, and an invented memory
  entering the archive under grandmother's name is the worst outcome this app
  has. But the ceiling is calibrated on Finnish, and its comment says so.

  Measured on this repository's own paired samples rather than argued, because
  the site carries the same story in both languages with both durations:

  | | words | seconds | words/second | share of the ceiling |
  |---|---|---|---|---|
  | Finnish (`sample-mokki-puhdas`) | 27 | 13.24 | 2.04 | 51 % |
  | English (`sample-cottage-en`) | 35 | 11.61 | 3.01 | 75 % |

  Same content, **30 % more words in English**, because Finnish is agglutinative
  — one long word carries what English needs three or four for. So English does
  not cross the line at these rates, and the first version of this note said it
  would, which was wrong. What it does is halve the headroom: the comment beside
  the constant says four is a ceiling *"nobody crosses by accident"*, and that
  is a Finnish sentence. A fast or excited English speaker crosses it, and what
  they get is their real telling discarded and a request to try again. Nothing
  looks broken. The memory simply never arrives.

  **The prompt is the second cost and a smaller one.** Of the six rules in
  `extract.ts`, one cannot be translated at all — names in base form, `"Ainon"`
  → `"Aino"`, describes a declension English does not have — three are rules
  that translate while their calibration does not (the filler words *niinku,
  tota, öö*; the common nouns *mummola, mökki, tori*; the decade idiom
  *50-luku*), and two are language-neutral. The examples are the part that was
  tuned; the structure is not what makes it work.

  **And the model choice does not transfer.** `asr-bench.mjs` measured Finnish
  word error rate and Finnish proper-noun recall, with a Finnish instruction.
  It is one model measured on one language.

  So this is a second pipeline — its own constant, its own prompt, its own bench
  run — and not a translation.

  **Built the same day**, at the author's decision and with model credit granted
  for it. What shipped: two system prompts in `extract.ts` and `transcribe.ts`
  written rather than translated, one description table so the schema shape
  cannot drift between them, `MAX_WORDS_PER_SECOND` as `{ fi: 4, en: 6 }` with
  the arithmetic beside it, and a `lang` field carried from the app, which
  sends its display language as its guess at who is speaking
  (`SpokenLanguage`, which says where the guess is wrong). Absent means
  Finnish, so a client built
  before this behaves exactly as it did. Verified against the real models: 22 of
  22 extraction cases, five English and seventeen Finnish, in one run — and the
  Finnish ones matter as much, because the schema was restructured under them.

  **The listening end was measured too**, the same evening. `asr-bench.mjs` now
  reads the language off the sample's file name and reports the two separately,
  because an average across both is a number about neither. English samples are
  generated by the same script with the same voice family, rate and degradation
  steps — `Grandma (English (UK))` beside `Grandma (Finnish (Finland))` — which
  is what makes the columns comparable rather than merely both synthetic.

  The numbers live in `backend/wrangler.jsonc` beside the setting they justify.
  The finding, and it is the one the entry above said could not be assumed:
  **the ranking is not the same in the two languages.** On English,
  `gemini-2.5-flash` leads on word error rate and `gemini-3.1-flash-lite` on
  proper nouns; the shipping model is second and third.

  It stays anyway, and the reason is not inertia. Both of those leaders blow up
  in the other language — 13 533 % and 4 011 % word error rate, which is the
  wall of invented text rule 4 exists against. Only `gemini-3.6-flash` is sane
  in both, and its gaps to the leaders are inside the noise of twelve samples.
  A model that hallucinates in one language will do it in the other on the day
  the audio is bad enough.

  **What is still NOT answered** is the same thing §8 says about Finnish: every
  sample in both columns is synthetic, and synthetic audio cannot tell you
  whether the concept survives a real elderly voice. Risk 2 is now unanswered in
  two languages rather than one. That is not worse than it was — it is the same
  gap, correctly sized.
