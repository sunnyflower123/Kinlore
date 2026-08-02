# Accounts and API keys

In short: **three secrets in the backend, one public key in the app, nothing
from Apple.** Development costs over two months land in the low tens of euros.

## The ground rule

**ASR and LLM keys live only in the Worker's secrets, never in the iOS app.**
Unpacking an IPA is trivial, and a leaked key is a real bill on a student
budget. This dictates the architecture:

```
iOS  ──audio──▶  Worker  ──▶  ASR service
                    │
                    └────────▶  LLM (extraction)
```

The app never talks directly to OpenAI or similar. That is why uploading audio
to the Worker sits on the critical path of week 2.

## Keys required

### Backend — as Worker secrets

| Key | What for |
|-----|----------|
| **`OPENROUTER_API_KEY`** | **Both transcription and extraction.** OpenRouter has no separate transcriptions endpoint — audio goes as an `input_audio` part of chat completions, base64 encoded, so one key covers both. |
| `RC_SECRET_KEY` | RevenueCat's v2 REST API. The backend verifies the payer's entitlement and maps it to the whole family. |
| `RC_PROJECT_ID` | The project identifier from the dashboard (not a secret, lives in `wrangler.jsonc` vars). |
| `RC_WEBHOOK_SECRET` | Authentication for subscription events (renewal, cancellation) → `family.entitlement`. Without it anyone could forge a subscription. |

```bash
cd backend
npx wrangler secret put OPENROUTER_API_KEY
```

Models are chosen in `wrangler.jsonc` vars, not in code: `MODEL_EXTRACT` and
`MODEL_TRANSCRIBE`. The transcription model is a separate variable because it
may switch to a dedicated ASR if the comparison shows one to be better.

**Local development.** Create `backend/.dev.vars`:

```
OPENROUTER_API_KEY=sk-or-...
```

It is already in `.gitignore` — **check anyway before the first push**, because
the repo is public. After that:

```bash
cd backend && npx wrangler dev
```

The app uses stubs until it is told the backend's address. Switch the real
services on with a launch argument:

```
-api http://localhost:8787
```

Without it the app still works completely — that is deliberate, so development
does not stop when the Worker is broken or there is no network.

### Health check

```bash
curl -s http://localhost:8787/health
```

Returns `{"ok":true,"hasKey":true}` when the key is in place. If `hasKey` is
`false`, extraction answers `502 upstream_failed` — the cause goes only to the
Worker's log, never to the app, because it can contain account details or echo
back the memory the user just told.

### iOS app — public

| Key | Note |
|-----|------|
| RevenueCat **Test Store API key** | Designed for the client side, safe to embed. Supplied with the launch argument `-rcKey <key>` so Test Store and production can be swapped without recompiling. Without a key, purchases are unavailable but the app works normally. |

## Launch arguments

Everything the app can be told from outside, in one place. In Xcode they go
under Product → Scheme → Edit Scheme → Run → Arguments; from the command line,
after the bundle id:

```bash
xcrun simctl launch <device> app.memorize.Memorize -tab people -screen person
```

