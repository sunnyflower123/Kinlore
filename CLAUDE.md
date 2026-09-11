# Kinlore

A family's shared memory archive. An old person rambles; the AI gives it
structure. Side project for RevenueCat Shipaton 2026.

**Target category: Next Gen** (student category). **No App Store release** — it
was dropped because upper secondary school starts around 11 Aug and there is no
time for App Store Connect. Purchases run on the RevenueCat Test Store.

The official Devpost deadline is **30 Sep 2026, 23:45 PDT** (= 1 Oct, 09:45
Finnish time); **28 Sep is an internal buffer**, not the real limit. One
eligibility question is settled, confirmed by RevenueCat staff in Aug 2026 —
do not re-research it:

- **A non-qualifying school email domain is not a bar.** Student status is
  verified at submission; a student ID or letter of enrolment is accepted when
  the domain is not on the JetBrains/swot list.

**The repository is private, and stays private until submission. That is a
decision, not a task left undone** — decided 9 Sep 2026, and this paragraph
exists because the file used to read as an overdue chore and every session
dutifully raised it again. Do not raise it again.

Next Gen's rule, quoted from the rules page rather than paraphrased: *"The
repository must be public and open source by including an open source license
file. This license should be detectable and visible at the top of the repository
page."* It applies to Next Gen alone; no other category asks for a repository.

The dates that set the window, read from the same page on 9 Sep 2026:
submission closes **30 Sep 23:45 PDT**, judging runs **1–13 Oct**, and winners
are announced **21 Oct**. So the obligatory exposure is the fourteen days from
submission to the end of judging — which is what made the timing a free choice
rather than a risk to sit on.

**Flip it on 28 Sep, the internal buffer, not on the 30th.** Two things can only
be seen once the repo is public and neither should be met for the first time on
a deadline evening: whether GitHub actually *detects* the licence and shows it
at the top of the page, and whether Pages serves `docs/index.html` — whose four
links into the repository answer 404 until the moment it flips. A minute-long
dry run, public and straight back to private, settles both at no cost.

Nothing about safety is holding it: `.dev.vars` is in `.gitignore`, has never
been committed, and no key-shaped string appears anywhere in history. It is one
setting, not a cleanup. What it costs to wait is that GitHub Actions stays paid
until then — which is why `ci.yml` runs its expensive half only on pull requests
— and that Pages is off, so the page nobody can reach yet is also the DSA
contact surface. Both are priced and accepted.

Two consequences for anything written here in the meantime. Everything in this
file about the repo being a shop window is about the day it opens, not today.
And a public repository publishes its **history**, not merely its head — so what
goes into a commit now is as permanent as what goes into `main`, and unbuilt
plans belong outside the repository entirely.

**The schedule is built around school:** the heaviest work (backbone + magic
moment) happens 4–10 Aug during the holiday, not alongside school. When time
runs out, cut in the order given in PLAN.md §5 — it was decided in advance so
that nobody has to choose while exhausted.

Plan and scope: [docs/PLAN.md](docs/PLAN.md). **Read it before adding features** —
the scope is deliberately cut, and every addition requires a removal.

## Language — this repo is written in English

The category judges the **public source code**, so the repo is a shop window and
not just a tool. Two languages coexist here on purpose, and the boundary is not
negotiable:

| Audience | Language | Covers |
|----------|----------|--------|
| Whoever reads the repo | **English** | Docs, code comments, commit messages, identifiers, developer-facing log output, test names, debug launch arguments, config comments |
| Whoever uses the app | **Finnish, written; English, default** | Every string the user sees or hears — see the mechanism below |

**The app speaks both, and the mechanism is the part to understand before
touching anything.** Since 30 Aug 2026:

- **The Finnish strings in the Swift source are the KEYS.** SwiftUI reads a
  string literal in `Text`, `Button`, `Label`, `navigationTitle` and
  `accessibilityLabel` as a `LocalizedStringKey`, and the export uses
  `String(localized:)`. So writing a new user-facing string still means writing
  it in Finnish, in the source, exactly as before.
