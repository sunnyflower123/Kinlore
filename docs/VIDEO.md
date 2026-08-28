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

Between takes, three rules the dry run paid for:

1. **`terminate` and an immediate `launch` race.** The launch fails silently
   and the screen keeps showing the previous state — five identical
   screenshots taught this. Sleep 2 seconds between them, always.
2. **The stub pipeline takes its time, and the two runners differ**: a
   `-screen result` launch renders its result in ~3 s (typed opening, only
   the 2.2 s extraction sleep), a `-screen interview` launch needs ~10 s
   (it speaks, records and finishes a round), and a live stop-press reaches
   the result ~3.6 s later (1.4 s transcribe + 2.2 s extract). Wait before
   rolling, and cut with margin.
3. **A fresh start is an erase, not an uninstall** — the identity lives in
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

  All four arguments are load-bearing, and the dry run proved it by filming
  their absence: the offer slot only fills when the telling proposed **no
  names** (`-defer structure`) and the rhythm counter is due
  (`-tellings-since-upsell 2` — the threshold is 3, the launch makes it),
  and only an alone family offers the invitation. A plain `-screen result`
  shows proposals and **no card at all**.
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

## Before filming night, in one list

1. Copy the Test Store public key from the RevenueCat dashboard (scene 5).
2. Decide stub or live per scene — the recipes above run either way.
3. `xcrun simctl list devices | grep -c "(Booted)"` — a starved machine
   drops frames the same way it invents test failures (CLAUDE.md).
4. Check the Devpost form's video requirements (length, host) before editing
   to a length; the rules are the form's, not this file's.