| Argument | Build | What it does |
|---|---|---|
| `-api <url>` | any | Points the app at a backend. Without it the app runs on stubs — deliberately, so development does not stop when the Worker is broken. |
| `-rcKey <key>` | any | The RevenueCat Test Store key. Without it purchases and the paywall do not exist, and the app works normally. |
| `-tab memories` / `-tab people` | DEBUG | Opens on that tab instead of Tell. |
| `-screen write` | DEBUG | Opens the typing view directly. |
| `-screen interview` | DEBUG | Runs a canned memory through the stub pipeline and enters the interview loop, finishing the first spoken round by itself — the whole loop, hands-free. |
| `-comfort <1–5>` | DEBUG | Puts the question ladder at a given level instead of where the answers have taken it. Level 1 offers naming questions, level 5 reflective ones — the whole progression without answering six questions first. See ARCHITECTURE.md §12. |
| `-screen starter` | DEBUG | Opens the Tell screen on a photo nobody has spoken about yet, where the starter questions live. Otherwise that state is reachable only by picking a photo from the library by hand. |
| `-screen person` | DEBUG | Opens the first person's card, relationships and all. |
| `-screen family` | DEBUG | Opens the family view: members, usage, invite link. |
| `-screen settings` | DEBUG | Opens Settings: export, leaving the family, emptying the device. |
| `-screen export` | DEBUG | Opens Settings and runs the export at once, logging where the zip landed. The export is the one output that leaves the app for good, so it is worth opening the real file. |
| `-guess demo` | DEBUG | Builds guessing rounds from memories you told yourself. A round normally needs a second family member — a screenshot run and the demo phone both have one device. |
| `-seed guess` | DEBUG | **Replaces** the archive with a canned family that has a guessing round waiting. What the UI tests launch with, and the fastest way to reach the round by hand. |
| `-seed empty` | DEBUG | **Empties** the archive. The empty states are a screen each, and on a device that has ever been used they are otherwise unreachable. |
| `-defer once` | DEBUG | Records a couple of seconds and has the transcription fail as though the month's AI minutes had just run out, leaving the memory waiting for its text. The next launch runs the catch-up and finishes it, so the two together are one filmable sequence. The real trigger is an outage nobody can schedule. See ARCHITECTURE.md §16. |

These exist because some screens sit behind a tap, and two things that need to
reach them have no hands: a screenshot run, and **filming the demo video**
(PLAN.md §3, phase F). They also make the accessibility sweep possible at all —
checking a screen at the largest text size means being able to open it.

Debug arguments are Finnish-free on purpose; they are a developer interface, so
they follow the repo's language rule rather than the app's. See CLAUDE.md.

### Cloudflare

No manual key. `npx wrangler login` handles it via OAuth.
`CLOUDFLARE_API_TOKEN` is only needed if CI is ever set up.

## What is NOT needed

- **Apple: nothing.** No $99 account, no Sign in with Apple, no APNs certificate.
- **Google / Firebase:** nothing.
- **Email service:** nothing, because authentication is device based.
- **OneSignal:** dropped from scope along with push notifications.

## Authentication without a login screen

A paid Apple Developer account is available, so Sign in with Apple, push, iCloud
and App Groups **would** be technically possible. Authentication is still done
without them — not because of a constraint, but because it is better for this
audience:

1. On first launch a UUID is generated and stored in the Keychain with the
   `kSecAttrSynchronizable` flag. iCloud Keychain syncs it between the user's
   devices — this does not require an iCloud entitlement, so it works on a free
   account.
2. The backend issues a member id for this identity.
3. You join a family with an invite link. No email, no password, no login screen.

**An 80-year-old never hits a login wall** — she gets a link from a grandchild
and she is in. That is precisely the point where this audience normally drops out.

The honest downside: losing the device loses the identity if iCloud Keychain is
off. The mitigation: the family owner can re-invite, and nobody loses memories —
they belong to the family, not to the member.

**Sign in with Apple will be adopted only as optional account recovery for a
paying member**, never as anyone's gate in. A grandchild buying a subscription
justifiably wants it tied to something permanent; grandmother does not want to
sign in to anything. Those are different needs and should not be solved on the
same screen. This is a v1.1 matter, not an MVP one.

## Cost estimate during development

Orders of magnitude; check current prices yourself:

| Service | Estimate |
|---------|----------|
| OpenRouter, transcription (Gemini Flash, audio input) | Audio is billed as tokens and costs more than text — this is the single largest item |
| OpenRouter, extraction | A 90 s memory ≈ 300 tokens in, 500 out — clearly under a cent per memory |
| Alternative for transcription: Groq whisper-large-v3 | The free tier covers development. Worth comparing if the audio token price surprises you |
| Cloudflare Workers + D1 + R2 | The free tier is enough for a hackathon. R2 has no egress fees, which matters here because audio is kept permanently |
| RevenueCat | Free below $2,500 monthly revenue |

**Realistic total for two months: under €20.** The largest single item is ASR,
and only if you test a lot of long recordings.

## Order of operations for week 0

1. Cloudflare account + `wrangler login`, `d1 create`, `r2 bucket create`
2. One ASR key → run `scripts/asr-bench.mjs`
3. RevenueCat account → project → Test Store → test key
4. LLM key (can be the same as the ASR one)
