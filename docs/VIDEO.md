# The demo video — shot list and dry run

Phase F (PLAN §3, 25–28 Sep) films the five scenes docs/UX.md §10 defines.
This document exists so that filming night is filming and not debugging: the
filmable stub fragment of every scene was dry-run on 28 Aug 2026 on a private
simulator, with the stub pipeline and no deploy — the parts only a live
server can film (scene 2's share sheet, scene 5's purchase) are named as
such below rather than claimed. The traps the dry run found are written next
to the recipes that avoid them, and `VideoSceneTests` keeps the one
otherwise-unpinned scene state red-green from here to filming night.

Two paths exist per scene, and the choice is phase F's to make scene by scene:

- **Stub** (verified here): no network, no credits, the canned pipeline. The
  stub transcriber **rotates**: the first recording of a launch shows
  `samples[0]` (the Puumala text), the second `samples[1]`, the third
  `samples[2]` — deliberately, so consecutive recordings differ — and a
  terminate-and-relaunch resets the count. So on camera, **speak the sample
  the round will show**: the Puumala text for a fresh launch's first telling,
  the next sample for the next round. That is the honest stub trick — the
  samples exist as test transcripts, and the voice on the recording really
  said the words on screen — and it works per round, not per evening. (The
  `-screen` runners seed their *opening* from a typed draft instead:
  `-screen result` types `samples[0]`, `-screen interview` types
  `samples[2]`, and no speech needs to match a typed opening.)
- **Live**: production is deployed (`https://memorize.arkiste.workers.dev`)
  and a Release build points there by default. Real transcription spends real
  credits and shows what was really said — and it is the only path where the
  share sheet, the join and a cross-device voice playback are real. The best
  material for scenes 1 and 3 may well come from the phase E visit.

## Filming setup, once

```bash
# A simulator of your own — the shared one belongs to everybody (CLAUDE.md).
SIM=$(xcrun simctl create kinlore-filming \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5) && xcrun simctl boot "$SIM"

# Install a Debug build (stubs by default; -api overrides when going live).
xcrun simctl install "$SIM" <path-to>/Kinlore.app

# The pro touches, both verified 28 Aug 2026:
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryLevel 100
xcrun simctl privacy "$SIM" grant microphone com.kinlore.app  # no Allow popup on camera

# Record. Ctrl-C stops it; h264 .mov, plays everywhere.
xcrun simctl io "$SIM" recordVideo --codec h264 scene.mov
```

**The hand is a UI test.** A launch argument puts the app in a state; it
cannot press anything, and the submission has to show the app *working*. The
simulator panel that would do the pressing needs `sudo xcode-select` and there
is no sudo on this machine, so `ios/KinloreUITests/FilmDriver.swift` does it:
eight scenes that tap through the loop, the invitation, a person, the return,
a place — and, for the v16 cut, the blind card, the paywall and a proposal row
alone — walking slowly enough to be read. It runs only on a simulator whose
name contains "film", so an ordinary test run pays nothing for it, and it
passes neither `-testLanguage fi` nor `-testRegion FI` — filming is the one
case that wants the device's own English.

```bash
xcrun simctl io "$SIM" recordVideo --codec h264 take.mov &
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Kinlore.xcodeproj -scheme Kinlore -sdk iphonesimulator \
  -destination "id=$SIM" \
  -only-testing:KinloreUITests/FilmDriver/testFilmTheTelling test
kill -INT %1
```

One scene per invocation: two in one recording puts the springboard, and the
runner's own install, in the middle of the take.

Between takes, four rules the dry run paid for:

1. **`terminate` and an immediate `launch` race.** The launch fails silently
   and the screen keeps showing the previous state — five identical
   screenshots taught this. Sleep 2 seconds between them, always.
2. **The stub pipeline takes its time, and the two runners differ**: a
   `-screen result` launch renders its result in ~3 s (typed opening, only
   the 2.2 s extraction sleep), a `-screen interview` launch needs ~10 s
   (it speaks, records and finishes a round), and a live stop-press reaches
   the result ~3.6 s later (1.4 s transcribe + 2.2 s extract). Wait before
   rolling, and cut with margin.
