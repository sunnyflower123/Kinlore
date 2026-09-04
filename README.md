<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/lockup-dark.svg">
    <img src="docs/logo/lockup.svg" alt="Kinlore" width="340">
  </picture>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-Apache_2.0-blue.svg" alt="Apache 2.0 licence"></a>
</p>

A family's shared memory archive. An old person rambles; the AI turns it into
structure: memories attach to photos and people, the family tree grows out of
the stories, and open questions come back to be asked.

The problem being solved: grandparents *know*, but cannot explain in a
structured way. They do not fill in forms and they do not tag photos — they
talk. Existing album and genealogy apps demand structured input from the one
person who will never produce it, and so the knowledge disappears at the funeral.

The 80-year-old in that paragraph is not a persona. It is my own grandparent,
who tested it — which is why the rules further down read as constraints rather
than good intentions, and why the failure that matters here is not a crash but a
story nobody could get told.

Side project for the [RevenueCat Shipaton 2026](https://revenuecat-shipaton-2026.devpost.com/)
hackathon. Target category: **Next Gen Award** (student category).

## The one thing it does

> Grandmother presses a big button and rambles for 90 seconds about an old
> photo. The app returns: a structured memory attached to the photo, person
> cards for the relatives mentioned, year and place information — and three
> follow-up questions back.

<p align="center">
  <img src="docs/media/demo.gif" alt="The app launching, showing Järjestelen muistoa while it works, and arriving at a saved memory placed at Puumalassa in the 1950s with three proposed subjects waiting to be confirmed." width="320">
</p>

<p align="center"><sub>Simulator, stub pipeline — the waiting is real, the model call is canned.<br>Reproduce it with <code>-screen result</code> and <code>scripts/frames-to-gif.swift</code>.</sub></p>

```
audio → ASR (Finnish) → raw_transcript (kept verbatim)
                             ↓
                     LLM extraction (structured output)
                             ↓
     ┌───────────────────────┼───────────────────────┐
memory.body           mentioned subjects      follow-up questions
(cleaned text)        (confirmed = 0)         (prompt_question)
```

| <img src="docs/media/01-tell.png" alt="The Tell screen: a large red microphone button under the heading Kerro mitä muistat, with Paina ja ala puhua below it and a link offering to type instead."> | <img src="docs/media/02-result.png" alt="The result screen: Muisto tallennettu, the memory placed at Puumalassa 1950-luku, the spoken text kept as it was said, and three proposed subjects each with a cross and a tick."> |
|---|---|
| **Telling.** One button, and a way out of it for anyone who would rather type. | **What comes back.** The date is a decade because that is what was said, and no name enters the family tree before somebody confirms it. |

Everything else in the app exists to make that loop worth repeating. What is
built and what is not is inventoried, honestly, in
[`ARCHITECTURE.md` §1](docs/ARCHITECTURE.md#1-where-things-stand) — including a
warning about why that inventory has been wrong before.

### And then it asks

The follow-up questions are not a list to read. The app speaks one, listens for
the answer, organises what it heard, and asks the next — round after round,
without a tap. That matters because the person it is for should not have to
operate anything while she is remembering:

<p align="center">
  <img src="docs/media/demo-interview.gif" alt="The app organising a memory, then asking Kuka muu oli paikalla and listening with a live waveform, then organising again and asking Minä vuonna tämä suunnilleen oli — two full rounds with no tap in between." width="320">
</p>

<p align="center"><sub>Two rounds, hands-free. The 1:14 on the timer is real waiting, not a cut.<br>Reproduce it with <code>-screen interview</code>.</sub></p>

How the questions are chosen, and why they get more personal only as the
answers earn it, is the question ladder in
[`ARCHITECTURE.md` §12](docs/ARCHITECTURE.md#12-the-question-ladder).

## Six rules that do not bend

1. **The primary user is 80 years old.** Dynamic Type up to XXL, VoiceOver,
   large tap targets. If a new screen does not work at the largest text size, it
   is not done. Colours come from `Elder.swift`, never from `.secondary` or the
   system blue — every one of those measures below the contrast minimum, and
   contrast is the one rule eyes cannot check.
2. **Telling is never paywalled.** The paywall limits photos and AI minutes, not
   the act of writing or dictating a memory.
3. **The original audio and the raw transcript are always kept.** The speaker
   may no longer be around to ask. `memory.audio_r2_key` and
   `memory.raw_transcript` are not intermediate steps; they are the product.
4. **AI proposes, a human confirms.** A person or relationship inferred by the
   model is created with `confirmed = 0` and never appears in the family tree as
   fact. A wrong relationship is worse than a missing one.
5. **Uncertainty is stored, not rounded.** "Sometime in the fifties" goes into
   `date_start`/`date_end` with precision `decade`. No date is forced.
6. **No login screen.** Identity is a UUID in the Keychain; you join a family
   through an invite link.

## The core of the data model

A single `subject` table covers photos, people, places and events; a `memory`
attaches to any subject. That is why *"write a memory about this photo"* and
*"tell us what grandmother was like"* are the same screen and the same code
path, and why the family tree is just the edges between person subjects.
Schema: [`backend/schema.sql`](backend/schema.sql).

| <img src="docs/media/04-person.png" alt="A person card for Sanni: a large blue button reading Kerro tästä muisto, an empty Suku section offering to add a relative, one memory, and a button to ask the family."> | <img src="docs/media/05-family.png" alt="The family screen for the Virtaset family on the free tier: 7 of 10 minutes of telling used this month, 12 of 20 photos, and three members with the dates they joined."> |
|---|---|
| A person card is the same screen as a photo, because a person is the same row. The empty **Suku** section is the point: a gap is an invitation, not an error. | One archive, several members, one shared quota. The quota belongs to the family rather than to whoever paid for it — see **Who pays**. |

## How to check any of this yourself

Several parts of this app fail *silently* — they keep working, look right, and
are wrong. Each one has a check of its own rather than a promise:

```bash
./scripts/verify.sh
```

That runs everything below that costs nothing and says what it skipped and why.
What it deliberately leaves out is argued in its header: nothing that spends
model credit, because a script you run twenty times a day must not cost money.

CI runs that same script rather than a reimplementation of it, so the two cannot
drift apart — but on pull requests and on request, not on every push. The Swift
checks in it need macOS, a macOS minute is metered at ten while this repository
is private, and every push getting one is how you find out in four seconds that
the meter said no. Every push still gets the backend type check, on Linux.

| Claim | Command |
|---|---|
| Every screen works at XXL text, with VoiceOver, at sufficient contrast | `xcodebuild … test` — 103 UI tests, 46 of them an accessibility sweep at both text sizes |
| One purchase unlocks one family, and never a second | `node scripts/entitlement-binding-check.mjs` |
| The paid archive is offered on a rhythm, and never beside a name a human is being asked to confirm | `swiftc … scripts/upsell-rhythm-check.swift` |
| A place's coordinates follow its title through sync, and rubbish is refused | `node scripts/place-sync-check.mjs` |
| Extraction gets Finnish names, dates and relations out of a transcript | `node scripts/extract-tests.mjs` |
| The whole pipeline runs end to end | `scripts/smoke-pipeline.sh` |

The last three need a Worker running (`cd backend && npm run dev`); the first
three need only Xcode and node. The full commands, with the arguments this machine forces, are
in [`CLAUDE.md`](CLAUDE.md#commands).

## Measured, not claimed

**The ASR engine was chosen by measurement**, not from memory:
`scripts/asr-bench.mjs` over 3 Finnish texts × 4 degradation steps × 5 models.
The numbers sit in [`backend/wrangler.jsonc`](backend/wrangler.jsonc) beside the
setting they justify.

**Two of them are bad, and they are printed here on purpose.** The chosen model,
`gemini-3.6-flash`, scores 68 % on proper nouns against the bench's own tripwire
of 80 %, and a word error rate of 37.8 % against its own *"above 30 % is not
usable"* — on synthesised speech, which is kinder than a real 80-year-old voice.

The concept was not dropped anyway, and
[PLAN.md §8](docs/PLAN.md#risk-2-honestly) argues why in full: the original audio
is kept forever and is playable, the raw transcript is kept beside the cleaned
text, and names are checked by the teller in the seconds after telling — or
corrected from the person's card years later. *One proper noun in three being
wrong is the premise the name-correction step was written for, not a surprise.*

**Accessibility:** 0 failures across 17 audits, measured 15 Aug 2026 on a
private simulator. (On a simulator shared with another session the same commit
reports 15 failures that are not real — see `CLAUDE.md`.)

But the number is not the argument. This is one screen at the default text size
and at the largest one iOS offers, which is the size rule 1 is actually about:

| <img src="docs/media/02-result.png" alt="The result screen at the default text size: heading, placement, the spoken text, and three proposed subjects all visible at once."> | <img src="docs/media/06-result-xxxl.png" alt="The same result screen at the largest accessibility text size: the heading wraps to two lines, the text reflows, nothing is clipped or truncated, and the screen scrolls instead."> |
|---|---|
| Default | Accessibility XXXL |

Nothing is clipped and nothing is truncated — the screen gets longer instead.
That is rule 1 in one pair. It is also why the sweep opens each screen and audits
it at both sizes rather than trusting a screenshot at one: a screenshot shows the
top of a screen, and clipping happens further down.

## What I got wrong

This is the first project where I wrote my mistakes down instead of quietly
fixing them. Five that cost real time, kept here because a repo that lists only
what worked is not telling you how it was built:

**I wrote things down as done before they were.** Nearly every row of
`ARCHITECTURE.md` §1 was marked finished while it was not, and every one of them
*looked* finished: the transcription that waited for a text nothing was
bringing, the deletion the client never sent, the rate limit that existed only
in the document, the accessibility audit that measured the wrong screen and
passed. They were found by reading a promise and then checking the code meant to
keep it — never by using the app, which behaved perfectly in all four cases.
That is this project's failure mode, and it is why the checks in the table above
exist as scripts and not as intentions.

**I set a tripwire and then walked past it.** The plan called Finnish ASR risk
#1 and told me to settle it *before any app code*. I measured five engines
properly — and then never ran the actual go/no-go on real elderly speech, which
is the half that decides anything. What I do have says 68 % on proper nouns
against my own 80 % bar. The concept survives because of how the app is built,
not because the number is good; the argument is in
[PLAN.md §8](docs/PLAN.md#risk-2-honestly) and it is the part I would most like
a judge to read.

**I corrected a fact in the wrong direction, confidently.** `CLAUDE.md` used to
state which Xcode was installed here. It was wrong, I "fixed" it — backwards —
and wrote the new wrong version with more certainty than the old one. Following
it fails as *"Invalid runtime"*, which reads like a broken Xcode and is not one.
The file now says: measure before editing this line, and paste the output rather
than a remembered number.

**I carried five candidate names for a year without checking any of them.** Two
were already taken outright, by apps doing this same thing. Checking costs one
HTTP request. Worse, the check I eventually wrote has two blind spots that both
bit me: reserved-but-unshipped names are invisible, and the API only sees the
App Store — *Saga* looked free while Saga plc sells insurance and cruises to 2.7
million over-50s in the UK, which is the same demographic as this app.

**I chased a red test run for an evening.** Fifteen accessibility failures,
contrast and clipping, on a screen that passes on its own. Another session was
using the same simulator. Measured afterwards: 15 failures shared, 0 of 17
private, same commit, minutes apart. The tests were not lying about the screen;
they were lying about which process they had hold of.

## Who pays

**The payer is not the beneficiary.** Grandmother does not buy a subscription —
the grandchild does, and the whole family channel opens for every member.
RevenueCat grants the entitlement to the buyer; the backend maps it to a
channel-level right (`family.entitlement`). For an audience whose ability to pay
sits in a different person than the one producing the value, that is the only
model that works. Details: [`ARCHITECTURE.md` §6](docs/ARCHITECTURE.md#6-money).

Purchases run on the **RevenueCat Test Store** — there is no App Store release,
by decision ([PLAN.md §2](docs/PLAN.md)).

## The cloud question, unanswered in public

Who hands a dead parent's voice to somebody's server? What is true today, rather
than what is comfortable: the words of every memory are D1 columns, and the
audio leaves the phone even with R2 disabled, because transcription happens in
the Worker. A local-only mode already exists in the code (`Session.mode`), but
onboarding does not yet offer it, and the only place the user is told the audio
travels is the microphone prompt — which comes *after* the archive is created.

So the barrier is the order, not the architecture. The three levers, priced, are
the last item in [PLAN.md §10](docs/PLAN.md). End-to-end encryption is the only
real answer and is incompatible with server-side transcription; it is named as a
v1.1 direction rather than quietly omitted.

What the repo does guarantee: `OPENROUTER_API_KEY` exists only as a Worker
secret, `provider: { data_collection: "deny" }` is unconditional and never a
per-call flag, and the cause of an error never reaches the client — upstream
bodies can echo back the memory that was just told, so they go to
`console.error` and the app gets `{ error: "upstream_failed" }`.

## Layout

| Directory | Contents |
|-----------|----------|
| `ios/` | SwiftUI app. The project is generated from `project.yml` with XcodeGen. |
| `backend/` | Cloudflare Worker + D1 (metadata) + R2 (photos and audio). |
| `scripts/` | The checks in the table above, plus `asr-bench.mjs` and the logo tooling. |
| `docs/` | `PLAN.md` (scope, schedule, risks), `ARCHITECTURE.md`, `SETUP.md`, `logo/`. |
| `.claude/` | The [guideline file](.claude/skills/karpathy-guidelines/SKILL.md) Claude Code works under here — vendored, MIT, [why](CLAUDE.md#the-assistants-rules--checked-in-not-personal-setup). |

## Setting it up

**Prerequisites:** Xcode 26.6 (iOS 26.5 simulator SDK), XcodeGen
(`brew install xcodegen`), Node 20+. **Nothing from Apple beyond Xcode** — no
paid developer account, no certificates, no Sign in with Apple. What else is not
needed, and why, is in [`SETUP.md`](docs/SETUP.md#what-is-not-needed).

### 1. The app on its own — no keys, no backend, about two minutes

```bash
git clone https://github.com/sunnyflower123/Kinlore.git
cd Kinlore/ios && xcodegen generate && open Kinlore.xcodeproj
```

Press Run. **The app is fully usable on stubs**: record or type a memory, watch
it come back structured, browse the people it proposed, open the paywall. That
is deliberate rather than a demo mode — development must not stop when the
Worker is broken or there is no network — and it means anyone can try this
without an account of any kind.

Run `xcodegen generate` again after changing `project.yml` **and after adding or
removing a source file** — XcodeGen globs the sources, so a new `.swift` file is
invisible to `xcodebuild` until it runs.

### 2. The backend, locally

```bash
cd backend && npm install
printf 'OPENROUTER_API_KEY=sk-or-...\n' > .dev.vars
npm run db:local   # FIRST TIME ONLY — this creates the tables, it does not migrate them
npm run dev
```

`.dev.vars` is gitignored — **check anyway before your first push**, because the
repo is public. One key covers both halves of the pipeline: OpenRouter has no
separate transcriptions endpoint, so audio travels as an `input_audio` part of a
chat completion. That key lives only in the Worker, never in the app; unpacking
an IPA is trivial and a leaked key is a real bill.

```bash
curl -s http://localhost:8787/health
```

`{"ok":true,"hasKey":true}` means the key is in place. If `hasKey` is `false`,
extraction answers `502 upstream_failed` and the cause goes to the Worker's log
only — upstream bodies can echo back the memory that was just told.

### 3. Point the app at it

In Xcode: Product → Scheme → Edit Scheme → Run → Arguments.

| Argument | Effect |
|---|---|
| `-api http://localhost:8787` | Real transcription and extraction instead of stubs |
| `-rcKey <RevenueCat Test Store key>` | Purchases. Without it the app works normally, minus the paywall |

Both are optional, and there are about twenty more. The debug ones exist because
some states cannot be reached by hand at all — a refused microphone, a family
with no server behind it, an extraction that fails while transcription succeeds.
They are what the UI tests and the demo video are filmed with, and they are
listed in [`SETUP.md`](docs/SETUP.md#launch-arguments).

### 4. Your own Cloudflare resources — only for the cloud half

```bash
cd backend && npx wrangler login
npx wrangler d1 create memorize && npx wrangler r2 bucket create memorize-media
```

Put the returned `database_id` in [`backend/wrangler.jsonc`](backend/wrangler.jsonc),
push the schema to the remote database with `npm run db:remote`, then add the
three secrets ([what each is for](docs/SETUP.md#backend--as-worker-secrets)):

```bash
npx wrangler secret put OPENROUTER_API_KEY   # and RC_SECRET_KEY, RC_WEBHOOK_SECRET
```

The Cloudflare resources keep the old project name `memorize` on purpose: an R2
bucket cannot be renamed, only recreated empty, and rule 3 lives in that bucket.

Two months of development cost under €20 in total — the estimate, item by item,
is at the end of [`SETUP.md`](docs/SETUP.md#cost-estimate-during-development).

## Building and testing from the command line

This needs two things the machine forces. `DEVELOPER_DIR`
is mandatory because `xcode-select` points at CommandLineTools and changing it
would need `sudo`. And the simulator has to be given **by UDID**: four devices
here are called *iPhone 17 Pro*, so a `name=` destination fails as *"Unable to
find a device matching the provided destination specifier"*, which reads like a
missing simulator and is not one.

```bash
SIM=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available | grep -m1 'iPhone 17 Pro (' | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator -destination "id=$SIM" build
```

The UI tests need a simulator of their **own** — they install, launch and
terminate one bundle id, and two runs on one device kill each other's process
and report accessibility failures that are not real. Create one, then pass its
id as `$KINLORE_TEST_SIM`:

```bash
xcrun simctl create kinlore-tests com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

## Two languages, on purpose

The repo is written in **English**: docs, comments, identifiers, commit
messages. The app's user interface is **written in Finnish**, because the person
it exists for is a Finnish 80-year-old — and it **speaks English by default**,
because the app has to be shown to people who do not read Finnish. A Finnish
phone still gets Finnish. The Finnish source strings are the lookup keys, so
writing a new one still means writing Finnish; `scripts/localisation-check.mjs`
fails if it has no English.

The pipeline follows **who is speaking**, not who is reading the screen: there
are two system prompts and two hallucination ceilings, and the app says which
applies. The English prompt is not the Finnish one translated — its first rule
teaches a model about case endings that English does not have. The test
transcripts stay Finnish because they are the input under test. The boundary and
its exceptions are spelled out in [CLAUDE.md](CLAUDE.md).

## Licence

[Apache 2.0](LICENSE).
