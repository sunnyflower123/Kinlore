# UX — the arrivals, and the day after

Written 17 Aug 2026 from a measured map of every screen; the file:line
references are to that day's code. PLAN.md owns scope and schedule,
ARCHITECTURE.md §8/§21/§22 own the screens and the words. This document owns
what none of them designed: **the arc between the screens** — what a person
meets on their first launch, how that differs by how they arrived, and what
brings them back the day after.

The finding it starts from: **the screens are good and the arc is missing.**
Screen-level guidance exists and is tested — empty states are invitations,
starter questions fill the blank button, the vocabulary is a system (§21), one
blue button per screen (§22), the consent sentence sits on both onboarding
paths. But the app cannot tell its arrivals apart. The founder, the invited
relative and the grandmother handed a phone all land on the same tab with the
same words, and three of the moments that define this product — *the
invitation*, *arriving into a family that already has memories*, and
*returning to something new* — have no designed moment at all.

This matters more than polish would: the Next Gen judges see the demo video
and the repo, and the video is precisely a recording of these arcs.

## 1. Today, measured

Three arrivals exist and they are barely different:

| Arrival | What happens today | Lands on |
|---|---|---|
| Fresh install, no backend address | mode `.local`, **no onboarding of any kind** (`KinloreApp.swift:111-114`) | Kerro tab |
| Fresh install, backend configured | `OnboardingScreen`: a fork with two buttons | create → Kerro tab |
| Invite link or pasted code | `JoinFamilyForm`: name + code + consent | join → **Kerro tab** |

**Changed 13 Sep 2026, for the second row.** After *"Luo arkisto"* on the phone
of whoever set the archive up, `FirstMinuteSheet` now comes up over the Kerro
tab: *"Kenen muistot haluat tallentaa?"*, a name that becomes a confirmed card,
and *"Miten hän kertoo muistonsa?"* — her own phone, which sends an invitation
made out to that name, or this phone, which is the answer for a grandmother
with no smartphone. Looking at the app as a buyer would,
the founder saw the first screen asking the buyer for their own memories when
the archive had been bought for somebody else's. A grandparent's phone (the
text floor) skips it and lands on her button as before. The table above stays
as it was measured.

The findings, each measured on 17 Aug:

1. **A real install shows no onboarding and no family.** `Session.init` reads
   `AppServices.apiBaseURL` first; nil means `.local`, and the URL comes only
   from the `api` UserDefault (`Session.swift:90-114`, `AppServices.swift:14-20`).
   No production address is baked in, so outside a DEBUG launch argument every
   install is silently a single-device archive — onboarding, family, invite,
   sync, usage and the paywall are all unreachable. Every other finding in this
   document sits behind this one.
2. **The one sentence that says what the app is disappears for exactly the
   people who need it.** The onboarding intro — *"Kerätkää yhdessä talteen se
   mitä isovanhemmat muistavat…"* — is dropped entirely at accessibility text
   sizes (`OnboardingScreen.swift:51-55`). What remains is a title and two
   buttons that both assume you already know. *(Stands as an observation; the
   fix this document proposed for it was measured and rejected before it was
   proposed — see §3.1.)*
3. **The joiner lands as if nothing had been shared.** After
   *"Liity perheeseen"* the mode flips and `RootView` opens on the default tab
   — Kerro (`RootView.swift:16-25`) — with starter questions, exactly like a
   founder with an empty archive. The family's memories, the thing that was
   shared, are one tab away and nothing points there. Worse: until the first
   pull completes, Muistot shows *"Ei vielä kuvia. Lisää vanha valokuva…"*
   (`GalleryScreen.swift:144-158`) — a false sentence on a phone that just
   joined a family with photos.
4. **A link tapped at the wrong time does nothing at all.** `invitedCode` is
   read only while `OnboardingScreen` is mounted; in `.local` or `.inFamily`
   the code is parsed, stored and never read (`KinloreApp.swift:96-99`). The
   most likely wrong time is the most human one: the app was opened and looked
   at first, an archive got created by pressing the big blue button, and *then*
   the grandchild's link was tapped. Silence.
5. **Nothing ever suggests inviting.** The invite lives at People → gear →
   Asetukset → *"Perheen jäsenet ja kutsut"* → *"Kutsu perheenjäsen"* — four
   levels deep from any tab (`RootView.swift:142-148`, `SettingsScreen.swift:106-122`,
   `FamilyScreen.swift:107-129`). Meanwhile the upsell card tells a family of
   one *"yksi maksaja avaa sen koko perheelle"* (`TellScreen.swift:1004-1031`)
   — an offer to buy for a family that does not exist yet, on the screen where
   the invitation should be.