3. **The 9:41 status bar invents accessibility findings.** Measured 9 Sep
   2026: with `simctl status_bar override` applied, `testFamily` and
   `testMemoriesWithContent` failed 3/3 on plain black headings that measure
   18.7:1 — impossible — and both pass on a device without it, same commit.
   The override is wanted for filming and must be **cleared before auditing**
   (`xcrun simctl status_bar "$SIM" clear`). Anybody who runs the sweep on the
   filming device is chasing ghosts.
4. **A fresh start is an erase, not an uninstall** — the identity lives in
   the simulator's keychain. `xcrun simctl shutdown "$SIM" && xcrun simctl
   erase "$SIM"`, boot, reinstall, re-apply the status bar and mic grant.

## The scenes

### 1 · The founder's minute

Fork → name → whose phone → the big button → the telling → the result.

- **Fork and forms** (verified: renders): fresh app state, launch with
  `-api http://127.0.0.1:9`. The address — any address — is what makes
  onboarding render at all; what sits behind it is then the **real** pipeline
  pointed at a port that refuses, not stubs. So the create button would fail
  against it: **cut before the button lands** and resume in stub mode.
- **The telling** (verified): `-seed empty`, no `-api`. Tap the big button,
  speak `samples[0]` (the Puumala text) for the scene's length, stop.
