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
| `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` | Optional: the two notifications of ARCHITECTURE §11. Without them the Worker logs *"not sent: no key"* and nothing else changes. See *Apple push* below — they cannot be had on a free account. |

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
baked into `AppServices` on deploy day, 24 Aug 2026 — docs/UX.md §7).

**To test with your own voice, run the `Kinlore Production` scheme.** It
builds the Release configuration, which has the production address compiled
in, and it exists because the stub is convincing: on 12 Sep 2026 a telling
about a photograph came back as the sample about Puumala, and nothing on the
screen said the words were not the teller's. The console does say so
(`[kinlore] backend: not configured — using stubs`), but nobody reads the
console on a phone. Pick the scheme in Xcode's scheme menu and run; the
transcription and the structure are then the real ones, and they cost
OpenRouter credit.

Until 13 Sep 2026 it was the Debug build with `-api` among its arguments, and
this section said that an install without Xcode gets Release. The app Xcode
installs is not that install. **Scheme arguments apply only to launches Xcode
makes**: open the same app from the phone's home screen and it is a Debug
build with no address — on stubs again, and with no onboarding either, since
the onboarding fork exists only where there is a backend. The phone tested with
this scheme held all three stub samples on 13 Sep, and its People tab listed the
people named in them as family. A Release build has nothing to forget.

`-rcKey` does **not** belong among this scheme's arguments. A Test Store key is
the only kind this project has, and RevenueCat's SDK refuses one in a build
without `DEBUG`: it shows an alert and then stops the app with `fatalError`
(`checkForSimulatedStoreAPIKeyInRelease` in purchases-ios's
`Configuration.swift`). The paywall and the purchase belong to the `Kinlore`
scheme, which is Debug — `-rcKey` there, and `-api` beside it for a backend.

### Health check

```bash
curl -s http://localhost:8787/health
```

Returns `{"ok":true,"hasKey":true}` when the key is in place. If `hasKey` is
`false`, extraction answers `502 upstream_failed`, and the Worker's log records
the status, 401, and nothing more. No upstream body reaches either the app or
the log, because it can contain account details or echo back the memory the
user just told.

### iOS app — public

| Key | Note |
|-----|------|
| RevenueCat **Test Store API key** | Designed for the client side, and still not in the repository: in a public clone it would hand the paid tier on the production Worker to anybody. Supplied with the launch argument `-rcKey <key>` so Test Store and production can be swapped without recompiling — **in a Debug build only**, because a Release build stops on a Test Store key by RevenueCat's design (the `Kinlore Production` paragraph above). Without a key, purchases are unavailable but the app works normally. |

### iOS app — signing for a real device

A simulator build needs nothing here; a build for a phone needs a development
team, and until 19 Sep 2026 the only place to put one was Xcode's Signing &
Capabilities tab. That is a setting inside the `.xcodeproj`, which is generated
and ignored by git, so `xcodegen generate` replaced it — and that command runs
after every added source file and several times a day when more than one
session is working. Xcode then asked for the team again before the next device
build, which reads as Xcode forgetting and is the project file being rewritten.

`ios/Signing.xcconfig` is tracked, carries no team of its own and optionally
includes `ios/Signing.local.xcconfig`, which is in `.gitignore` because the
Apple account behind the identifier was taken out of HEAD on 10 Sep 2026.
`#include?` is the optional form: a clone or a CI checkout without the local
file generates and builds exactly as before, with no team and no error, which
is what every simulator build and the whole of `verify.sh` rely on. Write the
local file once, from the certificate already in your keychain:

```bash
security find-identity -v -p codesigning \
  | sed -n 's/.*(\([A-Z0-9]\{10\}\))"$/\1/p' | head -1 \
  | sed 's/^/DEVELOPMENT_TEAM = /' > ios/Signing.local.xcconfig
```

