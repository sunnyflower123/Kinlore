# Memorize

A family's shared memory archive. An old person rambles; the AI gives it
structure. Side project for RevenueCat Shipaton 2026.

**Target category: Next Gen** (student category). **No App Store release** — it
was dropped because upper secondary school starts around 11 Aug and there is no
time for App Store Connect. Deadline: Devpost submission 28 Sep 2026. Purchases
run on the RevenueCat Test Store.

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
docs/      PLAN.md, ARCHITECTURE.md, SETUP.md
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
2. **Telling is never paywalled.** The paywall limits photos and AI minutes, not
   the act of writing or dictating a memory.
3. **The original audio and the raw transcript are always kept.** The speaker
   may no longer be around to ask. `memory.audio_r2_key` and
   `memory.raw_transcript` are not intermediate steps; they are the product.
4. **AI proposes, a human confirms.** A person or relationship inferred by the
   AI is created with `confirmed = 0`. Unconfirmed never appears in the family
   tree as fact. A wrong relationship is worse than a missing one.
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
9. **The cause of an error never leaks to the client.** Upstream bodies go only
   to `console.error`: they can contain account details or echo back the memory
   the user just told. The app gets `{ error: "upstream_failed" }`.

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

# iOS build. DEVELOPER_DIR is mandatory: this machine's xcode-select points at
# CommandLineTools, and changing it would need sudo. This overrides it.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Memorize.xcodeproj -scheme Memorize -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Backend locally
cd backend && npx wrangler dev

# D1 schema into the local database
cd backend && npx wrangler d1 execute memorize --local --file=schema.sql

# ASR comparison
node scripts/asr-bench.mjs samples/
```

## Environment notes

- **`sudo` is not available.** Do not suggest `xcode-select -s` — use the
  `DEVELOPER_DIR` variable as in the command above. Xcode 26.6, iOS 26.5
  simulator SDK.
- The app name and bundle ID are still provisional (`app.memorize.Memorize`),
  see PLAN.md §10.
- Purchases go through the **RevenueCat Test Store**, not App Store Connect
  products. No paid Apple Developer account is needed.