- **The result** (verified: screenshot with title *"Sijoitin sen kohteeseen
  Puumalassa, 1950-luku"* and three proposal rows): arrives ~3.6 s after
  stop — the stub waits on purpose. For a still to frame against,
  `-seed empty -screen result` (ready ~3 s after launch).
- Live path: one unbroken take against production — the form creates a real
  family and the result shows the words that were really said.

### 2 · The invitation

The card on the result screen, then the share sheet.

- **The card** (verified: *"Perheen arkisto — Tämä arkisto on vielä vain
  sinun…"* with the blue *"Kutsu perheenjäsen"*):

  ```
  -seed alone -defer structure -screen interview -tellings-since-upsell 2
  ```

  Three of the four are load-bearing and the fourth is inert, which filming
  their absence could not tell apart: the offer slot only fills when the
  telling proposed **no names** (`-defer structure`), and only an alone
  family offers the invitation (`-seed alone`). `-tellings-since-upsell 2`
  sets a counter the invitation never reads — `slotShows` answers
  `case .invite: !proposalsRemaining` and takes the rhythm only for the paid
  archive card — so it changes nothing in this shot. Harmless to leave in
  the line; just not proof of anything. A plain `-screen result` shows
  proposals and **no card at all**.
- **The share sheet is live-path only.** Creating an invite asks the Worker;
  in the stub state the tap answers honestly with *"Kutsua ei voitu luoda"* —
  the same shared button and nil-client path `SilentFailureTests` pins from
  the Family screen (the offer card's own tap is pinned by nothing; the sweep
  only settles on it). Film the tap-through against `wrangler dev` or
  production, where the sheet carries the real `koodi#avain` text.

### 3 · The arrival

The second device taps the link, gives a name, lands on the family's memories.

- **The waiting** (verified: spinner over *"Haetaan perheen muistoja…"*):
  `-seed arrival`. Holds still indefinitely — no server ever answers.
- **The landing** (verified: *"Uutta perheeltä"* with four *"Mummo kertoi"*
  rows): `-seed unseen`. Opens on Muistot by itself, no `-tab` argument.
- **The voice from the row is not in the fixture.** The seed's audio key
  points at nothing on purpose (it pins the failing-download path), so
  playback from seeded rows does not play. Two honest ways to film it: play
  the telling recorded in scene 1's stub take — **within scene 1's own
  launch, or after a relaunch with no `-seed` at all**, because every later
  `-seed` launch replaces the archive and orphans that row (the m4a survives
  on disk; nothing points at it any more) — or go live and play what the
  other device really told.
- Live path: PLAN §5 row 5 named the seeded stand-in in advance; a real join
  against production is one invite text away if the evening allows.

### 4 · The return

The first device opens onto *"Uutta perheeltä"* and answers a question aloud.

- **The scene's opening is pinned by `VideoSceneTests`** (and dry-run):
  `-seed unseen` opens on Muistot with the section, and the Kerro tab then
  offers the question — two labels, *"Mummo kysyy"* over *"Kuka souti veneen
  saareen sinä aamuna?"* — a fixture question that exists for this scene
  (MemoryStore, unseen branch, added 28 Aug 2026 when the dry run found no
  seed carried one). Tap it, answer aloud, and the interview loop carries the
  scene from there on the stub pipeline — that half is the ordinary loop
  other tests cover, not something this scene's test taps through.

### 5 · The paywall, last

- **The offer card** (verified: the *"Ilmainen arkisto"* label over the
  sentence about ~3 minutes of telling left and room for 8 photos —
  `-seed family`'s part-spent quota is where the numbers come from):

  ```
  -seed family -defer structure -screen interview -tellings-since-upsell 2
  ```

  Same mechanics as scene 2.
- **The paywall and the purchase need `-rcKey <Test Store key>`** — and
  without the key there is no tap to frame: the card stays informational and
  draws **no button at all**. With the key it grows the blue *"Avaa koko
  arkisto"*, so the paywall take's card is not the same still the dry run
  screenshotted. The key is the *public* Test Store API key (RevenueCat
  dashboard → the project's API keys; safe to embed, SETUP.md). This is the
  **one item to fetch before filming night**, and the purchase then completes
  against the Test Store.

### What the Test Store does on its own, which can ruin the take

Two things about scene 5 that are not in the app and cannot be seen by looking
at it. Both were read out of RevenueCat's own documentation on 1 Sep 2026,
because everything else about this scene had been checked against the code and
these are facts about somebody else's service.

**A test subscription expires by itself, quickly.** Renewals are accelerated —
a one-week product renews about every five minutes, a one-year product hourly
— and **after five renewals it cancels and the entitlement goes inactive.** A
one-week product is therefore about twenty-five minutes from purchase to dead.

With the webhook wired, the Worker then does exactly what it is supposed to:
EXPIRATION arrives, `family.entitlement` returns to `free`, and the card the
camera is pointed at says *"Ilmainen"*. Nothing is broken —
`webhook-revocation-check.mjs` pins that behaviour deliberately. **So buy on
filming night and shoot scene 5 immediately.** Do not buy hours ahead to "have
it ready".

**Test Store purchases are reported as sandbox data.** The webhook
configuration in the RevenueCat dashboard (Integrations → Webhooks) has an
environment scope, and one scoped to production only receives nothing at all
from the Test Store. Nothing reports this: the purchase succeeds, the app says
thank you, and `family.entitlement` simply never changes. The Authorization
header field has a matching trap — `isAuthorizedWebhook` compares the whole
header against `RC_WEBHOOK_SECRET` by length and then byte for byte, so a
field typed as `Bearer <secret>` against a secret of `<secret>` is refused
silently.

## The v16 takes

The v16 cut (the video project's `SCRIPT-v16.md`, shot list in `SHOOT-v16.md`)
films five things for real and draws the rest, and three of the five need a
state no seed above provides. `-seed film` is `-seed blind` with the film's
people and the film's words: a proposal heard in the telling about the one
photograph, three confirmed people who were not — exactly three, because the
blind card takes its decoys from them in store order — Toivo confirmed and
named, Puumala at `.town`. `-seed film-untold` is the same archive a minute
earlier, the photograph not yet spoken about, for filming the telling into.
The photograph comes from `Documents/film-photo.jpg` in the app's container
when the shooting day has put one there:

```bash
cp <the film's photograph> \
  "$(xcrun simctl get_app_container "$SIM" com.kinlore.app data)/Documents/film-photo.jpg"
```

- **The telling** — `testFilmTheTelling`, `-seed film-untold -sample film
  -tab tell`. The stub writes down the film's own sentence
  (`StubTranscriptionService.film`) and returns the extraction the pipeline
  gave it (`StubExtractionService.filmResult`) — the heuristics cannot read
  that sentence, and a take has to show what the app really made of the
  words on its soundtrack. The listening runs 8.5 s, longer than her clip.
- **The blind card** — `testFilmTheBlindCard`, `-seed film -tab tell`. Taps
  the name the app proposed — given by somebody who knows the photograph,
  without being shown it — and the take ends on the app's own sentence,
  *"Thank you. Now we know who this is."*
- **The family tree** — `testFilmTheTree`, `-seed film-tree -tab people
  -screen tree`. The film fixture with Helmi confirmed, a card for Grandma
  and no relation yet: the hand adds two on camera, on the tree — Helmi's
  sheet, "Add a spouse", Toivo; then "Add a child", Grandma — because
  relationships are only ever added by a person and the film has to show
  the mechanism. The tree draws confirmed people and confirmed relations
  only; `-seed film` draws nothing. A family member's phone state: the tree
  is not offered on a grandparent's phone or with VoiceOver on.
- **The paywall** — `testFilmThePaywall`, scene 5's arguments. The key
  cannot travel through the runner, so it goes into the app's defaults once:
  `xcrun simctl spawn "$SIM" defaults write com.kinlore.app rcKey <key>`.
  The purchase button is RevenueCat's and is matched by the usual words;
  the first keyed run is the check.
- **The name waiting, alone** — `testFilmTheRowAlone`, `-seed film -tab
  people`. The hand opens the people list's one quiet row and holds on
  *"Names heard"*: the proposal with the sentence it was heard in, its two
  answers, and no offer near it. A separate launch from the paywall on
  purpose: the offer needs a result with no proposals, so the two never share
  a screen. The take of 12 Sep 2026 shows the row on the list itself, which
  the list stopped holding that evening; it has to be shot again.

The telling names Helmi and Toivo, the stub hears both, and Helmi is the
proposal the card asks about — since 13 Sep 2026; before that the proposal
was a misheard *Elli* and the take ended on the question left open, which
the film then had to explain as something other than a quiz.

## Before filming night, in one list

1. Copy the Test Store public key from the RevenueCat dashboard (scene 5).
   Sidebar → *Apps and providers* → **Test configuration**, or Project
   Settings → **API keys**; the project is `proj087f04ef`, already in
   `wrangler.jsonc`. It is the **public** key — the three Worker secrets
   (`OPENROUTER_API_KEY`, `RC_SECRET_KEY`, `RC_WEBHOOK_SECRET`) were already
   set in production, checked with `wrangler secret list` on 1 Sep 2026.
2. Check the webhook's environment scope includes **sandbox**, and that its
   Authorization header is byte-identical to `RC_WEBHOOK_SECRET` — see above.
3. `-rcKey` is a launch argument and lives in NSArgumentDomain, which is
   volatile: **launched from the icon the key is gone** and the paywall
   disappears with it. Every recipe here launches with arguments; stay on
   them.
4. Decide stub or live per scene — the recipes above run either way.
5. `xcrun simctl list devices | grep -c "(Booted)"` — a starved machine
   drops frames the same way it invents test failures (CLAUDE.md).
6. The Devpost rules, read 5 Sep 2026 from
   `revenuecat-shipaton-2026.devpost.com/rules`: the video *"should be less
   than two (2) minutes. Judges are not required to watch beyond two
   minutes"*, must be public on **YouTube or Vimeo**, must show *"the Project
   functioning on the device for which it was built"*, and may carry no
   third-party trademarks or copyrighted music. RevenueCat's own pitching
   post still says three minutes; it is older than the rules, and the rules
   are what the form enforces. Re-read the page before the final cut — it is
   somebody else's document and can change.