- **Both tables translate away from those keys.** `en.lproj` carries the
  English; `fi.lproj` maps every key to itself. The Finnish table is not
  redundant — English is the development language, the fallback for a missing
  key is the development language rather than the key, and an empty `fi.lproj`
  hands a Finnish phone English. That happened, and only a screenshot showed it.
- **`scripts/localisation-check.mjs` fails if either table is short.** Nothing
  else reports a missing translation: the Finnish build stays perfect, the
  build succeeds, and the English one shows one Finnish word in the middle of a
  screen nobody runs except on filming night.
- **English is the default because the app is presented, judged and filmed in
  it.** A Finnish phone still gets Finnish. Nothing in the app switches
  language; it follows the device.
- **A runtime `String` is looked up only if you look it up.** `Text`,
  `navigationTitle` and `accessibilityLabel` localise a *literal*; handed a
  `String` variable they show it verbatim. So a fallback name that lives in a
  computed property — `Subject.displayTitle`'s *"Valokuva"*, `SubjectKind.label`
  — must be built with `String(localized:)`. Both keys sat in both tables from
  30 Aug 2026 and an English phone still read "Valokuva" on every untitled
  photograph until 6 Sep, and the check above could not see it: it counts keys,
  not lookups.

Two things stay Finnish even though no user reads them, and each has a reason:

1. **Test transcripts and TTS sample texts** (`scripts/`). That is the input
   under test. Translating it would test a different thing.
2. **The Finnish half of the LLM prompts** (`backend/src/extract.ts`,
   `backend/src/transcribe.ts`). There are now two of each, and the English one
   is not a translation: rule 1 teaches a model about Finnish case endings and
   has no English counterpart, and the filler words and common nouns in rules 2,
   3 and 5 are the part that was tuned. **Which prompt runs follows who is
   SPEAKING**, not who is reading the screen — the app sends `lang`, absent
   means Finnish. The Finnish was tuned by measurement; do not edit it on the
   way past. `MAX_WORDS_PER_SECOND` is two numbers for the same reason.

Everything new follows this rule from the start. Do not write a Finnish comment
now and translate it later — the translation pass has already happened once.

## Layout

```
ios/       SwiftUI app, XcodeGen (project.yml → .xcodeproj)
backend/   Cloudflare Worker + D1 (metadata) + R2 (photos and audio)
scripts/   asr-bench.mjs — Finnish speech recognition comparison
docs/      PLAN.md, ARCHITECTURE.md, UX.md, SETUP.md, VIDEO.md, RECOVERY.md
```

## Data model

A single `subject` table covers photos, people, places and events. A `memory`
attaches to any subject. That is why "write a memory about this photo" and "tell
us what grandmother was like" are the same screen and the same code path — do
not split these into separate implementations, it is the core of the whole
architecture. Schema: [backend/schema.sql](backend/schema.sql).

## Rules that do not bend

