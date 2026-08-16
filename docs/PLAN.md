# Plan — Shipaton 2026 / Next Gen

Name: **Kinlore** (decided 15 Aug 2026, §10)
Contest: RevenueCat Shipaton 2026, 1 Aug – 30 Sep 2026
**Target category: Next Gen Award** (student category, $15,000). The store route
is a conditional option decided on 10 Sep, not a second target — see §2.1.

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

## 2.1 The store route, reopened as an option — 15 Aug 2026

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
| **C** | 11–31 Aug | Person cards + relationships. ~~Confirmation UI for proposals~~ — replaced by the guessing round, see §4.1. | evenings |
| **D** | 1–14 Sep | RevenueCat Test Store + paywall. Craft: animations, waveform, empty states, accessibility. | evenings |
| **E** | 15–24 Sep | Testing with a real grandparent (TestFlight). Fixes. **Repo in English.** | evenings |
| **F** | 25–28 Sep | **Demo video** and Devpost submission. | weekend |

If phase B succeeds, the rest is downhill. If it does not, everything else is
pointless — which is why it sits in the holiday and not alongside school.

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

## 4.1 The guessing round — and what it cost

*One person tells a story, the others guess who it was about.* A memory that
names exactly one person is shown to the rest of the family with the name taken
out, and four person cards to choose from. Details in
[`ARCHITECTURE.md` §13](ARCHITECTURE.md#13-the-guessing-round).

Everything in §4 is a **writing** loop, and it has a hole: nothing gives the
family a reason to open a memory that is already written. That is how family
archives actually die — not unrecorded, unread. Guessing costs one tap, and it
is the only part of this app that asks nothing of the 80-year-old: the round is
derived from an ordinary memory, so she tells the story the way she always does.

**What it removes, because every addition removes something:** the standalone
*"confirm this proposal"* screen that phase C was going to grow. It is not
needed, and it was never going to work — a card with the answer already written
on it gets tapped "Yes" without being read. A blind guess cannot be. The
guessing round *is* the confirmation UI, and it is a better one; what stays of
the old plan is the orange proposal row that already exists on the person list
and in the Tell result.

Net effect on the schedule: roughly even. Net effect on rule 4 of §6: better.

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
| 8 | **Guessing round** | **First out.** It is the reading loop, not the magic moment, and it is one section on one screen plus one table — delete `GuessSection()` from the gallery and it is gone without touching anything else. That isolation is the reason it was built the way it was |
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

- ~~**Licence.**~~ **Decided: MIT**, canonical text in `LICENSE`. AGPL-3.0 was
  the alternative and would have made commercial copying unattractive, but it is
  effectively incompatible with App Store distribution — and this plan
  deliberately leaves a store release open for v1.1 (see `SETUP.md`). The
  protection AGPL buys matters for server software; here the moat is in the
  product decisions, not the code.
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
  RevenueCat field only when an **App Store** app config is added, which happens
  only if the store route opens (§2.1), and by then the new id is the one that
  gets typed in. So the rename cost nothing here at all.

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
  why all three names travel to that moment (§2.1, 10 Sep) rather than one.

  And the name does not have to explain the product. The App Store subtitle and
  the Devpost tagline do that, and the demo video explains more in ten seconds
  than any name can.
- **ASR implementation.** Resolved by the phase A test.
- **A map of the places.** The data half exists: `subject` carries `lat`, `lon`
  and `geo_precision`, and place names are looked up on the device as they are
  told, so the archive accumulates coordinates from now on. The screen is *not*
  decided — it is not in any phase, and if it is built it takes the place of the
  family tree's edges (§5, row 7). Read `ARCHITECTURE.md` §18 first: the lookup
  always answers, and a map that draws every answer as a pin publishes guesses as
  fact.
- **Prices.** Free: 1 family / ~20 photos / ~10 AI minutes per month. Paid:
  ~€9.99/month or €59.99/year. Nominal on the Test Store, but considered.
- **The cloud as an adoption barrier.** Raised 15 Aug 2026, undecided. Who hands
  a dead parent's voice to somebody's server? For this product that is not a
  passing worry — it is the trust question, and the answer is currently *"we
  never say"*.

  What is actually true today, measured rather than assumed:

  - `memory.body` and `memory.raw_transcript` are D1 columns, so the words of
    every memory are on a server the moment sync runs. R2 holds only the files.
  - The audio leaves the device even with R2 off, because transcription happens
    in the Worker. Rule 7 puts the model key there and nowhere else.
  - **A local mode already exists.** `Session.mode` has `.local`, and sync is
    gated on `.inFamily` (`Session.swift`). The machinery for "nothing leaves"
    is built.
  - But onboarding offers **two** choices, *Aloita perheen arkisto* and *Liity
    kutsulinkillä*, and nothing else. The only place the user is ever told the
    audio leaves the phone is the microphone permission prompt — which comes
    *after* the archive has been created.

  So the barrier is the order, not the architecture: the choice is asked before
  the consequence is explained.

  Three levers, in rising cost:

  1. **Say it in onboarding**, where the archive is created. One evening. For an
     80-year-old this is a dignity question as much as a privacy one — informed
     consent rather than a fact discovered later.
  2. **A third option: "Vain minulle, tälle puhelimelle."** Sets `mode = .local`
     and sync never runs. One to two evenings, since the machinery exists. It
     must say plainly that audio *still* travels for transcription — fixing the
     barrier with a promise that is not kept would be worse than the barrier.
  3. **End-to-end encryption.** The only real answer to "everything is in the
     cloud", and **incompatible with server-side transcription**: the model
     cannot write down speech it cannot hear. Not September, not close. Worth
     naming as a v1.1 direction, because a judge or a user will ask.

  Decide with the rest on 10 Sep. Lever 1 is cheap enough to be worth doing
  regardless; 2 competes for September evenings and §5 says every addition takes
  a removal.
