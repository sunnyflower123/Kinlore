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
| **A** | 31 Jul – 3 Aug | **Kill the risks.** ASR test on real elderly speech. Swot check. RevenueCat account + Test Store. GitHub public + licence. | holiday |
| **B** | 4–10 Aug | **Backbone + magic moment.** Photo picking, memories, dictation → transcription → extraction → follow-up questions. The last week of the holiday goes to the hardest part. | holiday, full |
| — | **~11 Aug** | **School starts** | |
| **C** | 11–31 Aug | Person cards + relationships. Confirmation UI for proposals was dropped in favour of the guessing round, which was then cut itself — see §4.1. | evenings |
| **D** | 1–14 Sep | RevenueCat Test Store + paywall. Craft: animations, waveform, empty states, accessibility. | evenings |
| **E** | 15–24 Sep | Testing with a real grandparent — **installed from Xcode on a visit**, see below. Fixes. **Repo in English.** | evenings |
| **F** | 25–28 Sep | **Demo video** and Devpost submission. | weekend |

If phase B succeeds, the rest is downhill. If it does not, everything else is
pointless — which is why it sits in the holiday and not alongside school.

### Phase E does not go through TestFlight

This row said "TestFlight" and contradicted the first paragraph of CLAUDE.md,
which drops App Store Connect for want of time. **TestFlight *is* App Store
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
and on the paid account the build keeps working for about a year rather than the
seven days a free account allows.

What it costs instead, so that it is not a surprise on the day: her phone has to
be paired to this Mac once, over a cable, and **Developer Mode has to be turned
on in her Settings** — which takes her passcode and a restart of her phone. That
is done with her, once, before anything is installed.

The fallback, if a visit turns out to be impossible, is TestFlight with her as an
external tester and a day or two of review built into the schedule. It is written
down here so that the choice is made now rather than on 15 September.

## 4. The magic moment — the one thing