6. **A phone joined for a grandparent never gets the large-text floor.**
   *"Kenen puhelin tämä on"* is asked on the create form only
   (`OnboardingScreen.swift:288-397`); `JoinFamilyForm` asks a name and a code
   and nothing else. The floor exists (`elder.largerText`, `Elder.swift:44`)
   but on the handed-over phone it is reachable only through Settings — behind
   the smallest text in the house.
7. **Nothing marks what is new from the family.** No badge, no section, no
   dot; the only sync surface is outgoing (`SyncNote`, *"…vielä vain tässä
   puhelimessa"*, `GalleryScreen.swift:282-312`). PLAN §4.1 already names this
   hole — *"a family archive dies unread more often than unrecorded"* — and
   cutting the guessing round left it open on purpose. **Answered for the
   half it can reach**, 17 Aug 2026 — *"Uutta perheeltä"* and the derived
   default tab, §6 and §9 row P1-1. The half it cannot: a reason to open a
   telling that is old and already read, which is empty by construction here
   (`authorID != me` minus a seen list). See ARCHITECTURE §13.

Two defects found by the same measurement are code fixes rather than design,
and are tracked as their own tasks, not here: the invite **link** drops the
`#`-fragment that carries the family key (`KinloreApp.swift:128-134` reads
query items only, so a link-joiner can never decrypt what a paste-joiner can),
and the 21st photo is accepted locally and then never syncs, with the 402
swallowed by `try?` (`SyncEngine.swift:124`) — a silent ceiling in an app
whose whole ethic is that silent failure is the enemy.

## 2. Roles are derived, never asked

There are no accounts (rule 6) and there will be no role picker. Everything
this document designs is composed from state the app already has:

| Signal | Exists | Says |
|---|---|---|
| `Session.mode` | yes | local archive / needs family / in family |
| `family.members.count` | yes (`session.family`) | alone, or a real family |
| joined via invite vs created | derivable at join time | founder vs invited |
| tellings by others newer than last seen | **new**: `memories.lastSeenSeq`, device-local | something to read |
| `usage.isPaid` | yes | offer or thank |
| *"Kenen puhelin tämä on"* | yes, **both forms** since 17 Aug 2026 | text floor |

And the direct answer to the question this document was commissioned by —
*how does opening-and-buying differ from being-shared-to*: in exactly three
places, all derived.

- **The door.** The founder walks through *"Aloita perheen arkisto"* and a
  form that asks who they are and whose phone it is. The invited walks through
  a link into *"Liity perheeseen"* and gives only a name.
- **The first landing.** The founder lands on Kerro, because an empty archive
  has nothing to read and the first telling is the product. The invited lands
  on **Muistot**, because something was shared and the arrival must show it.
- **The offer slot.** The result screen's one card is the invitation while
  the family is one person, and the paid archive after that. The elder in the
  middle of checking names sees neither — the no-card-beside-proposals rule
  already guarantees it. And the paid archive is never the card on a
  grandparent's phone, where somebody else pays, nor on a phone with no store
  to buy from (`UpsellRhythm.offersPurchase`, 26 Sep 2026).

Everything else is one app. The difference is composed, never configured.

## 3. Arrival 1 — the founder, who opens and buys

The spine exists and is right: fork → *"Uusi arkisto"* (name, whose phone,
keiden kesken, consent above the button) → Kerro with opening starters →
first telling → result with *"Kuulin nämä"* (*"Kuulinko nimet oikein?"* until
12 Sep 2026, when the screen stopped naming the moment and started showing the
sentence each name was heard in — ARCHITECTURE §22) → rhythm-gated offer →
RevenueCat paywall → *"Kiitos — maksu meni läpi"* recovery. Two changes.

### 3.1 The welcome sentence at large text — withdrawn, by an existing measurement

Proposed on 17 Aug and withdrawn the same day, before any code moved: the code
already carries the measurement this needed. `OnboardingScreen.intro`'s
comment records that shortening was tried — one sentence is still four lines
at XXXL, and *"Liity kutsulinkillä"* went below the fold again, the exact
failure that dropping the intro had fixed. The buttons beat the sentence,
deliberately: a first screen whose only two actions have to be found by
scrolling is a first screen this user does not get past.

The withdrawal is recorded rather than deleted, because a proposal that
quietly vanishes gets proposed again by the next person to notice finding 2.
Measure before editing that screen; the measurement is in the comment.

### 3.2 The invite card takes the offer slot for a family of one

On the result screen, in the exact slot the upsell card occupies today, when
`family.members.count == 1` and the family is shared (not `.local`):

- `Label("Perheen arkisto", systemImage: "person.2")`
- *"Tämä arkisto on vielä sinun yksin. Kutsuttu perheenjäsen näkee muistot ja
  voi kertoa omansa."*
- Prominent **"Kutsu perheenjäsen"** — the same words as the same act on
  FamilyScreen (§21: no new word for an old act) → creates the invite and
  opens the same *"Jaa kutsu"* share sheet FamilyScreen uses. Extract that
  flow from `FamilyScreen` so both call one implementation.

Rules, inherited rather than invented: never beside proposals, and on the
same 1-in-3 `UpsellRhythm` counter — the card in the slot alternates by
family size, the rhythm stays one rhythm, and `upsell-rhythm-check.swift`
grows two cases (family of one → invite card, never upsell; family of two →
upsell as today). The upsell card stops being shown to a family of one at
all, which also deletes a sentence that was false there (*"…avaa sen koko
perheelle"*). This is the removal that pays for the card: one slot, one card,
one rhythm — no new surface.

The moment is the right one for the same reason the paywall chose it (§8.6):
the first structured memory is when the value peaks, and the founder's next
thought is *who else should see this*. Four levels of Settings should never
have been the only path to the product's second user.

**Revised 4 Sep 2026: the invitation no longer rides the 1-in-3 rhythm.** On
it, the card was hidden whenever a telling proposed names — which a telling
about relatives does every time — so a founder who told about the family
never met the invitation on the first telling, the second or the third, and
for a family of one that card is the only other holder of the key the whole
archive rests on (founder's-eye review, finding #41). Now a family of one is
shown the invitation on every finished telling, but only once the names on
the screen are answered: *never beside a name* is kept to the letter, by
waiting rather than by hiding. The paid card keeps both rules unchanged.
`UpsellRhythm.slotShows` holds the rule and `upsell-rhythm-check.swift` runs
it.

### 3.3 The purchase arc is already designed — leave it

Rhythm, paywall placement, the family-wide entitlement, the
*"maksu meni läpi"* recovery and the foreground re-sync are all built and
argued in ARCHITECTURE §6/§8.6. This document changes nothing there. What §3.2
adds is the missing *first* beat of §9's model: the payer-who-is-not-the-
beneficiary has to have a family before the model means anything.

## 4. Arrival 2 — the invited, to whom something was shared

### 4.1 A link always gets an answer

The `onOpenURL` handler stops being conditional on the onboarding screen
being mounted. Three cases:

- **`.needsFamily`** — as today: the join form, code pre-filled. While the
  phone is still asking whether it is a member already (§4.5), the code waits
  for the answer, and is used the moment the answer is no.
- **`.inFamily`** — an alert that says what is true:
  *"Tämä laite kuuluu jo perheeseen."* / *"Laite voi kuulua yhteen perheeseen
  kerrallaan. Voit poistua perheestä Asetuksista, ja liittyä sitten
  kutsulla."* / **"Selvä"**. (The server would refuse with `member_exists`
  anyway — `FamilyClient.swift:172-173` — this says it before a request is
  ever made, in the app's own words.)
- **`.inFamily`, but the server has stopped knowing the device**
  (`SyncEngine.State.refused`, since 5 Sep 2026) — the join form as a sheet over
  the archive, code pre-filled, joining the same family again without touching
  anything on the phone (`Session.rejoin`, ARCHITECTURE §20). The alert above
  would send her to *"Poistu perheestä"*, which the same server refuses. A
  phone that has lost the family's key (`.keyMissing`, since 26 Sep 2026) gets
  the same form, and the invitation brings the key back.
- **`.local`** — the same shape: *"Tällä laitteella on jo oma arkisto."* /
  *"Sait kutsun perheeseen. Tämän puhelimen arkisto on erillinen — voit
  tyhjentää laitteen Asetuksista ja liittyä sitten kutsulla."* / **"Selvä"**.
  It does not offer to wipe from inside the alert: *"Tyhjennä tämä laite"*
  keeps its one home, with its export-first dialog around it.

(Fixes finding 4. Three strings and a moved guard; the deliberate
one-family-per-device rule is unchanged, it just stops being enforced by
silence.)

### 4.2 The key travels with the link

Tracked as its own fix (see §1): the parser keeps the fragment, so the code
that arrives by tapping equals the code that arrives by pasting. Nothing else
in this arc works if the joiner cannot read what they joined.

### 4.3 The arrival lands on what was shared

At the moment `join` succeeds, set a one-shot device-local flag; `RootView`
consumes it and opens on **Muistot**. Two states of that first view:

- **While the first pull runs** (store empty, cursor 0, sync in flight):
  a waiting state instead of the false invitation —
  `ProgressView` + *"Haetaan perheen muistoja…"*. It replaces
  *"Ei vielä kuvia"* only in this window; a genuinely empty family archive
  falls through to the existing invitation once the pull has answered.
- **The first pull failed** (store empty, cursor still 0, engine waiting for
  the network): a state of its own since 6 Sep 2026 — *"Perheen muistoja ei
  saatu haettua"*, a sentence that nothing is lost and that it fetches again
  by itself, and *"Hae nyt uudelleen"*. Until then this case fell through to
  the invitation: `waitingForNetwork` is not `syncing`, so a joiner whose
  Wi-Fi dropped under the first pull was told the archive was empty and
  asked to photograph an album — the second archive beside the family's that
  the waiting state above exists to prevent (founder's-eye review, finding
  #63). The engine now retries when the network path comes back
  (ARCHITECTURE §3), and the button is the same round a tap sooner. A family
  that genuinely has nothing answers the pull, and lands on the invitation.
- **Pull done**: the grid and lists as today, newest first — and the newest
  telling with audio is the emotional landing: the row's
  *"Kuuntele omalla äänellä"* is already the strongest control this app has.
  Nothing new to build there; the design is *which screen is in front*.

The way back into telling is already built: open questions and
*"&lt;nimi&gt; kysyy"* cards wait on the Kerro tab, and a person arriving from
a family will meet them on their second tab visit, now with context above
them. (Fixes finding 3.)

**Building this found the arrival had nothing arriving.** Sync ran at launch,
on foregrounding and when the entitlement changed — and at no other moment —
so a fresh joiner's first pull waited for the app to be backgrounded and
opened again. On a phone that is never quit, that is an arrival that stays
empty for hours. `KinloreApp` now starts a sync the moment the mode flips
into a family, which is also what makes the waiting state above a state
rather than a permanent screen.

### 4.4 Sharing itself — what stands, said out loud

The mechanics stay exactly as built and verified (ARCH §4): the share text
carries the link *and* the pasteable code+key, the code expires in 7 days, is
revocable, and a wrong/expired/revoked code is refused in identical words.
The custom-scheme dialog ("Open in Kinlore?", English) remains the known
shortcoming; the paste path remains the mitigation; a universal link waits
for a domain. No change — this section exists so the next reader knows the
sharing model was decided, not forgotten.

### 4.5 The phone that comes back

A member's identity outlives deleting the app and follows the Apple account
to a new phone; the family id does neither (ARCHITECTURE §4, "The identity
survives deleting the app"). Until 26 Sep 2026 such a phone was put in front
of the fork as a stranger, and both of its roads were closed to a member:
*"Aloita perheen arkisto"* ends in the server's `member_exists`, which the
app words as *"Tämä laite kuuluu jo toiseen perheeseen."*, and
*"Liity kutsulinkillä"* needs somebody to notice and send an invitation. For
the grandparent who deleted the app by accident, that was the family gone.

Now the phone asks the server first, and one of three pages answers:

- **While it asks**: a wheel and *"Katsotaan, oletko jo perheen jäsen."*
- **The server knows the phone**: *"Tervetuloa takaisin"*, the family's name
  as its founder typed it, *"Olet tämän perheen jäsen, ja sen muistot
  haetaan tähän puhelimeen."* and one button, **"Avaa perheen arkisto"**,
  which lands on Albumi as a join does (§4.3). The words do not say the app
  was reinstalled: a new phone on the same Apple account arrives on the same
  page, and nothing on it can tell the two apart.
- **The server did not answer**: *"Odotetaan yhteyttä"*, *"Perheen palvelu
  ei vastannut. Sovellus yrittää itse uudelleen, kun yhteys palaa."* and
  **"Yritä uudelleen"**. The fork stays hidden, because silence is not a no:
  a member who took "Aloita" here would meet the refusal above, or with the
  network gone, set up an archive apart from the family. The page asks again
  by itself when the app comes back to the front and when the connection
  returns, and the button is there because a page with nothing to press reads
  as a phone that has stopped.

Only the server's own no — an identity it does not know, or a member who has
left — opens the fork, exactly as before. At accessibility sizes the
returning page drops its sentence and the waiting page keeps only
*"Sovellus yrittää itse uudelleen."*, for the fork's reason (§3.1): measured
at XXXL, the full sentences left the one button below the fold on both.
`ReturningPhoneTests` drives the three answers, and `testReturningPhone` and
`testReturningPhoneUnanswered` audit the two pages at both sizes.

## 5. Arrival 3 — the handover

Two variants, and only one needs work:

- **Founded on the elder's phone.** The grandchild creates the archive on her
  phone, answers *"Kenen puhelin tämä on" → "Isovanhemman"*, hands it over on
  the Kerro tab: a big red button, one caption, two starter questions. That
  screen *is* the handover screen, and building a separate one would add a
  ceremony between her and the button. Already right.
- **Joined on the elder's phone.** The same question is missing from the join
  form (finding 6). Add the identical section — *"Kenen puhelin tämä on"*,
  *"Isovanhemman"* / *"Minun"*, same footer — to `JoinFamilyForm`. One
  section, same strings, same `AppStorage` key; the floor follows the answer
  exactly as on create. No removal owed: this is rule 1 arriving on the one
  phone that needed it most, the §16 precedent ("completing a promise is not
  an addition").

What is deliberately *not* designed: a "hand the phone over now" screen, a
tutorial, or any state the grandchild must remember to set. The cold-handover
test in PLAN §8 measures whether this is enough — *every question she asks
out loud is a sentence missing from a screen* — and phase E is where this
section gets its verdict.

## 6. The day after — returning

Two shapes, one derivation:

- **The teller returns.** Kerro, as today: the big button, and at most two
  question cards chosen by the ladder, a person-asked question pinned first.
  Nothing changes. *Revised 12 Sep 2026:* the cards are a person's questions
  only. The extraction's follow-ups stay beside the telling they came from and
  on their subject's own Tell screen; the front screen never shows what the
  model thought of by itself (ARCHITECTURE §12).
- **The reader returns.** New, and the smallest instrument that answers
  finding 7: **"Uutta perheeltä"** — a section at the top of Muistot listing
  tellings by *other* members this phone has not seen, author and subject on
  the row, tap → the subject's card. Visiting Muistot marks everything seen.
  No red badges, no counts on the tab bar, no notifications — a section that
  exists when there is something and does not when there is not, exactly like
  `SyncNote` facing the other direction.

  **Built 17 Aug 2026**, with one mechanism correction against what this
  section first sketched: seen-ness is a device-local list of telling ids
  (`memories.seen`, `NewFromFamily`), not a `lastSeenSeq` cursor — a `Memory`
  row carries no `seq` on the device, and at hundreds of rows a list is the
  simpler honest instrument. Two consequences fell out of building it: the
  first visit defines the baseline rather than dumping a joiner's whole
  archive into the section (the arrival state frames that case), and
  "by other members" is exactly `authorID != me` with nil excluded, since a
  locally told memory has no author id until the server assigns one.
- **The default tab follows it.** Unseen tellings by others → open on
  Muistot; otherwise → Kerro. The elder whose family has been reading her
  stories opens onto *their* newest telling — which is the reading loop
  finally pointing both ways. Risk, named: if the phase E visit shows the
  flip costs her the button, the flip (one condition) is reverted and the
  section stays.

**Revised 5 Sep 2026:** the flip is gated on whose phone it is. A reader's phone still opens on Muistot when the family has told something; a grandparent's (the text-floor signal from *"kenen puhelin tämä on"*) opens on Kerro every time, and the blind card moves to her Muistot for the same reason (founder's-eye review, findings #75, #76, #81, #83).

**The removal that pays for it:** the map screen. PLAN §10 holds it as an
open decision; this document closes it — **no map in v1**, the coordinates
keep accumulating (ARCH §18), and the §5 row 7 slot the map would have taken
stays empty. An archive that is read is worth more than an archive that is
drawn, and this is the cheaper of the two by an order of magnitude.

**Built after all, 21 Sep 2026 — and this payment is owed again.** The founder
asked for a map to browse the archive by, and `PlacesMapScreen` was built the
same day (ARCH §18); since 25 Sep a map icon in the album's bar opens it in
every album, the empty one included. Nothing was removed beside it, so the
section above is no longer paid for by the map. PLAN §10's map row records the
debt as open — since 25 Sep by the founder's decision that nothing is removed
now — and this paragraph does not settle it.

Push notifications are the honest full answer to reading and are explicitly
**v1.1**: they cost APNs infrastructure, a server that knows when to speak,
and a permission prompt on an elder's phone — three expensive things, one of
them paid in her attention. The section is the v1 instrument.

Two narrower ones exist since 25 Sep 2026 — a question asked of you by name,
and an answer to one you asked (ARCHITECTURE §11) — and the cost paid in her
attention is not among what they pay: authorization is provisional, so no
prompt is ever shown, and they arrive quietly in Notification Center. A
notification for a new telling, which is what this section is about, is still
v1.1.

## 7. The production address — the fork above every arrival

Everything in §3–§6 is unreachable in a real install until the app ships with
a backend address (finding 1). The day the Worker deploys (R2 is the current
blocker, see MEMORY): bake the production URL into `AppServices` as the
default, keep `-api` as the override it already is, and keep `.local` as what
it deliberately is — the *chosen* mode behind *"Vain minulle, tälle
puhelimelle"*, never the accident of a missing default. Minutes of work, and
until it happens every demo of the family half runs on launch arguments.

**Done 24 Aug 2026**, the day the Worker deployed — with one deliberate
narrowing: the default is baked into the **Release** configuration only.
A DEBUG build without `-api` stays on stubs, because every test, demo recipe
and screenshot run launches without an address and must never talk to the
live database by accident (every UI test launch additionally passes `-api`
explicitly — empty, or a dead loopback address, never a real one). A device
build that should sync runs Release or passes `-api`;
SETUP.md carries the recipe. The mode fork itself is unchanged — `.local` is
still only ever chosen.

The choice `.local` now has a cost the review named B4: with a real
backend in the build, the chosen local mode still has no member the server
knows, so transcription could only ever answer 401 — and the app used to
promise *"teksti valmistuu myöhemmin"* over it, forever. Since the same day,
that mode skips the attempt and says the truth in both places the promise
lived (the result screen and the memory row): the text is not coming, the
voice is safe, writing it yourself is right there. A family-less
transcription identity — or on-device ASR — is the v1.1 way to make the
promise true instead of unmade.

Coverage, honestly: `LocalModeTests` pins the sentences and their gating and
would redden if either screen promised again. The skip itself — that no
request leaves — is revert-blind there (a reverted guard fails fast against
the test's dead port into the same screen) and is guarded only by the guard's
own code and this paragraph. The same audit also caught this change's blast
radius the first pass missed: the local-choice consent notice, the Help
screen and the microphone permission text all still said the recording is
sent, and each now tells the mode's truth.

## 8. Deliberately not built

Each of these was considered and refused, so the next session does not
re-litigate them:

- **A welcome carousel / tutorial pages.** The first run *is* the tutorial:
  one fork, one form, one button. Carousels are skipped by the young and
  trap the old.
- **Tooltips and coach marks.** Hostile to VoiceOver, hostile to large text,
  and they explain screens that should instead explain themselves (the
  empty-state-as-invitation rule already does this).
- **Tab-bar badges with numbers.** A number on Muistot is a debt; the
  "Uutta perheeltä" section is an offer. (Also: §21 — no new mechanism where
  a section already carries the act.)
- **A role picker or "elder mode".** Roles are derived (§2). A mode switch is
  a setting a family would have to discover, set, and get wrong.
- **Family rename.** A family is named when it is created and no route
  changes it afterwards — there is no `UPDATE family SET name` anywhere —
  and *"Perhe"* is what `family.ts` falls back to when nobody typed one.
  *Member rename was refused here and shipped on 6 Sep 2026 anyway*
  (`Session.rename` → `PATCH /family/me`, the pencil on the Perhe screen):
  the typo made at join, called its one honest use case here, turned out to
  be the case attribution could not live with.
- **Full-screen photo viewer.** A real gap, still out of scope here.
  *Photo delete was the other half of this bullet and shipped on 4 Sep 2026*
  (52cf270), in the one shape that needs no moderation design to settle
  first: the row appears only while `store.memories(for:)` is empty, so a
  photograph anybody has told about cannot be taken away from them. The
  quota frees its slot server-side either way.

## 9. Order, cost, and what each item pays

Phases per PLAN §3; school evenings. P0 fits before 31 Aug (phase C's tail),
P1 in early phase D beside the paywall craft it neighbours.

| # | Item | §  | Cost | Pays with / owes | State |
|---|---|---|---|---|---|
| P0-1 | ~~Intro survives accessibility sizes~~ | 3.1 | — | — | **Withdrawn** — measured and rejected in `OnboardingScreen.intro` before this document proposed it |
| P0-2 | Invite card in the offer slot, family of one | 3.2 | 1–1½ | replaces the upsell card there; deletes a false sentence | **Built 17 Aug 2026** |
| P0-3 | Link always answered (3 strings, moved guard) | 4.1 | ½ | completion of ARCH §4's known shortcoming | **Built 17 Aug 2026** |
| P0-4 | Joiner lands on Muistot + "Haetaan perheen muistoja…" | 4.3 | 1 | state derivation, no new surface | **Built 17 Aug 2026** — and found the first pull waited for a relaunch; fixed with it |
| P0-5 | *"Kenen puhelin tämä on"* on the join form | 5 | ½ | §16 precedent: rule 1 completion | **Built 17 Aug 2026** |
| P0-6 | Production URL default (deploy day) | 7 | ¼ | config, not feature | **Built 24 Aug** — Release default, DEBUG stays on stubs (§7); R2 had been enabled since 17 Aug |
| P1-1 | "Uutta perheeltä" + derived default tab | 6 | 2 | **the map is formally out of v1** (built anyway 21 Sep 2026, the debt open — §6) | **Built 17 Aug 2026** — the payment is recorded in PLAN §10's map row; mechanism corrected to a seen-id list, see §6 |
| P2 | Own-name row; restore-purchases row outside the paywall | 8 | 1 | only if phases D–E leave room (the 10 Sep rule went with §2.1's closure, 24 Aug) | Not built |

What the built rows shipped with, in the house pattern: two new sweep audits
(`testMemoriesArrival`, which exercises the real landing flag rather than a
`-tab` argument, and `testResultOffersTheFamily`, the first audit ever to
reach a card in the offer slot), a silence test for the answered link
(`SilentFailureTests`), `ConsentOrderTests` unchanged and covering the grown
join form in both directions, three new launch arguments in SETUP.md
(`-seed arrival`, `-seed alone`, `-invite`), and the slot decision in
`upsell-rhythm-check.swift` — five new cases. Test counts moved 47 → 50 and
28 → 30, in ARCHITECTURE §1 and README both, which `verify.sh` counts.

The two independent fixes §1 flagged are done, both 17 Aug 2026: the invite
link keeps its key fragment (the parser reattaches it, and `-invite` with a
full URL drives the real parser in `SilentFailureTests`), and the photo-limit
402 is decoded, counted and said — a `SyncNote`-shaped line on Muistot,
*"…ei mahtunut ilmaiseen arkistoon. … tallessa tässä puhelimessa ja lähtee
perheelle kun tilaa on."* — never a modal, never a red badge, cleared by the
re-sync that going paid now triggers. ARCHITECTURE §4 and §5 carry the full
accounts.

**Every item ships with its tests** in the house pattern: a sweep audit at
both text sizes for each new state (the arrival-waiting state, the invite
card, the alert, the join form's new section, the Uutta section), launch
arguments for the states a test cannot otherwise reach (`-seed arrival`,
`-seed unseen` beside the existing `-seed family`), and any
`ContentUnavailableView` string added to `AccessibilityPolicy`'s list, which
is the coupling working (§21).

Vocabulary delta (§21 discipline — new words only for new acts):

| Act (new) | Word |
|---|---|
| Waiting for the family's memories on arrival | *"Haetaan perheen muistoja…"* |
| Unread tellings from others | *"Uutta perheeltä"* |
| Inviting (existing act) | **reuses** *"Kutsu perheenjäsen"*, *"Jaa kutsu"* |

## 10. What the video shows

The demo video (phase F, never cut) is a recording of exactly this arc, and
the plan above is sequenced so the video can be:

1. The founder's minute — fork, name, whose phone, the big button, ninety
   seconds of rambling, the structured result. (The magic moment, §4 — built.)
2. The invitation — the card on the result screen, the share sheet. (P0-2.)
3. The arrival — a second device taps the link, gives a name, and lands on
   the family's memories; grandmother's voice plays from the row. (P0-3/4.)
4. The return — the first device opens onto *"Uutta perheeltä"* and answers a
   *"&lt;nimi&gt; kysyy"* question aloud. (P1-1, and the interview loop — built.)
5. The paywall, last, where §8.6 put it.

If time collapses, PLAN §5 row 5 still holds: the join flow is the first
thing to *simplify* — a seeded family (`-seed`) can stand in for step 3's
mechanics, and the arrival composition still shows, because it renders from
synced content and not from how the content arrived. The concept is never
cut; the implementation is.

**Pre-production ran 28 Aug 2026**: every scene above is mapped to launch
arguments and dry-run with stubs in [VIDEO.md](VIDEO.md) — recipes, the traps
the dry run found, and the one item to fetch before filming night. Scene 4's
state is pinned by `VideoSceneTests` so it stays filmable.

## 11. Four things standing between her and the family — measured 29 Aug 2026

A second pass over the same arcs, this time reading the code rather than the
plan. §1–§10 designed the *shape* of the arrivals and largely built it; what
follows is four places where the shape was right and the path through it still
demanded something of the wrong person. Each was measured from the source, and
each is now built.

### 11.1 The archive that could be chosen and never unchosen

*"Keiden kesken"* is answered on `CreateFamilyForm`, the first form in the app,
by somebody who does not yet know what the app does. Answering *"Vain minulle,
tälle puhelimelle"* set `local_only`, and the only thing in the app that
unset it was `Session.renewIdentity()` — the second half of *"Tyhjennä tämä
laite"*, which takes every memory on the phone with it.

The price of the wrong answer was not a preference but the product: this mode
attempts no transcription at all (§7's finding B4), so one picker answered out
of habit turns off dictation, structure, family, invitations and the paywall,
permanently, on that device.

**Built:** `EnableSharingScreen`, reached
from a Settings row that exists only where the choice was actually made
(`isLocalByChoice`, which needs the flag *and* a backend address — a build with
no address is local because there is nowhere to sync to, not because anybody
decided so). It is one-way and says so: what has reached the family is on other
people's phones and cannot be recalled from this one.

The archive travels rather than staying behind. Rows told while there was
nowhere to send them were never queued — nothing queues for a server that does
not exist — so `MemoryStore.markAllPending()` puts every row in the outbox
before the mode flips, and the screen says that this is what will happen before
it happens. Media needs no marking: the upload queue is `r2Key == nil`, not the
outbox.

**The residual, named.** `LocalModeTests` pins the row's gating, the sentence
about what travels, and the landing on the onboarding fork. It does **not** pin
`markAllPending()`: nothing on any screen shows an outbox on a device with no
family, so a build that dropped that call would go green and would send an
archive that stayed behind. The call is four `formUnion` lines one line above
the mode flip, and this paragraph is its only other guard.

### 11.2 The paste nobody in this audience can perform

The invite code arrives inside a message and has to cross into a text field.
There was no paste control anywhere in the app, so the only way across was a
long press and a context menu: a fine, timed, two-step gesture — on the screen
an 80-year-old reaches alone, from a link, with nobody beside her, which is the
exact step the whole no-login design exists to make possible.

**Built:** SwiftUI's own `PasteButton` beside the field. The system's control
rather than one of ours, for two reasons: it carries iOS's own Finnish label,
and it is the one paste that raises no clipboard permission alert — which would
have been a second English dialog on the same path as *"Open in Kinlore?"*.

And it reads what was actually copied. Selecting one line out of a message is a
finer gesture than selecting the message, so the message is what a paste button
will usually be handed; the field takes the code out of it with
`KinloreApp.inviteCode(from:)` — the app's own link parser, not a second
reading of the same format, because the last time that string had two readings
the tapped link joined a family it could not decrypt (§4.2).

### 11.3 The name the inviter already knows

The join form asked the joiner for their own name and refused to proceed
without one. The joiner is the grandmother; the person who created the
invitation is the grandchild, who knows exactly who it is for. The keyboard was
on the wrong path, for an answer the app could already have been told.

**Built:** `invite.display_name`. The invite sheet asks *"Kenelle kutsu
menee?"* before making the code, and `joinFamily` uses that name when the
joiner leaves the field empty — `input.displayName || invite.display_name ||
'Perheenjäsen'`. The joiner's own typing still wins, because they are the
authority on their own name.

**What changed from the obvious design, and why.** The first sketch showed the
suggested name on the join form for the joiner to accept or correct. That needs
an unauthenticated lookup of an invite code — and a lookup that answers for a
real code and not for a wrong one is exactly the oracle ARCHITECTURE §4 denies:
a wrong, expired and revoked code must be indistinguishable, or guessing tells
you when you have found a real family. So the name travels but is never handed
back before joining, and the form says *"Voit jättää tyhjäksi, jos kutsun
lähettäjä kirjoitti nimesi valmiiksi"* rather than showing a name it must not
reveal.

The pairing this addition owes: the join form's **required** name field is
gone. One field left the path of the person rule 1 is about, and one field
arrived on the path of the person who was already typing.

### 11.4 The English dialog in the middle of a Finnish path

Tapping the invite link raises iOS's own *"Open in Kinlore?"* — English, in the
middle of the one flow this design exists for. A universal link would remove
it and needs a domain (§4.4 decided that, and it stands). But the invitation
message is our own text, and it can say what the phone is about to ask.

**Built:** one line in `InviteShareButton.inviteText`, before the link —
*"Puhelin voi kysyä englanniksi luvan avata Kinlore — vastaa \"Open\"."* It
says *voi kysyä* rather than naming the exact words, because the exact words
are Apple's and have not been measured here.

**Since 26 Sep 2026 the message is in the sender's language, and says what
joining takes.** It was one `"""` literal, which is a `String` and never a
key, so an English phone sent its invitation in Finnish. Each sentence is now
looked up on its own, and the link and the code stay outside every lookup, so
no translation can move the line the paste field reads the code from. A
sentence ahead of this one says *"Tarvitset iPhonen ja Kinloren."*: somebody
on another phone used to learn it from a link that did nothing. The English
drops *englanniksi*, because to somebody reading English the dialog is not in
another language.

### 11.5 What the audit cost, and what it found

Every item above ships with its tests in the house pattern: `JoinFormTests`
(the paste, the optional name, the code that is still required), two new
`LocalModeTests` (the door, and its absence without a backend), three new sweep
audits (`testSettingsLocalArchive`, `testEnableSharing`, `testInviteNaming`),
four new cases in `invite-boundary-check.mjs`, and `-screen sharing` in
SETUP.md.

Two findings came out of running them, and both are worth keeping:

- **The invite sheet was `.medium` while its content was one share row.** With
  a title, a field, a paragraph and a button in it, the audit reported the
  title, the paragraph and the button as *clipped* and the paragraph as failing
  contrast — which reads like three unrelated styling defects and was one
  squeezed sheet. It is full height now, like `AskQuestionSheet`, which met the
  same wall first.
- **A `Label` in a `List` row that is a `Button` or a `NavigationLink` exposes
  its title as a static text element of its own**, 60 pt tall inside the tap
  target, and the audit reports that element as clipped and as not scaling with
  Dynamic Type. Twenty-one runs across every shape — both containers, its own
  section and a shared one, with and without header and footer, high on the
  screen and low, four different labels including one width-matched to a row
  that passes, and the same symbol that row carries — and only a plain `Text`
  passes. It is not the new row's defect: swapping it with *"Näin tämä
  toimii"* moved the identical finding onto that row, which has passed every
  audit it has ever been in. The older rows are left where they are, green
  where they stand; the new one is a `Text` and pays for it with its icon.
