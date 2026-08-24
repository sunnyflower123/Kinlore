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

A **DEBUG** build uses stubs until it is told the backend's address. Switch
the real services on with a launch argument:

```
-api http://localhost:8787
```

Without it a DEBUG build still works completely — that is deliberate, so
development does not stop when the Worker is broken, and so no test, demo or
screenshot run ever talks to production by accident.

A **Release** build defaults to production (`https://memorize.arkiste.workers.dev`,
baked into `AppServices` on deploy day, 24 Aug 2026 — docs/UX.md §7). So a
phone that should behave like a real install runs the Release configuration
(Xcode: Product → Scheme → Edit Scheme → Run → Build Configuration), or a
DEBUG build with `-api https://memorize.arkiste.workers.dev` in the scheme —
remembering that scheme arguments only apply to launches Xcode makes.

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
xcrun simctl launch <device> com.kinlore.app -tab people -screen person
```

| Argument | Build | What it does |
|---|---|---|
| `-api <url>` | any | Points the app at a backend; `-api ""` means none at all. Without the argument a DEBUG build runs on stubs — deliberately, so development does not stop when the Worker is broken — and a Release build uses production. |
| `-local_only YES` | any | The same UserDefaults key the onboarding form's *"Vain minulle, tälle puhelimelle"* writes: the chosen local mode, without filling the form. `LocalModeTests` launches with it beside a dead `-api` address to check the mode promises nothing it cannot deliver. |
| `-rcKey <key>` | any | The RevenueCat Test Store key. Without it purchases and the paywall do not exist, and the app works normally. |
| `-tab memories` / `-tab people` | DEBUG | Opens on that tab instead of Tell. |
| `-screen write` | DEBUG | Opens the typing view directly. |
| `-screen interview` | DEBUG | Runs a canned memory through the stub pipeline and enters the interview loop, finishing the first spoken round by itself — the whole loop, hands-free. |
| `-screen interviewed` | DEBUG | The same loop run to its end: one spoken round finished, the loop left on the result screen. For the test that checks every round's names reach the name check — tapping "Riittää tältä erää" by hand races the speech window. |
| `-comfort <1–5>` | DEBUG | Puts the question ladder at a given level instead of where the answers have taken it. Level 1 offers naming questions, level 5 reflective ones — the whole progression without answering six questions first. See ARCHITECTURE.md §12. |
| `-screen starter` | DEBUG | Opens the Tell screen on a photo nobody has spoken about yet, where the starter questions live. Otherwise that state is reachable only by picking a photo from the library by hand. |
| `-screen person` | DEBUG | Opens the first person's card, relationships and all. |
| `-screen family` | DEBUG | Opens the family view: members, usage, invite link. |
| `-screen settings` | DEBUG | Opens Settings: export, leaving the family, emptying the device. |
| `-screen export` | DEBUG | Opens Settings and runs the export at once, logging where the zip landed. The export is the one output that leaves the app for good, so it is worth opening the real file. |
| `-seed archive` | DEBUG | **Replaces** the archive with a canned one that has something in it: four people, a photograph and memories about them. What the UI tests launch with, and the fastest way to reach a screen that needs content. Called `-seed guess` until 16 Aug 2026, after a feature that has since been cut. |
| `-seed empty` | DEBUG | **Empties** the archive. The empty states are a screen each, and on a device that has ever been used they are otherwise unreachable. |
| `-defer once` | DEBUG | Records a couple of seconds and has the transcription fail as though the month's AI minutes had just run out, leaving the memory waiting for its text. The next launch runs the catch-up and finishes it, so the two together are one filmable sequence. The real trigger is an outage nobody can schedule. See ARCHITECTURE.md §16. |
| `-screen result` | DEBUG | Runs a canned memory through the stub pipeline and **stops** at the result screen, with the name proposals on it. `-screen interview` reaches the same screen and starts talking a second later; `-defer structure` reaches it with no proposals at all. This is the only way to hold still the screen where a misheard name is caught (rule 4), and nothing had ever measured those rows. |
| `-import 3` | DEBUG | Stands in for the system photo picker at the end of an import: it puts three untitled photographs in the archive and hands them to the sheet that asks when they are from. The picker itself cannot be driven from a test run, so the whole bulk path was unreachable without this. See `ImportTests`. |
| `-mic denied` | DEBUG | The microphone is refused without touching the device's own permission. The screen behind a refusal is otherwise reachable only by answering the system prompt with "Älä salli" and then digging the app back out of iOS Settings — so nothing had ever measured it. See ARCHITECTURE.md §8. |
| `-seed family` | DEBUG | A family with **no server behind it**: three members, two invites — one used, one not — and a part-spent free quota. The Perhe screen is drawn entirely from what the Worker sends, so without this every run reaches the offline note instead, and the invite rows are the one part of the app that nothing could ever measure. It does not touch the archive; combine it with no other `-seed`, since they all share the key. |
| `-mic unasked` | DEBUG | The other end of the same state: the microphone has **not been asked about yet**, which is what the Tell screen says its one-off sentence for. Real for exactly one press per install, and gone for good after it — so without this neither a test run nor a screenshot run can ever see that screen. |
| `-family_id demo -api http://127.0.0.1:9` | any build | Not a debug argument but a recipe: a family id in `UserDefaults` and an address with nothing behind it put the app in the state of a phone with no signal. It is the only way to see the "vielä vain tässä puhelimessa" note without going somewhere without coverage, and it is what `SyncVisibilityTests` launches with. |
| `-defer structure` | DEBUG | Transcription works and **every** extraction fails — the one combination that cannot be arranged by hand, because it needs the expensive half of the pipeline to succeed and the cheap half to fail at the same moment. The telling is then kept verbatim rather than lost; see ARCHITECTURE.md §16 and `OrganisingFailureTests`. |
| `-defer silence` | DEBUG | The same recording, but **every** transcription in the run fails the way a recording with nothing said into it fails. The catch-up is meant to count it, move on to the next recording rather than stopping, and stop asking after three — which is only visible across four launches, and only with a failure that never relents. Launch once plainly, then with `-tab memories` so the Tell screen does not record a second one. |
| `-seed arrival` | DEBUG | The joiner's landing, held still: sets the same one-shot flag a real join sets — so the app opens on Muistot with no `-tab` argument — and forces the gallery's waiting state, which otherwise exists only while the first pull is in flight. Empties the archive the way `-seed empty` does. See docs/UX.md §4.3. |
| `-seed alone` | DEBUG | A family of one, with no server behind it: the state where the finished-memory screen's offer slot carries the invitation instead of the paid archive. Empties the archive. See docs/UX.md §3.2. |
| `-invite <code-or-url>` | DEBUG | Feeds the invite-link handler at launch, as though the link had been tapped. A bare code reaches the handler directly; a full `kinlore://join?code=…#…` URL goes through the real parser, fragment and all — which is how the family key riding the fragment is tested rather than bypassed. The only way a test run can reach the wrong-time answers and the parser at once. |
| `-seed unseen` | DEBUG | The demo archive plus an empty seen-baseline, so every telling by the fixture's Mummo is one this phone has not seen: the *"Uutta perheeltä"* section, and the Muistot landing that follows from it. A real one needs a second device to have told something between two visits. |
| `-photos-refused <n>` | DEBUG | Holds still the note about photographs the free ceiling refused — *"…ei mahtunut ilmaiseen arkistoon"*. The real state needs a running Worker and a family over its limit, which is why the refusal went unseen for as long as it did. |

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