Measured the same day, in a worktree pinned to a commit so that nothing else in
the tree could explain it: without the file, `xcodebuild -sdk iphoneos` fails
with *"Signing for \"Kinlore\" requires a development team"*; with it, that
error is gone and the build gets as far as provisioning, where the command line
refuses to create a profile unless it is passed `-allowProvisioningUpdates`.
Xcode's own build does that step itself, which is why the app installs from the
IDE and the same command does not.

### Apple push — the one thing a free account cannot do

The two notifications in ARCHITECTURE §11 need an APNs key, and Apple issues
one only to the paid Developer Program: a personal team cannot add the Push
Notifications capability at all. Nothing depends on it. Without it the app's
registration fails and is logged, the Worker logs *"not sent: no key"*, and
every question is still on the card and in the Kerro tab.

With the program, four steps, and each is the account holder's to take:

1. Certificates, Identifiers & Profiles → Identifiers → `com.kinlore.app` →
   **Push Notifications** on.
2. Keys → a new key with **Apple Push Notifications service (APNs)**. The
   `.p8` downloads once and Apple does not issue it again; note its Key ID
   and the Team ID. `*.p8` is in `.gitignore`, and the file goes into the
   Worker and nowhere else:

   ```bash
   cd backend
   npx wrangler secret put APNS_KEY_P8 < AuthKey_XXXXXXXXXX.p8
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID
   ```

3. The production database gets the `push_token` table: the two statements
   beside it in `schema.sql` are the migration.
