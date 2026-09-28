# Kinlore

A family's shared memory archive. Anyone in the family tells what they
remember, out loud or in writing, and the AI gives it structure: memories
attach to photos and people, the family tree grows out of the stories, and
open questions come back to be asked. It is an entry in the RevenueCat
Shipaton 2026 hackathon (Next Gen, the student category); purchases run on the
RevenueCat Test Store, and there is no App Store release.

The plan and the scope are in [docs/PLAN.md](docs/PLAN.md). Read it before
adding features: the scope is deliberately cut, and every addition requires a
removal.

## Layout

```
ios/       SwiftUI app, generated with XcodeGen (project.yml → .xcodeproj)
backend/   Cloudflare Worker + D1 (metadata) + R2 (photos and audio)
scripts/   verify.sh and the checks it runs, asr-bench.mjs, the logo tooling
docs/      PLAN, ARCHITECTURE, DETAILS, DEVELOPMENT, SETUP, UX, VIDEO, RECOVERY
```

[docs/DETAILS.md](docs/DETAILS.md) is the long write-up behind the README, and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) the long form of this file. The
Cloudflare resources keep the old name `memorize`, because an R2 bucket cannot
be renamed, only recreated empty, and rule 3 lives in that bucket.

## Language

The repository is in English: docs, code comments, commit messages,
identifiers, developer log output, test names, debug launch arguments and
config comments. What the app's user sees or hears is written in Finnish and
shown in English by default, because the app is presented, judged and filmed in
English. The app follows the device, so a Finnish phone gets Finnish.

- The Finnish strings in the Swift source are the localisation keys. SwiftUI
  reads a literal in `Text`, `Button`, `Label`, `navigationTitle` and
  `accessibilityLabel` as a `LocalizedStringKey`, and the export uses
  `String(localized:)`, so new user-facing text is still written in Finnish.
- `en.lproj` holds the English and `fi.lproj` maps every key to itself, because
  a missing key falls back to English, the development language.
  `scripts/localisation-check.mjs` fails if either table is short. Nothing else
  notices: the build succeeds either way.