> Grandmother presses a big button and rambles for 90 seconds about an old
> photo. The app returns: a structured memory attached to the photo, person
> cards for the relatives mentioned, year and place information — and three
> follow-up questions back.

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
why it worked is kept in [`ARCHITECTURE.md` §13](ARCHITECTURE.md#13-the-guessing-round-built-then-cut);
this section records the hole it leaves, because the hole is not where it looks.

It was built to answer a real problem: everything in §4 is a **writing** loop,
and nothing gave the family a reason to open a memory that was already written.
That problem is still there. Cutting the round does not solve it; it postpones
it, and a family archive dies unread more often than unrecorded.

**And it took the confirmation mechanism with it.** §4.1 used to say the round
*was* the confirmation UI and a better one — a card with the name already on it
gets tapped "yes" without being read, a blind guess cannot be. That argument was
right, and it was the reason the standalone "confirm this proposal" screen was
never built. So confirmation is now the orange proposal row and nothing else,
which is the weaker instrument the old section rejected. Rule 4 in CLAUDE.md
says so plainly rather than inheriting the old sentence.

Why it went anyway: §5 fixed the order in advance so nobody has to choose while
exhausted, and levers 2 and 3 of §10 are two additions that owed a removal. This
is that removal.

## 5. Cut order for when time runs out

It will. This is decided in advance so that nobody has to choose while exhausted.

**Never cut:**
1. The magic moment (dictation → extraction → follow-up questions)
2. RevenueCat Test Store + paywall — a rule requirement, but small work
3. The demo video
4. Repo in English + OSS licence visible in GitHub's About section

**Cut in this order, from the bottom up:**

| # | Target | How |
|---|--------|-----|
| 8 | ~~**Guessing round**~~ | **Cut 16 Aug 2026.** The isolation claim was half true: the two call sites really were one line each, but the round also owned two files, a model, a table, sync rows in both directions, a check script, a test file and 165 lines of §13 — about 1 100 lines in all. Budget a session, not a line |
| 7 | Family tree / relationships | Person cards without edges |
| 6 | Reporting and blocking | No longer mandatory without App Review |
| 5 | **Real invite link and join flow** | **First thing to simplify.** Deep links and join screens are an expensive part. The data model already supports multiple members (`memory.author_id`), so **a demo family can be seeded** — the video shows several relatives' memories on the same photo without the join flow being built |
| 4 | Person cards | Memories only on photos |
| 3 | Uploading photos to the cloud | Local photo picking is enough for the video |

Note the difference: **the concept is not cut, the implementation is.** Shared
family memory shows on the video even if the join flow is seeded — but if the
magic moment is missing, there is nothing to show.

## 6. Design principles

1. **The primary user is 80 years old.** Dynamic Type up to XXL, VoiceOver,
   large tap targets. Accessibility *is* this app's design.
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
| 3 | **The student email only arrives when school starts** | The domain can be checked already: `./scripts/check-swot.sh <domain>`. Upper secondary school domains are on the list under municipality directories. |
| 4 | **School takes more time than expected** | The cut order in §5 is decided in advance. The heaviest work is in the holiday. |
| 5 | **The demo video is left to the last evening** | It has its own phase (F). The video is a deliverable, not an afterthought. |
| 6 | ~~**The repo stays in Finnish**~~ | **Done.** Translated, and the boundary is written down in CLAUDE.md so it stays. |

### Risk 2, honestly

This is the one the plan called risk #1 and told itself to close *before any
other code*. What actually happened is worth writing down, because the two
halves are easy to mistake for each other.

**What was measured.** `scripts/asr-bench.mjs` was run over
`scripts/make-synthetic-samples.py` output: three Finnish texts at four
degradation steps, five engines. That chose `gemini-3.6-flash`, and the numbers
are in `backend/wrangler.jsonc` beside the setting they justify. As an engine
comparison this is sound — relative ranking is exactly what the generator says
it is good for.

**What was not.** The samples are text-to-speech. The generator says so in its
own header: *"TTS does not produce dialect, stammering, self-correction,
overlapping speech, or a sentence trailing off. A real elderly speaker does all
of that. These figures are therefore optimistic."* The tripwire — *below ~80 %
on proper nouns, rethink the concept* — is about absolute quality on real
speech, and no real speech has been through it. `samples/LUEMINUT.txt` has said
what is needed from the beginning: three recordings of an actual elderly voice.

**And the optimistic number already missed both bars.** 68 % on proper nouns
against a tripwire of 80 %, and a word error rate of 37.8 % against the bench's
own *"above 30 % is not usable"*. On audio that is kinder than the real thing.

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

### The visit that takes the measurement

Written before the day rather than on it, because half of what follows cannot be
done afterwards at all.

**Before the door.** The build is on her phone already (§3), Developer Mode is
done, and there is something to write on. `scripts/asr-bench.mjs` says what it
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

## 9. The core of monetisation

**The payer is not the beneficiary.** Grandmother does not buy a subscription —
the grandchild does, and the whole family channel opens for every member.
RevenueCat grants the entitlement to the buyer; the backend maps it to a
channel-level right (`family.entitlement`).

Explain this in the Devpost description: the criterion says "thoughtful
RevenueCat implementation", not "a paywall exists". Ability to pay sits in a
different person than the one producing the value — for this audience that is
the only model that works, not a contest trick.

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
- **Prices.** Free: 1 family / ~20 photos / ~10 AI minutes per month. Paid:
  ~€9.99/month or €59.99/year. Nominal on the Test Store, but considered.

  **Two products, and a third was removed on 16 Aug 2026.** The Test Store had
  `monthly`, `yearly` *and* `lifetime` in its `default` offering — the trio
  RevenueCat proposes when a project is created, so `lifetime` arrived as a
  default rather than as a decision. Nothing was broken by it: `entitlement.ts`
  already reads a null `expires_at` as perpetual, deliberately. It was removed
  because an undecided price is worse than a decided one, and because in *this*
  product a single payment would open the archive for a whole family forever,
  which is a promise that deserves an argument rather than a template.

  The paywall is in the demo video. Three options, one of them unplanned, reads
  as pricing left at its defaults — on a submission judged partly on *"technical
  care in presentation"*.

  The case for bringing it back is real and is emotional rather than commercial:
  *"this is forever"* suits an archive better than a monthly bill does. If that
  wins later, **price it here first.** Do not let it return as a default a second
  time.
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

     **Two things it does not do**, both deliberate and both worth knowing
     before this is called finished:

     - **It is not reversible from inside the app.** Nothing turns a
       single-phone archive into a family one; the only way back is *"Tyhjennä
       tämä laite"*, which clears the answer along with everything else and
       offers the export first. That is defensible for v1 and it is not
       obviously right — a Settings row that hands the archive to a new family
       is the honest version, and it is not built.
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
     read it.** Three things stay outside it, each for a named reason:

     - **Transcription still sends the recording in clear.** Rule 7 puts the
       model key in the Worker and a model cannot write down speech it cannot
       hear. What lever 3 changes is what is *left behind* — the rows and the
       objects, which is what a dump contains.
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

- **English as a language the app HEARS, not only one it reads.** Raised
  30 Aug 2026, when the interface got English so that the app could be shown to
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
  run — and not a translation. It needs model credit and a removal under §5, and
  it is **not needed for what English was added for**. Not a v1 decision; parked
  here so that whoever opens it starts at the constant rather than at the prompt.