4. The app gets `aps-environment` in its entitlements, and a signed device
   build (CLAUDE.md, Commands) has to pass before it is committed — a build
   asking for an entitlement its App ID does not have fails to sign, which is
   why it is not in the repository before step 1.

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
| `-rcKey <key>` | DEBUG | The RevenueCat Test Store key. Without it purchases and the paywall do not exist, and the app works normally. The app reads it in any build, but in Release a Test Store key stops the app at launch — RevenueCat's own guard, not this app's (the `Kinlore Production` paragraph under *Backend — as Worker secrets*). |
| `-tab memories` / `-tab people` | DEBUG | Opens on that tab instead of Tell. |
| `-screen write` | DEBUG | Opens the typing view directly. |
| `-screen interview` | DEBUG | Runs a canned memory through the stub pipeline and enters the interview loop, finishing the first spoken round by itself — the whole loop, hands-free. |
| `-screen interviewed` | DEBUG | The same loop run to its end: one spoken round finished, the loop left on the result screen. For the test that checks every round's names reach the name check — tapping "Riittää tältä erää" by hand races the speech window. |
| `-comfort <1–5>` | DEBUG | Puts the question ladder at a given level instead of where the answers have taken it. Level 1 offers naming questions, level 5 reflective ones — the whole progression without answering six questions first. See ARCHITECTURE.md §12. |
| `-screen starter` | DEBUG | Opens the Tell screen on a photo nobody has spoken about yet, where the starter questions live. Otherwise that state is reachable only by picking a photo from the library by hand. |
| `-screen person` | DEBUG | Opens the first person's card, relationships and all. |
| `-person <card id>` | DEBUG | With `-screen person`: that card instead of the first person's. `-seed clan -screen person -person clan-elina` is the card with parents, a husband, children and a friend on it. |
| `-first_minute_pending YES` | any | The same UserDefaults key a real *"Luo arkisto"* sets: the sheet that asks whose memories the archive is for, and then how they will tell: on their own phone, which sends an invitation made out to them, or on this phone. A real create needs a server, so combine it with `-seed alone`, a family of one without one. Not shown with `-elder.largerText YES`, which is a grandparent's phone. |
| `-screen tree` | DEBUG | Opens Ihmiset on the drawn family tree, titled *Sukupuu*, whichever of its two views the phone was left on, and holds it there for the launch, so the list switch does nothing. The tree exists on a family member's phone only (since 13 Sep 2026). Combine with `-seed related`, the fixture with a confirmed couple in it, or the tree has nobody to draw. |
| `-people list` / `-people tree` | DEBUG | Which of its two views the third tab opens on, on a family member's phone, held for the launch — and so, since 19 Sep 2026, which word the tab itself carries: *Sukupuu* over the tree, *Ihmiset* over the list. Without it the phone decides: the tree until somebody taps *Luettelo*, and whichever was chosen last after that. The UI tests' launch helper passes `list` unless a test names `-people` itself, so the tests written about the list still test the list. |
| `-you <card id>` | DEBUG | A demo family whose "you" is linked to that card, as `PATCH /family/me` links it for real, so the tree shows *Sinä* under it with no server behind the app. Combine with a store seed that holds the card: `-seed related -you demo-eeva`. |
| `-screen family` | DEBUG | Opens the family view: members, usage, invite link. |
| `-screen settings` | DEBUG | Opens Settings: export, leaving the family, emptying the device. |
| `-screen camera` | DEBUG | Opens the camera over Albumi. It sits behind a menu row, and a screenshot run has no hands. |
| `-camera stub` | DEBUG | Draws the capture controls over an empty preview. The simulator has no camera, so this is the only way to reach the ready state on the device every audit runs on. |
| `-camera denied` | DEBUG | The refused camera, without answering a system prompt with "Älä salli" and digging the app back out of iOS Settings. Same hole as `-mic denied`. |
| `-camera unavailable` | DEBUG | The no-camera screen. Forcing it is only needed on hardware that has one — a simulator reaches it by itself, which is what `SilentFailureTests` uses. |
| `-screen sharing` | DEBUG | Opens Settings and pushes the screen behind *"Ota perhe käyttöön"* — the one-way door out of a single-device archive. Combine with `-local_only YES` and an `-api` address, since the row exists only where the archive was *chosen* local. |
| `-screen export` | DEBUG | Opens Settings and runs the export at once, logging where the zip landed. The export is the one output that leaves the app for good, so it is worth opening the real file. |
| `-seed archive` | DEBUG | **Replaces** the archive with a canned one that has something in it: four people, a photograph and memories about them. What the UI tests launch with, and the fastest way to reach a screen that needs content. Called `-seed guess` until 16 Aug 2026, after a feature that has since been cut. |
| `-seed empty` | DEBUG | **Empties** the archive. The empty states are a screen each, and on a device that has ever been used they are otherwise unreachable. |
| `-store outdated` / `-store unreadable` / `-store unknownKind` / `-store synced` | DEBUG | **Replaces the archive file on disk before it is read**, with what rule 10 (CLAUDE.md) is tested against: one written before the newer fields existed, one that is not JSON at all, one holding a relationship of a kind this version has never heard of beside two people it can read, and an empty one whose pulls have reached 412. The first three drive `SilentFailureTests`' three rule-10 tests; the last is the cursor check's, below. |
| `-sync.kindsKnown <r/s>` | any | The same UserDefaults key the app writes at every launch: which kinds the last build to run here could read, relationship kinds over subject kinds — `4/4` since `friend_of` arrived on 21 Sep 2026. A value that differs from this build's `MemoryStore.kindsKnown` — and a missing one — makes the launch forget the pull cursor once, so a kind the previous build dropped from every pull is fetched again (ARCHITECTURE.md §3). `-store synced -family_id demo -api http://127.0.0.1:9 -sync.kindsKnown 3/4` shows it on Albumi as a first pull that failed. |
| `-defer once` | DEBUG | Records a couple of seconds and has the transcription fail as though the month's AI minutes had just run out, leaving the memory waiting for its text. The next launch runs the catch-up and finishes it, so the two together are one filmable sequence. The real trigger is an outage nobody can schedule. See ARCHITECTURE.md §16. |
| `-screen result` | DEBUG | Runs a canned memory through the stub pipeline and **stops** at the result screen, with the name proposals on it. `-screen interview` reaches the same screen and starts talking a second later; `-defer structure` reaches it with no proposals at all. This is the only way to hold still the screen where a misheard name is caught (rule 4), and nothing had ever measured those rows. |
| `-import 3` | DEBUG | Stands in for the system photo picker at the end of an import: it puts three untitled photographs in the archive and hands them to the sheet that asks when they are from. The picker itself cannot be driven from a test run, so the whole bulk path was unreachable without this. See `ImportTests`. |
| `-mic denied` | DEBUG | The microphone is refused without touching the device's own permission. The screen behind a refusal is otherwise reachable only by answering the system prompt with "Älä salli" and then digging the app back out of iOS Settings — so nothing had ever measured it. See ARCHITECTURE.md §8. |
| `-seed family` | DEBUG | A family with **no server behind it**: three members, two open invitations — one made out to a name, one not — and a part-spent free quota. The Perhe screen is drawn entirely from what the Worker sends, so without this every run reaches the offline note instead, and the invite rows are the one part of the app that nothing could ever measure. It does not touch the archive; combine it with no other `-seed`, since they all share the key. |
| `-mic unasked` | DEBUG | The other end of the same state: the microphone has **not been asked about yet**, which is what the Tell screen says its one-off sentence for. Real for exactly one press per install, and gone for good after it — so without this neither a test run nor a screenshot run can ever see that screen. |
| `-family_id demo -api http://127.0.0.1:9` | any build | Not a debug argument but a recipe: a family id in `UserDefaults` and an address with nothing behind it put the app in the state of a phone with no signal. It is the only way to see the "vielä vain tässä puhelimessa" note without going somewhere without coverage, and it is what `SyncVisibilityTests` launches with. |
| `-defer structure` | DEBUG | Transcription works and **every** extraction fails — the one combination that cannot be arranged by hand, because it needs the expensive half of the pipeline to succeed and the cheap half to fail at the same moment. The telling is then kept verbatim rather than lost; see ARCHITECTURE.md §16 and `OrganisingFailureTests`. |
| `-defer silence` | DEBUG | The same recording, but **every** transcription in the run fails the way a recording with nothing said into it fails. The catch-up is meant to count it, move on to the next recording rather than stopping, and stop asking after three — which is only visible across four launches, and only with a failure that never relents. Launch once plainly, then with `-tab memories` so the Tell screen does not record a second one. |
| `-seed arrival` | DEBUG | The joiner's landing, held still: sets the same one-shot flag a real join sets — so the app opens on Albumi with no `-tab` argument — and forces the gallery's waiting state, which otherwise exists only while the first pull is in flight. Empties the archive the way `-seed empty` does. See docs/UX.md §4.3. |
| `-seed alone` | DEBUG | A family of one, with no server behind it: the state where the finished-memory screen's offer slot carries the invitation instead of the paid archive. Empties the archive. See docs/UX.md §3.2. |
| `-seed aimed` | DEBUG | The demo archive with two questions asked by name on its photograph — one of this phone's member, one of Aino — and the demo family beside them for the ask sheet's *"Kenelle?"* to choose from. The Kerro tab offers the first and says nothing of the second; the card shows both. See `TargetedQuestionTests` and ARCHITECTURE §11. |
| `-invite <code-or-url>` | DEBUG | Feeds the invite-link handler at launch, as though the link had been tapped. A bare code reaches the handler directly; a full `kinlore://join?code=…#…` URL goes through the real parser, fragment and all — which is how the family key riding the fragment is tested rather than bypassed. The only way a test run can reach the wrong-time answers and the parser at once. |
| `-seed deck` | DEBUG | The archive plus one photograph nobody has spoken about, which is what the Kerro tab's card is drawn from. The plain archive has none on purpose — a card on the idle screen would change what every other test is looking at. |
| `-seed blind` | DEBUG | The archive with a **file on its photograph**, which is what the blind confirmation is drawn from: the fixture already had an unconfirmed person whose name was heard in a telling about `demo-photo`, and the only thing missing was a face to put in front of somebody. The picture is also the guard — `BlindConfirmation` builds no card without one, because *"kuka tässä on?"* over a grey placeholder asks nothing — which is why the plain archive is untouched by the feature. |
| `-seed faces` | DEBUG | The archive with the same file on its photograph and a **face already chosen from it** on Kalle's card (ARCHITECTURE §25): his disc on the people list, his card and the tree is cut from the picture rather than drawn as his initial, and Eeva's card is where a test chooses one. The spot is the top of the dark shape the generated photograph carries, which is the nearest thing it has to a head. |
| `-seed unseen` | DEBUG | The demo archive plus an empty seen-baseline, so every telling by the fixture's Mummo is one this phone has not seen: the *"Uutta perheeltä"* section, and the Albumi landing that follows from it. A real one needs a second device to have told something between two visits. Also the one seed carrying an open question from another member (*"Mummo kysyy"*) — the demo video's return scene answers it aloud; see docs/VIDEO.md. |
| `-photos-refused <n>` | DEBUG | Holds still the note about photographs the free ceiling refused — *"…ei mahtunut ilmaiseen arkistoon"*. The real state needs a running Worker and a family over its limit, which is why the refusal went unseen for as long as it did. |
| `-tellings-since-upsell <n>` | any | Presets the offer-slot rhythm counter (`UpsellRhythm`; the threshold is 3, and the finished telling adds one before comparing) — so `2` makes the next proposal-free telling carry the offer card. The demo video's scenes 2 and 5 lean on it (docs/VIDEO.md); it rode the UserDefaults key unnamed in this table until the video dry-run's audit noticed. |