1. **The primary user is 80 years old.** Dynamic Type up to XXL, VoiceOver,
   large tap targets. If a new screen does not work at the largest text size, it
   is not done. This is not a compliance checklist; it is the product.
   **Colours come from `Elder.swift` and the accent colour asset, never from
   `.secondary`, `.tertiary`, `.orange`, `.red` or the system blue** — every one
   of them measures below the contrast minimum, and contrast is the one rule
   eyes cannot check. Run the accessibility tests after touching any screen; see
   [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §15.
2. **Telling is never paywalled.** The paywall limits photos and AI minutes, not
   the act of writing or dictating a memory.
3. **The original audio and the raw transcript are always kept.** The speaker
   may no longer be around to ask. `memory.audio_r2_key` and
   `memory.raw_transcript` are not intermediate steps; they are the product.
4. **AI proposes, a human confirms.** A person or relationship inferred by the
   AI is created with `confirmed = 0`. Unconfirmed never appears in the family
   tree as fact. A wrong relationship is worse than a missing one.

   **The strongest kind is blind**: somebody who was never shown the name and
   arrived at it anyway has genuinely recognised the person. A card with the
   name already on it gets tapped "yes" without being read.

   That instrument was lost when the guessing round was cut on 16 Aug 2026
   (PLAN.md §5, row 8) and **came back on 30 Aug 2026 in a cheaper shape**: the
   Kerro tab's card shows the photograph the name was heard in and asks *"kuka
   tässä on?"* over four names with the proposal unmarked among them
   (`BlindConfirmation`, ARCHITECTURE §23). The join it needed —
   `memories(mentioning:)` — was already in the model, and a photograph has no
   name in it to leak, which is the whole cost the round's mask used to carry.

   Since 5 Sep 2026 the card follows whose phone it is: on a reader's phone it
   stays on the Kerro tab; on a grandparent's (the text-floor signal) it sits
   on Muistot in the reading loop, and her Kerro tab is the button and nothing
   else (`BlindCardView`, one view in both places).

   The orange proposal row on the person list and in the Tell result is still
   there and is still the weaker instrument. It is what answers a proposal the
   blind card cannot reach: a name heard while talking about a person rather
   than a picture has no face to put in front of anybody.

   Two things the blind card must keep. **A wrong answer is never called
   wrong** — the app does not know who is in the photograph either, and saying
   otherwise is the guess asserted as fact. And **nothing on that screen may
   name the proposal**, including the photograph's accessibility label; that
   failure is silent, because a card that leaks its answer still looks exactly
   like a card that works. `BlindConfirmationTests` asserts it by walking every
   element on screen.
5. **Uncertainty is stored, not rounded.** "Sometime in the fifties" goes into
   `date_start`/`date_end` with precision `decade`. Do not force a date.
6. **No login screen.** Identity is a UUID in the Keychain
   (`kSecAttrSynchronizable`); you join a family through an invite link. Sign in
   with Apple *would* be possible and is still not used as a gate, at most as an
   optional account recovery for a paying member in v1.1.
   See [docs/SETUP.md](docs/SETUP.md).
7. **`OPENROUTER_API_KEY` lives only as a Worker secret.** The app uploads audio
   and text to the Worker; the Worker calls OpenRouter.

   This rule used to end "the repo is public — check `.dev.vars` before every
   push", which is a reminder and not a check, and it was the only one of these
   ten rules with nothing enforcing it. **`scripts/secret-check.mjs` enforces it
   now**, first in `verify.sh` and in about a third of a second: the tree, every
   blob that has ever existed, `.dev.vars` being both ignored and untracked, and
   its own matcher against a specimen of each key shape so it cannot go quietly
   green.

   It is first in that file because it is the only failure here that the next
   commit cannot undo. **A public repository publishes its history, not its
   head** — so a key committed today and deleted tomorrow is published on 28 Sep
   regardless, and the only remedy left is rotating the key and rewriting every
   commit after it. Measured 10 Sep 2026: 1370 blobs across 269 commits, clean.
8. **`provider: { data_collection: "deny" }` is unconditional**, never a
   per-call flag. The content is a family's memories of dead relatives. As a
   flag it would be forgotten on some call.
9. **The cause of an error never leaks to the client — and the log is not
   somewhere to leak it instead.** The app gets `{ error: "upstream_failed" }`.
   Upstream bodies and model output stay out of `console.error` as well:
   `observability` is on in `wrangler.jsonc`, so Workers Logs is a store beside
   D1 and R2 — and it is the one store a family cannot export, cannot clear with
   *"Tyhjennä tämä laite"*, and never agreed to. This rule used to send them
   there on purpose, and it cost 300 characters of the just-told memory on every
   extraction failure until 16 Aug 2026 (PLAN.md §10). Log shape, length,
   counts, status and the provider's own error codes. **An error message must
   not interpolate content** — not a title, not a transcript, not a name —
   because `message` is the one field of a thrown error that reaches the log.
10. **A file written by an older version must still load.** The local archive
    is one JSON file, and Swift's synthesized `Codable` does not use a
    property's default value for a missing key: a non-optional field added
    with a default throws on every old file. Until 4 Sep 2026 `load()`
    answered that by coming up empty and letting the next `save()` write
    empty over the family's only local copy. So a new persisted field is
    `Optional`, or `Snapshot`'s hand-written `init(from:)` reads it
    `IfPresent`; a file that still cannot be read is moved aside, never
    overwritten, and the app says so.

    **Two halves of that are narrower than they read, corrected 9 Sep 2026.**
    The `init(from:)` escape exists only for the ten keys `Snapshot` itself
    declares. A field added to `Subject`, `Memory`, `Relation` or
    `FollowUpQuestion` gets neither protection — `Models.swift` has no
    hand-written decoder anywhere, so those four use the synthesized `Codable`
    this rule is a warning about. **For them, `Optional` is not the preferred
    option; it is the only one.** And `schemaVersion` is written and decoded
    and read by nothing: it is a record of what wrote the file, available to a
    future migration, not a mechanism that does anything today.
    `-store outdated` and `-store unreadable` drive the two UI tests in
    `SilentFailureTests` that keep this true — run them after touching
    `Snapshot` or any persisted model.

## The assistant's rules — checked in, not personal setup

Most of the typing here is Claude Code's, and since **28 Aug 2026** it happens
under a guideline file that lives in the repository:
[`.claude/skills/karpathy-guidelines/SKILL.md`](.claude/skills/karpathy-guidelines/SKILL.md),
vendored unmodified from
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)
(MIT; provenance in `SOURCE.md` beside it). Four rules against the four things a
model does wrong when left to itself: inventing scope, abstracting for a single
caller, tidying code it was not asked to touch, and calling a thing done without
a check that could have failed.

