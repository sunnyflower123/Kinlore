<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/lockup-dark.svg">
    <img src="docs/logo/lockup.svg" alt="Memorize" width="340">
  </picture>
</p>

> Working title. To be changed before release — see [docs/PLAN.md](docs/PLAN.md) §10.

A family's shared memory archive. An old person rambles; the AI turns it into
structure: memories attach to photos and people, the family tree grows out of
the stories, and open questions come back to be asked.

The problem being solved: grandparents *know*, but cannot explain in a
structured way. They do not fill in forms and they do not tag photos — they
talk. Existing album and genealogy apps demand structured input from the one
person who will never produce it, and so the knowledge disappears at the funeral.

Side project for the [RevenueCat Shipaton 2026](https://revenuecat-shipaton-2026.devpost.com/)
hackathon. Target category: **Next Gen Award** (student category).

## Layout

| Directory | Contents |
|-----------|----------|
| `ios/` | SwiftUI app. The project is generated from `project.yml` with XcodeGen. |
| `backend/` | Cloudflare Worker + D1 (metadata) + R2 (photos and audio). |
| `scripts/` | `asr-bench.mjs` — Finnish speech recognition comparison. |
| `docs/` | `PLAN.md` (scope, schedule, risks), `ARCHITECTURE.md`, `SETUP.md`, `logo/` (the mark and why it looks like that). |

## Two languages, on purpose

The repo is written in **English**: docs, comments, identifiers, commit
messages. The app's user interface is **Finnish**, because the person it exists
for is a Finnish 80-year-old. A handful of Finnish strings therefore live in the
source on purpose — the boundary and its exceptions are spelled out in
[CLAUDE.md](CLAUDE.md).

## Development environment

```bash
# iOS
cd ios && xcodegen generate && open Memorize.xcodeproj

# Backend
cd backend && npm install
npx wrangler d1 execute memorize --local --file=schema.sql
npx wrangler dev
```

When building from the command line, `DEVELOPER_DIR` is mandatory because this
machine's `xcode-select` points at CommandLineTools:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Memorize.xcodeproj -scheme Memorize -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Before the first cloud deploy, create the resources and update `database_id` in
`backend/wrangler.jsonc`:

```bash
npx wrangler d1 create memorize && npx wrangler r2 bucket create memorize-media
```

## The core of the data model

A single `subject` table covers photos, people, places and events; a `memory`
attaches to any subject. That is why *"write a memory about this photo"* and
*"tell us what grandmother was like"* are the same screen and the same code path.
Schema: [backend/schema.sql](backend/schema.sql).

## Licence

[MIT](LICENSE).