- A runtime `String` is shown verbatim, so a fallback name built in a computed
  property (`Subject.displayTitle`'s "Valokuva", `SubjectKind.label`) must use
  `String(localized:)`. The check above cannot see a missing lookup.
- A ternary of literals is still a `LocalizedStringKey`, and both branches are
  looked up. It is a `String` only when a branch is one (`String(localized:)`,
  a `+`, a variable) or when it sits inside an interpolation. The check does
  not look inside a ternary's branches.

Two things stay Finnish although no user reads them. The test transcripts and
TTS sample texts in `scripts/` are the input under test. The Finnish prompts in
`backend/src/extract.ts` and `backend/src/transcribe.ts` were tuned by
measurement, so do not edit them in passing. The English prompts beside them
differ on purpose: rule 1 of the Finnish prompt teaches a model about case
endings and has no English counterpart, and its rules 2, 3 and 5 hold the
filler words and common nouns that were tuned. The speaker's language picks the
prompt, whatever the screen shows: the app sends `lang`, and a request without
it is Finnish. `MAX_WORDS_PER_SECOND` in `backend/src/budget.ts` has a value per
language for the same reason. Write anything new in English from the start.

## Data model

One `subject` table covers photos, people, places and events, and a `memory`
attaches to any subject. That is why "write a memory about this photo" and
"tell us what grandmother was like" are the same screen and the same code path.
Do not split them into separate implementations; the whole architecture rests
on this. Schema: [backend/schema.sql](backend/schema.sql).

## Rules that do not bend

1. **The primary user is whoever wants to tell, often an older person.**
   Dynamic Type up to XXL, VoiceOver and large tap targets. A screen that fails
   at the largest text size is not done. This is not a compliance checklist; it
   is the product. Colours come from `Elder.swift` and the accent colour asset,
   never from `.secondary`, `.tertiary`, `.orange`, `.red` or the system blue:
   all of them measure below the contrast minimum, and contrast is the one rule
   eyes cannot check. Run the accessibility tests after touching a screen
   ([ARCHITECTURE §15](docs/ARCHITECTURE.md#15-contrast--the-rule-that-was-never-measured)).
2. **Telling is never paywalled.** The paywall limits photos, AI minutes and
   colourisations, never writing or dictating a memory. The grandparent who
   tells is not the one who pays, and a wall in front of telling would stop the
   one person whose stories the archive exists to keep.
3. **The original audio and the raw transcript are always kept.** The speaker
   may no longer be around to ask. `memory.audio_r2_key` and
   `memory.raw_transcript` are the product, not an intermediate step.
4. **AI proposes, a human confirms.** A person or relationship the AI infers is
   created with `confirmed = 0` and never appears in the family tree as fact. A
   wrong relationship is worse than a missing one.

   The strongest confirmation is blind, because a card with the name already on
   it gets tapped "yes" without being read. The blind card
   (`BlindConfirmation`, `BlindCardView`,
   [ARCHITECTURE §23](docs/ARCHITECTURE.md#the-blind-confirmation-built-30-aug-2026))
   shows the photograph a name was heard in and asks *Who is this?* (*Kuka
   tässä on?*) over three or four names, the proposal unmarked among them. It
   sits on the Tell tab (*Kerro*) of a reader's phone and on the Album tab
   (*Albumi*) of a grandparent's. A wrong answer is never called wrong,
   because the app does not know who is in the photograph either. Nothing on
   the screen may name the proposal, the photograph's accessibility label
   included; a card that leaks looks like one that works, so
   `BlindConfirmationTests` walks every element on it. The orange proposal row
   on the person list and in the Tell result is the weaker instrument, kept for
   a name heard in a telling about a person, which has no photograph to show.
5. **Uncertainty is stored, not rounded.** "Sometime in the fifties" goes into
   `date_start`/`date_end` with precision `decade`. Do not force a date:
   anything sharper than what was said is a guess stored as fact.
6. **No login screen.** Identity is a UUID in the Keychain
   (`kSecAttrSynchronizable`), and you join a family through an invite link. A
   login wall would drive away exactly the user the app exists for. Sign in
   with Apple is possible and still not a gate; at most it could become optional
   account recovery for a paying member in v1.1 ([docs/SETUP.md](docs/SETUP.md)).
7. **`OPENROUTER_API_KEY` lives only as a Worker secret.** The app uploads audio
   and text to the Worker, and the Worker calls OpenRouter. Unpacking an IPA is
   trivial, and a leaked key is a real bill. `scripts/secret-check.mjs` runs
   first in `verify.sh`: it checks that `.dev.vars` is ignored and untracked and
   scans the tree and every blob that has ever existed, because a public
   repository publishes its history and a committed key can only be undone by
   rotating it and rewriting every commit after it.
8. **`provider: { data_collection: "deny" }` is unconditional**, never a
   per-call flag. The content is a family's memories of dead relatives. As a
   flag it would be forgotten on some call.
9. **The cause of an error never leaks to the client, and the log is not a
   place to leak it instead.** The app gets `{ error: "upstream_failed" }`.
   Upstream bodies and model output stay out of `console.error` too:
   `observability` is on in `wrangler.jsonc`, so Workers Logs is a store beside
   D1 and R2, and the one a family cannot export, cannot clear with *Clear it
   and start again* (*Tyhjennä ja aloita alusta*), and never agreed to. Log
   shape, length, counts, status and the provider's own error codes. An error
   message must not interpolate content (a title, a transcript, a name),
   because `message` is the one field of a thrown error that reaches the log.
10. **A file written by an older version must still load.** The local archive
    is one JSON file, and Swift's synthesized `Codable` ignores a property's
    default value for a missing key: a non-optional field added with a default
    throws on every old file, and a `load()` that came up empty would let the
    next `save()` write empty over the family's only local copy. So a new
    persisted field is `Optional`, or `Snapshot`'s hand-written `init(from:)`
    reads it with `decodeIfPresent`, which covers only the keys `Snapshot`
    declares. `Subject`, `Memory`, `Relation` and `FollowUpQuestion` use
    synthesized `Codable`, so a field added to them must be `Optional`. A file
    that still cannot be read is moved aside, never overwritten, and the app
    says so. `schemaVersion` records what wrote the file and is read by
    nothing yet. In the other direction, a `String` enum (`RelationKind`)
    fails to decode on a value a later version adds, so `Snapshot` reads
    `relations` row by row and counts what it leaves out. The wire drops such
    a row too, so the store records the relationship and subject kinds it
    knows (`sync.kindsKnown`), and a build that knows more pulls the family
    again from the start ([ARCHITECTURE §3](docs/ARCHITECTURE.md#3-sync)).
    `-store outdated`, `-store unreadable` and `-store unknownKind` drive the
    three UI tests in `SilentFailureTests`; run them after touching `Snapshot`
    or any persisted model.

## Working here

- Run `./scripts/verify.sh` before you commit. It runs every check that costs
  nothing, as CI does, and skips anything that spends OpenRouter credit.
- Several sessions often work here at once, on `main`, in one working tree
  with one git index. Commit by path: `git commit -F <message-file> -- <paths>`,
  after `git add -N` for a new file. Never `git add -A`, `git add .` or
  `git commit -a`, which sweep up another session's half-finished work. Read
  `git diff -- <path>` first, because another session may have edited the same
  file ([the full rule](docs/DEVELOPMENT.md#git--commit-by-path-because-the-index-is-shared)).
- Run experiments in a worktree of your own, never by editing a shared file:
  `git worktree add --detach /tmp/try HEAD`. Whoever makes a worktree removes
  it once its work has landed.
- Run `cd ios && xcodegen generate` after changing `project.yml` or adding or
  removing a Swift file. Until then `xcodebuild` cannot see a new file.
- Run the UI tests on a simulator of your own, by UDID, with
  `-testLanguage fi -testRegion FI`. A run installs, launches and terminates
  the app, so two runs on one simulator kill each other and report
  accessibility failures that are not real. The tests find elements by their
  Finnish text, so a run in English fails on tests that are not broken. Never
  shut down or reboot a simulator you did not create.
- Prefix `xcodebuild` and `xcrun` with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`: `xcode-select`
  points at the Command Line Tools here, and sudo is not available.
- Take colours only from `Elder.swift` and the accent colour asset (rule 1).
- Follow [the karpathy-guidelines skill](.claude/skills/karpathy-guidelines/SKILL.md),
  vendored unmodified under MIT with its provenance in `SOURCE.md`;
  [DEVELOPMENT.md](docs/DEVELOPMENT.md#the-assistants-rules--checked-in-not-personal-setup) says why it is checked in.

## Commands

```bash
./scripts/verify.sh               # before every commit
cd ios && xcodegen generate       # after project.yml changes or adding/removing a Swift file
cd backend && npx wrangler dev    # the Worker locally

# A simulator of your own (runtime ids: `xcrun simctl list runtimes`), then the UI tests.
export KINLORE_TEST_SIM=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl create kinlore-tests com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$KINLORE_TEST_SIM" \
  -testLanguage fi -testRegion FI test
```

The per-file checks, when to run each, and every other command with the reason
it exists are in [DEVELOPMENT.md](docs/DEVELOPMENT.md#commands).