These exist because some screens sit behind a tap, and two things that need to
reach them have no hands: a screenshot run, and **filming the demo video**
(PLAN.md §3, phase F). They also make the accessibility sweep possible at all —
checking a screen at the largest text size means being able to open it.

Debug arguments are Finnish-free on purpose; they are a developer interface, so
they follow the repo's language rule rather than the app's. See CLAUDE.md.

### Cloudflare

No manual key. `npx wrangler login` handles it via OAuth.
`CLOUDFLARE_API_TOKEN` is only needed if CI is ever set up.

When something on this account has gone wrong — a schema run against the wrong
database, a deleted bucket, a lost login — read [RECOVERY.md](RECOVERY.md)
before typing anything.

## What is NOT needed

- **Apple: nothing beyond Xcode, except for push.** No Sign in with Apple and
  no certificate — the app builds, runs and is tested on a free account. The
  two notifications are the one thing that needs the paid program (above), and
  nothing else waits on them.
- **Google / Firebase:** nothing.
- **Email service:** nothing, because authentication is device based.
- **OneSignal:** not needed. The Worker speaks to APNs itself (`apns.ts`).

## Authentication without a login screen

Sign in with Apple, push, iCloud and App Groups **would** all be technically
possible here. Authentication is still done without them — not because of a
constraint, but because it is better for this audience:

