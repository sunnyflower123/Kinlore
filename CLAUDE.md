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

**One requirement is still unmet: the repository is private.** Measured 16 Aug
2026 — `api.github.com/repos/sunnyflower123/Kinlore` answers 404 unauthenticated
while `git ls-remote` works with credentials, which is what GitHub does for a
private repo. Next Gen asks for *"a link to your public, open-source code
repository, including an open-source license file"*, so this blocks the
submission rather than merely looking untidy, and every claim in this file about
the repo being a shop window assumes the change has been made.

Making it public is safe and was checked rather than assumed: `.dev.vars` is in
`.gitignore`, has never been committed, and no key-shaped string appears
anywhere in history. It is one setting, not a cleanup. Doing it early also makes
GitHub Actions free, which is why `ci.yml` runs its expensive half only on pull
requests today.

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
| Whoever uses the app | **Finnish** | Every string the user sees or hears — labels, accessibility labels, `Info.plist` usage descriptions, user-facing error messages |

Three things stay Finnish even though no user reads them, and each has a reason:

1. **LLM system prompts and JSON-schema `description` fields**
   (`backend/src/extract.ts`, `backend/src/transcribe.ts`). They instruct the
   model about Finnish morphology and were tuned by measurement. Rewriting them
   is a behaviour change, not a translation, and it cannot be re-validated
   without spending credits.
2. **Test transcripts and TTS sample texts** (`scripts/`). That is the input
   under test. Translating it would test a different thing.
3. **Server-side default display names** (`'Perhe'`, `'Minä'`, `'Perheenjäsen'`
   in `backend/src/family.ts`). They are written straight into the app's UI.

Everything new follows this rule from the start. Do not write a Finnish comment
now and translate it later — the translation pass has already happened once.

## Layout

```
ios/       SwiftUI app, XcodeGen (project.yml → .xcodeproj)
backend/   Cloudflare Worker + D1 (metadata) + R2 (photos and audio)
scripts/   asr-bench.mjs — Finnish speech recognition comparison
docs/      PLAN.md, ARCHITECTURE.md, UX.md, SETUP.md, VIDEO.md
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

   This rule used to name a *blind* confirmation as the strongest kind the app
   collects — somebody who was never shown the name and arrived at it anyway —
   and pointed at the guessing round. **The round was cut on 16 Aug 2026**
   (PLAN.md §5, row 8), so what is left is the orange proposal row on the person
   list and in the Tell result: a card with the name already on it. That is a
   weaker instrument and the rule should say so rather than quietly inherit the
   old sentence. If confirmation ever needs strengthening again, ARCHITECTURE
   §13 records what blind confirmation was and why it worked.
5. **Uncertainty is stored, not rounded.** "Sometime in the fifties" goes into
   `date_start`/`date_end` with precision `decade`. Do not force a date.
6. **No login screen.** Identity is a UUID in the Keychain
   (`kSecAttrSynchronizable`); you join a family through an invite link. A paid
   Apple account exists, so Sign in with Apple *would* be possible — it is still
   not used as a gate, at most as an optional account recovery for a paying
   member in v1.1. See [docs/SETUP.md](docs/SETUP.md).
7. **`OPENROUTER_API_KEY` lives only as a Worker secret.** The app uploads audio
   and text to the Worker; the Worker calls OpenRouter. The repo is public —
   check `.dev.vars` before every push.
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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" test

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

# The invite link, which §4 calls the entire security boundary. Four rules that
# are silent when broken: a code expires, a code can be revoked, a code belongs
# to one family, and a wrong code answers exactly like an expired or revoked one
# — a different answer would tell a guesser they had found a real family.
# Needs `npx wrangler dev`; leaves two throwaway families behind.
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