It is checked in rather than left in `~/.claude` for the same reason everything
else here is written down — so that it travels with the clone and can be read
instead of taken on trust.

**It is not retroactive.** Two of the four rules this repository had already
paid for the hard way: *surgical changes* is the staging rule immediately below,
learned from one commit that swept up two other sessions' work; *goal-driven
execution* is why the Commands section is a list of scripts rather than a list
of intentions, learned from four features that were marked done and were not.
That overlap is why the file was adopted, not a claim that the months before it
were worked this way.

A second skill sits beside it in `~/.claude/skills/` and is deliberately **not**
checked in: [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
(MIT), 3.3 MB of design reference across 47 files. One file of it earns its keep
here — `data/ux-guidelines.csv`, 119 rules, 30 of them about accessibility and
motion — and it earns it against [docs/index.html](docs/index.html), the one
surface in this project with no test of its own. The app is not the customer:
the skill's SwiftUI table is 50 rows of basics with zero VoiceOver rows and zero
contrast rows, against the 32 accessibility audits that already run here.

Run over the page on 28 Aug 2026 it produced **one real defect and one false
alarm**: ten headings and no `<h1>` at all, so a screen reader navigating by
level found no page heading — fixed; and a fixed-chrome `scroll-padding-top`
rule that measurement then killed, because the page has exactly one fragment
link and `<main>` already reserves the chrome's height. One in two is the
honest yield, and the second one is why a guideline is read against the page
rather than applied to it.

**The palettes, font pairings and style presets are not to be used at all.**
They are measured on white. `#C2410C` is 5.2:1 on white and 4.43:1 on the
parchment this project actually uses; it failed here and had to be replaced.
Colours come from `Elder.swift` in the app and the six tokens in `kinlore.css`
on the page — and neumorphism and glassmorphism are low-contrast by
construction, which is rule 1 inverted.

## Git — stage only what you changed yourself

Several sessions often work in this worktree at once, on `main`, and a commit is
pushed to the public repo within minutes. A commit here is published by default,
not local.

**Stage files by path, only the ones you changed yourself.** Never `git add -A`,
`git add .` or `git commit -a`: they sweep up another session's half-finished
work, and it has already happened — one piece of work ended up split across
three commits whose messages were about something else entirely. If `git status`
shows changes you did not make, leave them alone and say so.

## Commands

**Most of the checks below are also one command.** `./scripts/verify.sh` runs
every invariant in this repository that costs nothing — and it is what CI's
Invariants job runs, so it is the same green a stranger sees. It skips only
what it says it skips: anything that spends OpenRouter credit, the UI suite
unless `KINLORE_TEST_SIM` names a simulator of your own, and `geo-check.swift`,
which measures somebody else's gazetteer over the network. With a
`npx wrangler dev` running it picks up the eleven backend checks too.

It is listed here because it was not, and the cost of that is the reason
`family_crypto` sits inside it: that check had stopped **compiling** a week
before anybody noticed, because its instruction said to run it after touching
a file nobody had touched. An instruction to run something by hand is a
reminder rather than a check, and it is only as good as whoever last read it.
The individual commands below are still worth having — they are what you run
while working on one thing — but the run before a commit is this one:

```bash
./scripts/verify.sh
```

```bash
# Generate the iOS project. Run this after changing project.yml — and also
# after ADDING OR REMOVING A SOURCE FILE. XcodeGen globs the sources when it
# generates, so a new .swift file is invisible to xcodebuild until this runs,
# and the build fails with "cannot find X in scope" for a type that is plainly
# there on disk. This has cost time twice.
cd ios && xcodegen generate

# A simulator for BUILDING, by UDID. `name=iPhone 17 Pro` does not resolve on
# this machine at all: four simulators carry that name, two of them on the same
# runtime, and an ambiguous name fails as "Unable to find a device matching the
# provided destination specifier" — which reads like a missing simulator and is
# not one. A build touches no device, so sharing this one is fine; the UI tests
# are the case that is not, and they use $KINLORE_TEST_SIM below.
SIM=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list \
  devices available | grep -m1 'iPhone 17 Pro (' \
  | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}')

# iOS build. DEVELOPER_DIR is mandatory: this machine's xcode-select points at
# CommandLineTools, and changing it would need sudo. This overrides it.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "id=$SIM" build

# Accessibility tests. VoiceOver reads the accessibility tree and XCUITest
# queries the same tree, so this is how rule 1 is checked rather than asserted.
# performAccessibilityAudit() also catches contrast, clipping and tap targets —
# it has already found real defects that screenshots did not.
#
# GIVE THE RUN A SIMULATOR OF ITS OWN, by id and not by name. Several sessions
# work in this worktree at once, every one of them targets "iPhone 17 Pro", and
# a UI test does not survive another session launching the app on the same
# device: the audit's target process disappears mid-run.
#
# It does not fail honestly either. Most of it arrives as "Invalid target app
# <pid>", but some of it arrives as ACCESSIBILITY FAILURES THAT ARE NOT REAL —
# one shared run reported ten contrast and clipping issues on a screen that
# passes on its own. Measured: 15 failures on the shared device, 0/17 failures
# on a private one, same commit, minutes apart. Do not chase a red audit before
# checking which device it ran on.
#
#   xcrun simctl create kinlore-tests \
#     com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
#     com.apple.CoreSimulator.SimRuntime.iOS-26-5
#
# iOS-26-5 is the ONLY runtime installed — measured 15 Aug 2026 with
# `xcrun simctl list runtimes`, which prints exactly one line. This file
# previously said 26-2 and claimed 18.6, 26.1 and 26.2 were installed; none of
# the three exists here, and following it fails as "Invalid runtime", which
# reads like a broken Xcode and is not one. Run the list before copying a
# runtime id out of any document, including this one.
#
# RUN IT IN FINNISH. The tests query the accessibility tree by the words on
# screen, and those words are Finnish — `staticTexts["Uutta perheeltä"]`,
# `buttons["Kysy perheeltä"]`. The app's default is English, so a run without
# these two flags fails on tests that are not broken, which is the same wasted
# hour as a shared simulator and looks exactly as convincing.
#
# Measured 8 Sep 2026: `testResultWithKnownNames` looks for "Tutut nimet",
# en.lproj translates that key to "Familiar names", and the test failed on an
# English device and passed on a Finnish one, same commit, minutes apart. It
# was one test then because most Finnish on screen was not being looked up at
# all. Fixing the gallery's four unlooked-up strings the next day made it
# several, which is the fix working — the app now answers in the device's
# language, so the tests have to ask in the app's.
#
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" \
  -testLanguage fi -testRegion FI test

# Backend locally
cd backend && npx wrangler dev

# D1 schema into the local database. FIRST TIME ONLY — this creates the tables,
# it does not migrate them. On a database that already exists it stops on the
# first statement with "table family already exists" and changes nothing, which
# reads like it ran.
#
# That is how a local database ends up several changes behind while looking
# fine. Measured 15 Aug 2026: `subject` was missing `lat`, `lon` and
# `geo_precision` and still carried a `blurhash` the schema had dropped, so
# `place-sync-check.mjs` failed with a 502 whose real cause was
# "D1_ERROR: table subject has no column named lat" in the Worker log — three
# levels away from anything the script prints.
#
# To bring an existing local database forward, run the ALTER statements that
# schema.sql keeps beside the columns they add:
#
#   npx wrangler d1 execute memorize --local --command \
#     "ALTER TABLE subject ADD COLUMN lat REAL;"
#
# Compare first, so you alter what is actually missing:
#
#   npx wrangler d1 execute memorize --local \
#     --command "PRAGMA table_info(subject);"
#
cd backend && npx wrangler d1 execute memorize --local --file=schema.sql

# A copy of the PRODUCTION database as SQL, into backend/backups/ — ignored by
# git, because family and member names are plaintext in it. D1's Time Travel
# keeps the last days of history by itself and needs no command until the day
# it is needed; this is the copy that outlives the account. It carries no R2
# object — the photographs and the voices — and R2 has no versioning to lean
# on. Both facts, the restore commands, and what to do when the account itself
# is gone are in docs/RECOVERY.md: read it BEFORE typing anything on the day
# something has gone wrong, because two of the commands there make things
# worse when run against the wrong target.
cd backend && npm run db:export

# ASR comparison
node scripts/asr-bench.mjs samples/

# The export, opened. The one output that leaves the app for good, and its
# promise — "avautuu millä tahansa koneella ilman tätä sovellusta" — is not
# something XCUITest can check: the file lands in the app's container and the
# test runner may not look inside it. Records a memory first, because the demo
# archive has no media and an export of it looks complete while carrying none.
# Needs a booted simulator with the app installed; set KINLORE_TEST_SIM.
node scripts/export-check.mjs

# When the paid archive is offered. Four lines of arithmetic over one
# UserDefaults key, and every way they can go wrong is silent: an offer after
# every story, or none ever, or one landing beside the names rule 4 asks a human
# to check. Run it after touching UpsellRhythm.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/upsell-rhythm-check \
  scripts/upsell-rhythm-check.swift ios/Kinlore/Services/UpsellRhythm.swift \
  && /tmp/upsell-rhythm-check

# The family's bytes on every phone. After a sync, the photographs and voices
# that exist only in R2 are fetched here in the background — voices first, on
# Wi-Fi only, never the last gigabyte, three failures ending a round, the
# store written every tenth file rather than every file — so the phone is a
# copy of the archive and not a window onto one (docs/RECOVERY.md).
# Every rule is silent when wrong: a copy that never starts looks exactly like
# one that is complete. Run it after touching FullCopy.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/full-copy-check \
  scripts/full-copy-check.swift ios/Kinlore/Services/FullCopy.swift \
  && /tmp/full-copy-check

# Encryption at rest. The one place in this app where being wrong is silent
# AND permanent: a memory sealed under the wrong key still syncs, still draws a
# row, and is simply unreadable — and by then the plaintext is gone. Also
# asserts the claim lever 3 actually makes, that none of the words cross to the
# Worker. Run it after touching FamilyCrypto.swift or the sealing in
# MemoryStore+Sync.swift.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/family-crypto-check \
  scripts/family-crypto-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
  && /tmp/family-crypto-check

# The same sealing, end to end: two identities through a real Worker, the key
# crossing only in the invite text, D1 rows and R2 bytes checked sealed and
# opened byte for byte on the second identity (PLAN §10 lever 3's "test to run
# the day it deploys" — first production run 24 Aug 2026). Same compile line
# with the round-trip source; needs `npx wrangler dev`, and against production
# pass https://memorize.arkiste.workers.dev instead. Leaves one throwaway
# family behind wherever it runs.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/lever3-roundtrip-check \
  scripts/lever3-roundtrip-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
  && /tmp/lever3-roundtrip-check http://localhost:8787

# Whether a browser can read this archive at all. Every argument for reaching
# anyone off an iPhone — an Android relative, the universal link ARCHITECTURE §4
# has wanted since August, any web surface at all — rests on one claim about
# lever 3: that WebCrypto opens what CryptoKit sealed. That claim was reasoning,
# and it was used in BOTH directions before it was measured — once to argue a web
# surface is impossible, which it is not. Measured 8 Sep 2026: 9 of 9, both
# directions. `webcrypto.subtle` is the same API a page gets, so what passes here
# passes in Safari; there is no library and no polyfill, because a helper would
# be a second implementation and the check would be measuring the helper.
#
# The one nobody expected: the browser can REPRODUCE the deterministic nonce
# (HMAC-SHA256 of the plaintext, truncated to 12 bytes), so a web client could
# write a title without `sync.ts` reading every push as a rename. Reading never
# needed that. It came free.
#
# Costs nothing — no Worker, no key, no network. Run it after touching
# FamilyCrypto.swift, and before believing anything about a web client.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/webcrypto-interop-check \
  scripts/webcrypto-interop-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
  && /tmp/webcrypto-interop-check emit \
   | node scripts/webcrypto-interop-check.mjs /tmp/kinlore-webcrypto-return.json \
  && /tmp/webcrypto-interop-check verify /tmp/kinlore-webcrypto-return.json

# Place coordinates through sync. Checks the four rules that are silent when
# broken: a resolved point round-trips, a device that has not looked the name up
# cannot wipe it, correcting the title clears it, and rubbish is refused. Costs
# nothing — no AI call — but needs `npx wrangler dev` running.
node scripts/place-sync-check.mjs

# The pull cursor, which is the delivery guarantee itself. Three defects lived
# in this one number (found 23 Aug 2026, ARCHITECTURE §3) and every one showed
# a working app while a telling silently never reached another phone: a cursor
# advanced from a push reply, a seq reservation that was not atomic, and a
# reply cursor that ran past a capped table. The rule they left behind — the
# cursor moves only through pull replies — is Swift's half to keep; this
# drives the server's half. Needs `npx wrangler dev`.
node scripts/sync-cursor-check.mjs

# The invite link, which §4 calls the entire security boundary. Six rules that
# are silent when broken: a code expires, a code can be revoked, a code belongs
# to one family, a code admits one person, the owner can close the door behind
# somebody who should not have come through it, and a wrong code answers
# exactly like an expired, revoked or used one — a different answer would tell
# a guesser they had found a real family. Needs `npx wrangler dev`; leaves two
# throwaway families behind.
node scripts/invite-boundary-check.mjs

# One purchase, one family. Loads the real schema.sql into an in-memory SQLite
# and asks it: the same customer id cannot unlock two families, a refund finds
# exactly one payer, and a restore inside the family still works. Costs nothing
# — no Worker, no D1, no RevenueCat — and the guard it backs up cannot be run
# on this machine at all. After touching the member table or entitlement.ts.
node scripts/entitlement-binding-check.mjs

# When the webhook may take the paid tier away. Drives the real handleWebhook
# over the shipping schema in in-memory SQLite — no Worker, no RevenueCat
# secret. The rule is RevenueCat's and was assumed wrong once: there is no
# REFUND event (a refund is CANCELLATION with cancel_reason CUSTOMER_SUPPORT),
# and a plain auto-renew-off must keep the tier until EXPIRATION — the old set
# locked a family out of a month somebody had paid for. After touching
# entitlement.ts.
node scripts/webhook-revocation-check.mjs

# The other half of the same arc: /entitlement/sync does not accept a state
# from the client, it asks RevenueCat. That claim went unchecked until 1 Sep
# 2026 because it looked as though it needed a key, and it does not — the real
# syncEntitlement runs over the shipping schema with `fetch` replaced by
# something that answers like RevenueCat and keeps the request. Nothing leaves
# the machine, which matters twice here: the request that proves the payer's
# account is protected must not be the request that sends it anywhere. Pins the
# claim the endpoint exists for, the 409 before any upstream call, the restore,
# the two-payer rule, and rules 7 and 9 on the one path whose upstream body is
# somebody's account. After touching entitlement.ts.
node scripts/entitlement-sync-check.mjs

# The transcription's output budget. `complete()` sends no cap unless told
# one, and the route's default is low: a long telling came back cut off, was
# rejected whole, and after three attempts the catch-up gave up on it. The
# budget is the hallucination bound turned into tokens, and both ways of being
# wrong are silent. Runs on Node's own type stripping — no build, no Worker,
# no key. After touching budget.ts or transcribe.ts.
node scripts/transcribe-budget-check.mjs

# Place lookup. Re-measures the claims in ARCHITECTURE.md §18 against the real
# MapKit answers — they are claims about somebody else's gazetteer, and they can
# stop being true without this repo changing. Needs a network; run it after
# touching PlaceLookup.swift, and before believing §18.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -o /tmp/geo-check scripts/geo-check.swift \
  ios/Kinlore/Services/PlaceLookup.swift && /tmp/geo-check
```

## Environment notes

- **`sudo` is not available.** Do not suggest `xcode-select -s` — use the
  `DEVELOPER_DIR` variable as in the command above. **Xcode 26.6, iOS 26.5
  simulator SDK, one runtime (`iOS-26-5`)** — measured 15 Aug 2026 with
  `xcodebuild -version`, `-showsdks` and `simctl list runtimes`.

  This entry said "Xcode 26.2, iOS 26.2" and asserted that *"this file said
  26.6 / 26.5 for a while; neither has ever been on this machine"* — which was
  exactly backwards, since 26.6 and 26.5 are what is installed and 26.2 is not.
  A correction was made in the wrong direction and then stated with confidence,
  which is worse than leaving a version out. **Measure before editing this
  line**, and paste the command output rather than a remembered number.
- **The simulator is shared; the UI tests must not be.** Building on the shared
  device is fine — a build touches no device. Running the app and running the
  tests are not: they install, launch and terminate one bundle id, and two
  sessions doing that at once take turns killing each other's process. Use a
  device of your own and **never shut down or reboot a booted one you did not
  create** — somebody else is very likely mid-run on it.
- **A device of your own is the rule; a device left booted is the cost.** Eight
  were booted here at once on 16 Aug — three sessions of this project, another
  project's two, and a stray — and a run of the UI suite died with

      IDELaunchReport: Finished with error: The operation couldn't be
      completed. (Mach error -308 - (ipc/mig) server died)

  before a single test executed. **A starved machine does not only kill runs, it
  invents findings.** The next attempt crawled through in two hours instead of
  fourteen minutes and reported two failures: one audit that timed out after
  33 minutes, and one Dynamic Type finding on a sheet's *"Peruuta"*. That sheet
  then passed three times in a row on a quiet machine, same commit, 36–47
  seconds each. Nothing was wrong with it.

  So: `xcrun simctl list devices | grep -c "(Booted)"` before believing either a
  dead run or a surprising finding, and delete your own device when you are
  finished rather than leaving it booted for the next session to inherit. Two
  sessions keeping one each is fine; six is the error above.
- `xcrun simctl` is not on the path xcodebuild hands to its own child processes,
  so a test run ends with `unable to find utility "simctl"` while collecting
  diagnostics. It is noise from a run that had already failed, not the failure.
  Prepending `/Applications/Xcode.app/Contents/Developer/usr/bin` to `PATH`
  silences it.
- The name is **Kinlore** and the bundle ID is `com.kinlore.app` (renamed
  15 Aug 2026, PLAN.md §10). The backend's Cloudflare resources are deliberately
  still called `memorize`: renaming an R2 bucket means making an empty new one,
  and rule 3 lives in that bucket.
- Purchases go through the **RevenueCat Test Store**, not App Store Connect
  products. No paid Apple Developer account is needed — and **the Test Store has
  no bundle-id field**, so the rename needed nothing there. It is keyed by its
  API key. A bundle id becomes a RevenueCat setting only when an App Store app
  config is added, which is a §2.1 decision and not a current one.