1. On first launch a UUID is generated and stored in the Keychain with the
   `kSecAttrSynchronizable` flag. iCloud Keychain syncs it between the user's
   devices — this does not require an iCloud entitlement, so it works on a free
   account.
2. That UUID **is** the member id — the client mints it and sends it in the body
   of `POST /family` or `POST /family/join`, and the Worker only ever reads
   `body.memberID`. Nothing server-side issues an id. (Corrected 9 Sep 2026;
   this used to say the backend issued one.) The Worker's half is the *secret*:
   the device generates 32 random bytes, the server stores only their SHA-256 in
   `member.secret_hash`, and every request afterwards is
   `Bearer <member_id>.<secret>`.
3. You join a family with an invite link. No email, no password, no login screen.

**An 80-year-old never hits a login wall** — she gets a link from a grandchild
and she is in. That is precisely the point where this audience normally drops out.

**What that flag also carries, said plainly since 9 Sep 2026.** `Keychain.query(_:)`
builds one query shape for all three entries — `member_id`, `device_secret` and
`family_key` — and every one is `kSecAttrSynchronizable`. So the secret that
authenticates *and the key that decrypts* travel to every device signed into the
same Apple ID. This section, and ARCHITECTURE §4's "The identity survives
deleting the app", both presented that as resilience only. It is also a second
way in: whoever holds the Apple account holds the archive, with no invitation.
That is the right trade for an audience who will lose a phone before they lose
an Apple ID, and it should be a known trade rather than a surprise.

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
