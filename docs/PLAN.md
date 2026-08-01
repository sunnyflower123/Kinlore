# Plan — Shipaton 2026 / Next Gen

Working title: **Memorize**
Contest: RevenueCat Shipaton 2026, 1 Aug – 30 Sep 2026
**Target category: Next Gen Award** (student category, $15,000). No others.

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
| 2 | **Finnish ASR on elderly speech.** The whole app rests on this. | `node scripts/asr-bench.mjs samples/` before any other code. Below ~80 % on proper nouns → rethink the concept. |
| 3 | **The student email only arrives when school starts** | The domain can be checked already: `./scripts/check-swot.sh <domain>`. Upper secondary school domains are on the list under municipality directories. |
| 4 | **School takes more time than expected** | The cut order in §5 is decided in advance. The heaviest work is in the holiday. |
| 5 | **The demo video is left to the last evening** | It has its own phase (F). The video is a deliverable, not an afterthought. |
| 6 | **The repo stays in Finnish** | Phase E. Directly scored, and an easy thing to skimp on. |

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
- **Name.** No longer urgent without App Store Connect. `Memorize` is full of
  flashcard apps in App Store search; candidates: *Heirloom*, *Kinfolk*,
  *Storykeeper*, *Rootline*, *Perennial*.
- **ASR implementation.** Resolved by the phase A test.
- **Prices.** Free: 1 family / ~20 photos / ~10 AI minutes per month. Paid:
  ~€9.99/month or €59.99/year. Nominal on the Test Store, but considered.
