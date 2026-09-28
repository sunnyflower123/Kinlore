<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/title-plate-dark.svg">
    <img src="docs/logo/title-plate.svg" alt="Kinlore" width="420">
  </picture>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-Apache_2.0-5B4A3E?labelColor=241A14" alt="Apache 2.0 licence"></a>
</p>

A family's shared memory archive. Anyone in the family tells what they
remember, out loud or in writing, and the AI gives it structure: memories
attach to photos and people, the family tree grows out of the stories, and open
questions come back to be asked.

Album and genealogy apps ask for structured input: a form to fill in, a face to
tag, a date to pick. A family's memory is not kept that way. It is told, a
little at a time and by different people, and whatever nobody wrote down goes
when they do. Kinlore keeps the telling and does the sorting itself.

Everyone tells into the same archive from their own phone, and the app is built
for the oldest teller as much as for the youngest. My own grandparent tested
it, which is why the rules further down read as constraints rather than good
intentions, and why the failure that matters here is not a crash but a story
that never got told.

I built it for the [RevenueCat Shipaton 2026](https://revenuecat-shipaton-2026.devpost.com/)
hackathon, in the Next Gen Award (the student category).

<p align="center">
  <img src="docs/media/demo.gif" alt="The app at work — Putting the memory in order, finding the people, the places and the time — then Memory saved, a Move to another card button, the date 1950s, and the question Who told this memory? with the answers Me, Someone else and I would rather not be named." width="320">
</p>

<p align="center"><sub>Simulator, stub pipeline: the waiting is real and the model call is canned.<br><code>scripts/readme-shots.sh</code> makes this GIF and the pictures below.</sub></p>

| <img src="docs/media/mounted/01-tell.png" alt="The Tell screen: the heading Tell what you remember, the line Talk at your own pace, freely, a large red microphone button with Press and start talking under it, and a Write instead link." width="1179"> | <img src="docs/media/mounted/02-result.png" alt="The result screen: Memory saved, a Move to another card button, the date 1950s, the card Who told this memory? with the answers Me, Someone else and I would rather not be named, and below it the beginning of the spoken text kept as it was said — in Finnish, because the sample telling is." width="1179"> | <img src="docs/media/mounted/03-who-is-this.png" alt="The blind card: a drawn stand-in photograph, the question Who is this?, four names in identical black buttons — Sanni, Aino, Eeva and Kalle — and I do not remember below them." width="1179"> |
|---|---|---|
| **Telling.** One button, and a way out of it for anyone who would rather type. | **What comes back.** The date is a decade because that is what was said, and no name enters the family tree before somebody confirms it. | **Who is this?** One of the four names is the proposal, and nothing on the screen says which. |

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/divider-dark.svg">
    <img src="docs/logo/divider.svg" alt="" width="320">
  </picture>
</p>

## What it does

- You press one big button and talk about an old photo for 90 seconds. The
  memory is kept in your own voice and in readable words, attached to the photo.
- The names and places it heard come back as proposals, each with the sentence
  it was heard in. None of them enters the family tree until a person says yes
  (rule 4).
- It asks follow-up questions out loud, listens to each answer and asks the
  next one, round after round, without a tap.
- Later it shows the photograph a name was heard in and asks *Who is this?*
  over three or four of the family's names, with the proposal unmarked among
  them. Any other answer confirms nothing and is never called wrong
  ([ARCHITECTURE §23](docs/ARCHITECTURE.md#the-blind-confirmation-built-30-aug-2026)).
- The original recording and the raw transcript are kept forever (rule 3). A
  date stays as vague as it was said, so "sometime in the fifties" is stored as
  a decade (rule 5).
- The app shows English by default and Finnish on a phone set to Finnish. The
  speech pipeline follows whoever is speaking.

Every screen has to work at the largest text size and with VoiceOver (rule 1).
The app has 338 UI tests, including 109 accessibility sweeps that audit a screen
at the default text size and again at the largest.

## Who pays

One member pays, and the whole family gets the archive. Whoever tells is not
necessarily whoever pays, so RevenueCat grants the entitlement to the buyer and
the backend maps it to a right for the whole family (`family.entitlement`).
Purchases run on the RevenueCat Test Store, since there is no App Store release.

The free tier limits three things, counted on the server: ten minutes of
transcription a month, twenty photographs in all and five colourisations a
month. Telling is never paywalled (rule 2). A recording over the limit is kept,
and its transcription waits.

The paywall is RevenueCatUI's own view, designed and priced remotely in
RevenueCat's dashboard, and
[`PaywallSheet.swift`](ios/Kinlore/Screens/PaywallSheet.swift) presents it. It
shows up in three places. The result screen offers it after one telling in
three, never when that telling proposed names somebody has to confirm and never
on a grandparent's phone. A limit the family has hit gets the offer beside it on
every phone, a grandparent's included. And the family screen has an *Open the
whole archive* button. `UpsellRhythm.swift` holds these rules.

[`RevenueCatPurchases.swift`](ios/Kinlore/Services/RevenueCatPurchases.swift)
configures the SDK with the family member's id as the app user id, so the
webhook can find the family without the app being open. On the server,
[`backend/src/entitlement.ts`](backend/src/entitlement.ts) does not take the
phone's word for a purchase: `POST /entitlement/sync` asks RevenueCat's REST API
what the customer owns, and the webhook takes the paid tier away only on an
expiry, a transfer or a refund. A unique index in `backend/schema.sql` keeps one
purchase to one family. Each piece has a check that needs no key and no network,
and `./scripts/verify.sh` runs them all.

A clone has no paywall, because the paywall needs a RevenueCat key and none is
in the repository. A Test Store key in a public repo would hand the paid tier on
the production Worker, and its model bill, to anybody.
[DETAILS.md](docs/DETAILS.md#who-pays) has the full section, including how to
see the paywall with a key of your own.

## Where to look

- [The ten rules that do not bend](CLAUDE.md#rules-that-do-not-bend), which the
  rule numbers on this page refer to. `CLAUDE.md` is the working agreement for
  the AI coding sessions that did most of the typing.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md):
  [§1](docs/ARCHITECTURE.md#1-where-things-stand) for what is built and what is
  not, [§6](docs/ARCHITECTURE.md#6-money) for the money.
- The RevenueCat code:
  [`RevenueCatPurchases.swift`](ios/Kinlore/Services/RevenueCatPurchases.swift),
  [`PaywallSheet.swift`](ios/Kinlore/Screens/PaywallSheet.swift) and
  [`backend/src/entitlement.ts`](backend/src/entitlement.ts).
- [`scripts/verify.sh`](scripts/verify.sh). Run `./scripts/verify.sh` from the
  repository root: it runs every check here that costs nothing and says what it
  skipped. CI runs the same script.
- [`docs/PLAN.md` §8](docs/PLAN.md#risk-2-honestly), on why the concept
  survives a speech recogniser that gets one Finnish proper noun in three wrong.
- [`docs/DETAILS.md`](docs/DETAILS.md), the long version of this page: what was
  measured, what I got wrong, what the server can read, and the full setup.

## Run it in about two minutes

You need Xcode 26 or later (it is built here with Xcode 27.0 and tested on an
iOS 26.5 simulator) and XcodeGen (`brew install xcodegen`). You do not need a
paid developer account, certificates or any keys.

```bash
git clone https://github.com/sunnyflower123/Kinlore.git
cd Kinlore/ios && xcodegen generate && open Kinlore.xcodeproj
```

Pick an iPhone simulator and press Run. The `Kinlore` scheme builds Debug, and a
simulator build needs no signing team. The app runs fully on stubs: record or
type a memory, watch it come back structured, and look through the people it
proposed.

The stubs cannot listen. A recording comes back as one of three canned Finnish
samples in turn, whatever you said (`StubTranscriptionService`), and only a
Worker hears your own words. The backend, the keys and the command-line test
runs are in [DETAILS.md](docs/DETAILS.md#setting-it-up) and
[SETUP.md](docs/SETUP.md).

## Licence

[Apache 2.0](LICENSE).
