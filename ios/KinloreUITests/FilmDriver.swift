import UIKit
import XCTest

/// The hand that taps while the camera is rolling.
///
/// docs/VIDEO.md maps every scene of the demo video to launch arguments, which
/// puts the app in the right state; what a launch argument cannot do is press
/// anything. A video of the app *working* needs a finger, and on this machine
/// there is no other one: the native simulator panel needs
/// `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and there
/// is no sudo here (CLAUDE.md). XCUITest talks to the same accessibility tree
/// VoiceOver reads, and it is the only thing in this repository that can tap.
///
/// **This is a camera, not a check.** It asserts only that a screen arrived —
/// which is worth failing on, because a screen that never arrives is also a
/// wasted take — and otherwise it walks slowly on purpose. `beat()` is the
/// pause a viewer needs to read a card; a test would not have one and a film
/// cannot do without it. Nothing here pins behaviour: the suites beside it do
/// that, and if a scene stops being filmable it is `VideoSceneTests` that
/// should redden, not this.
///
/// **It runs only on a simulator named for filming** — the name has to
/// contain "film" — so `xcodebuild test` on anybody else's device stays the
/// suite it was rather than spending two minutes walking slowly through four
/// screens. The obvious gate, an environment variable, does not work here and
/// the failure is silent: `TEST_RUNNER_KINLORE_FILM=1` never reaches the
/// runner under this scheme (measured 9 Sep 2026 — the runner's environment
/// holds `TESTMANAGERD_SIM_SOCK` and nothing else of ours), and the run then
/// reports success with every scene skipped. The device's own name crosses
/// that boundary because the runner is an app on the device. It is still
/// honoured if the variable does arrive, for whoever wires a test plan later.
/// Measured the other way on 27 Sep 2026: under `xcodebuild
/// test-without-building`, `TEST_RUNNER_KINLORE_CUE_DIR` does arrive, and
/// the live takes below depend on it: all four cues of that day's keyless
/// dry run came back through it. `test` itself was not measured again, so
/// the name stays the gate.
///
///     # A simulator of your own — never one you did not create (CLAUDE.md).
///     SIM=$(xcrun simctl create kinlore-filming \
///       com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
///       com.apple.CoreSimulator.SimRuntime.iOS-26-5)
///     xcrun simctl boot "$SIM"
///     xcrun simctl status_bar "$SIM" override --time "9:41" --batteryLevel 100
///     xcrun simctl privacy "$SIM" grant microphone com.kinlore.app
///
///     xcrun simctl io "$SIM" recordVideo --codec h264 take.mov &
///     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
///       xcodebuild -project ios/Kinlore.xcodeproj -scheme Kinlore \
///       -sdk iphonesimulator -destination "id=$SIM" \
///       -only-testing:KinloreUITests/FilmDriver/testFilmTheTelling test
///     kill -INT %1
///
/// One scene per invocation. Two in one recording would put the springboard,
/// and the runner's own install, in the middle of the take.
///
/// **The phone's language, not Finnish — and the command above is missing a
/// flag on purpose.** CLAUDE.md tells you to run the suite with
/// `-testLanguage fi -testRegion FI`, because its queries are written against
/// the Finnish keys and would otherwise fail on tests that are not broken.
/// Filming is the one case that inverts: the video is shot in English, which
/// is what `developmentLanguage: en` in project.yml is for, so a filming run
/// passes neither flag and lets the device's own language through. Do not add
/// them here to make this look like the other command.
///
/// Where a label has no English translation yet, the query lists both
/// spellings rather than pinning the defect: measured 9 Sep 2026, the
/// recording button's own accessibility label was still "Aloita kertominen" on
/// an English phone, which is what VoiceOver reads aloud to somebody who does
/// not speak Finnish.
final class FilmDriver: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - The scenes (docs/UX.md §10, docs/VIDEO.md)

    /// 1 · The telling: the photograph's card and its question, the big
    /// button, her telling, the app's first question back to her, and what
    /// the app made of it — ending on one name confirmed by a person and the
    /// other left open, which is rule 4 happening on camera.
    ///
    /// The question arrives by itself since 26 Sep 2026: a spoken telling goes
    /// straight on to it (`InterviewLoopTests`). `-voice stub` keeps it on the
    /// screen and silent for as long as the take holds it — the film lays the
    /// question's voice over the picture, as it does hers — and "That is
    /// enough for now" is what then lands on the names.
    ///
    /// `-seed film-untold` is the film's archive a minute before she speaks,
    /// so the Kerro tab offers the photograph; `-sample film` makes the stub
    /// write down the film's own telling — the words her voice says on the
    /// soundtrack — and return the extraction the pipeline gave them. The
    /// listening runs longer than her clip (7.5 s): the film lays the voice
    /// over the take, and the take must not stop first. The 10 Sep cut's
    /// version of this scene ran on `-seed empty` and the rotating samples.
    func testFilmTheTelling() throws {
        let app = try roll(["-seed", "film-untold", "-sample", "film", "-tab", "tell", "-voice", "stub"])
        beat(2.2) // the picture and its question are read before anybody presses anything
        try tap(app.buttons, ["Aloita kertominen", "Start telling"])
        // The first press on a fresh simulator raises iOS's microphone prompt
        // and nothing else, and the stop button then "never arrives" 25 s
        // later, which reads like a broken screen. Measured 12 Sep 2026 on a
        // watcher that forgot the grant. Say what it is instead.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 1.5) {
            XCTFail("the microphone prompt is up — grant it before rolling: xcrun simctl privacy <sim> grant microphone com.kinlore.app (docs/VIDEO.md)")
            return
        }
        beat(7.0) // she talks, and the line fills with her voice: 8.5 s with the check above
        try tap(app.buttons, ["Lopeta kertominen", "Stop telling"])
        // The stub waits on purpose: ~1.4 s transcribing, 2.2 s extracting.
        let enough = try find(app.buttons, ["That is enough for now", "Riittää tältä erää"], timeout: 40)
        beat(3.2) // the app asks back, by itself: long enough to be read and heard
        enough.tap()
        _ = try find(app.staticTexts, ["Memory saved", "Muisto tallennettu"], timeout: 15)
        beat(3.4) // the transcript in her own words, and two names in amber
        let confirm = try reveal(app, app.buttons, ["Confirm Toivo", "Vahvista Toivo"])
        confirm.tap()
        beat(8.0) // Toivo confirmed, Helmi still open: held, because the film holds it
    }

    /// 2 · The invitation: the offer slot on the result screen, and the
    /// question it asks before it makes anything.
    ///
    /// All four arguments are load-bearing (VIDEO.md §2): the slot fills only
    /// when the telling proposed no names, the rhythm counter is due, and the
    /// family is one person. The take stops at the name, because the code
    /// itself is the Worker's to make — in stub the next tap answers "Kutsua
    /// ei voitu luoda", honestly and on camera, which is not the shot.
    func testFilmTheInvitation() throws {
        let app = try roll([
            "-seed", "alone",
            "-defer", "structure",
            "-screen", "interview",
            "-tellings-since-upsell", "2",
        ])
        _ = try find(app.staticTexts, ["Memory saved", "Muisto tallennettu"], timeout: 60)
        beat(2.4)
        let invite = try reveal(app, app.buttons, ["Invite a family member", "Kutsu perheenjäsen"])
        invite.tap()
        beat(1.8)
        let field = try find(app.textFields, ["Nimi", "Name"], timeout: 20)
        field.tap()
        beat(0.6)
        field.typeText("Sanni")
        beat(2.6)
    }

    /// 3 · The family: the people the archive knows, and the one it only
    /// thinks it knows. The orange row is rule 4's weaker instrument — a
    /// proposal, waiting for a human — and it is the one thing on this screen
    /// that says the app does not decide who anybody is.
    func testFilmTheFamily() throws {
        // `-people list`: Ihmiset opens on the tree since 13 Sep 2026, and
        // this take was shot on the list.
        let app = try roll(["-seed", "archive", "-tab", "people", "-people", "list"])
        beat(2.6)
        let person = try reveal(app, app.buttons, ["Eeva", "Kalle", "Sanni"])
        person.tap()
        beat(3.4)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        beat(1.6)
    }

    /// 4 · The return: the phone opens on what somebody else told while it was
    /// away, and the Tell tab is holding their question.
    ///
    /// `VideoSceneTests` pins this state; this only walks through it.
    func testFilmTheReturn() throws {
        let app = try roll(["-seed", "unseen"])
        _ = try find(app.staticTexts, ["New from the family", "Uutta perheeltä"], timeout: 30)
        beat(2.8)
        let row = try reveal(app, app.buttons, ["Eeva", "Kalle", "Photograph", "Valokuva"])
        row.tap()
        beat(3.6)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        beat(1.4)
        try tap(app.tabBars.buttons, ["Tell", "Kerro"])
        beat(4.0) // the question waits to be answered aloud
    }

    /// 5 · The place: a name somebody said out loud, and where the gazetteer
    /// put it.
    ///
    /// The fixture's Puumala carries a coordinate at `.town` precision, so
    /// what this films is the circle and not a pin — which is the case worth
    /// filming, because it is rule 5 drawn rather than argued. Held for the
    /// six seconds the v16 cut keeps the card on screen.
    ///
    /// Under the map the card used to say that nobody had told anything yet,
    /// ten seconds after the film showed the telling that named Puumala. The
    /// card reads *"Mainittu yhdessä muistossa"* since 19 Sep 2026 and lists
    /// it: the telling is filed under the photograph
    /// (`TellViewModel.placeSubject`) and *mentions* the place, and the screen
    /// asked only the first of those two questions (`RootView`; the video
    /// project's SCRIPT-v21.md §1.5). Nothing about the seed changed — the
    /// take was waiting on the app.
    func testFilmThePlace() throws {
        let app = try roll(["-seed", "film", "-tab", "memories"])
        beat(1.6)
        let place = try reveal(app, app.buttons, ["Puumala"])
        place.tap()
        beat(7.0)
    }

    /// 5b · The album a week later, scrolled past the bottom of the screen.
    ///
    /// `-seed film-week` is the film's archive with thirty tellings in it, and
    /// quantity is the only thing it adds: six prints with their counts on
    /// them, sixteen moments under the days they were told, three places. The
    /// narration over this is one line — *"A week later there are thirty. She
    /// had more to say than anyone asked."* — and the picture has to carry the
    /// number, because nothing on the screen says it.
    ///
    /// Slow drags rather than flicks. A flick's deceleration belongs to the
    /// phone and lands wherever it lands; three slow drags with a beat between
    /// them are three readable screens, which is what a viewer gets in three
    /// and a half seconds.
    func testFilmTheAlbum() throws {
        let app = try roll(["-seed", "film-week", "-tab", "memories"])
        beat(2.4) // the grid, and the counts on the prints, before anything moves
        for _ in 0 ..< 3 {
            app.swipeUp(velocity: .slow)
            beat(1.2)
        }
        beat(2.4)
    }

    /// 5c · Not only her: one photograph, three tellings, three names.
    ///
    /// The album's *"Uutta perheeltä"* section on the grandchild's phone after
    /// the invitation, where `-seed film-family` leaves exactly three tellings
    /// unseen — the grandmother's, her daughter's and her nephew's, all three
    /// about the same picture. `byline(for:)` draws the name under each, which
    /// is the entire scene: the archive stops being one person's.
    ///
    /// It is the truthful version of a bigger idea that is not built. One phone
    /// round a table, several voices in a room, is an open question in PLAN §8
    /// with no screen behind it, and a film cannot show it (SCRIPT-v21.md
    /// §2.10). This is what is true today and filmable today.
    func testFilmTheTellers() throws {
        let app = try roll(["-seed", "film-family", "-tab", "memories"])
        _ = try find(app.staticTexts, ["New from the family", "Uutta perheeltä"], timeout: 30)
        beat(8.0) // three rows, three names, read one after another
    }

    // MARK: - The v16 takes (SHOOT-v16.md in the video project)

    /// The name the film seed proposes on the photograph the grandmother told
    /// about, mirrored from `-seed film` in MemoryStore. Scene 8 still needs
    /// it — the one quiet row on the people list is hers — and the blind card
    /// no longer does; see `filmOtherProposal` below.
    private static let filmProposal = "Helmi"

    /// And the name on the OTHER print, proposed by Uncle Jussi's telling in
    /// `-seed film-family`. The blind card's take taps this one.
    private static let filmOtherProposal = "Kerttu"

    /// 6 · The blind card: the photograph a name was heard in, four names with
    /// the app's guess unmarked among them, and the name a person who knows
    /// the picture gives. What the take has to show is what the app then
    /// says — its one sentence, and the name a fact.
    ///
    /// **`-seed film-family` and not `-seed film` since 19 Sep 2026, and the
    /// photograph is a different one.** On the film seed the card asked about
    /// the picture the audience had just heard the grandmother tell about, so
    /// the cut had to spend ten seconds explaining why the app was asking
    /// something it had been told — a conflict the film made, not the app (the
    /// video project's SCRIPT-v21.md §2.9). Here the question is about a print
    /// from the same table that nobody in the film has named, the telling that
    /// proposed the name is Uncle Jussi's, and the grandchild recognising her
    /// is the whole scene without a word of argument.
    func testFilmTheBlindCard() throws {
        let app = try roll(["-seed", "film-family", "-tab", "tell"])
        _ = try find(app.staticTexts, ["Who is this?", "Kuka tässä on?"], timeout: 30)
        beat(6.5) // the picture, the question and the four names, read before anything is chosen
        try tap(app.buttons, [Self.filmOtherProposal])
        _ = try find(
            app.staticTexts,
            ["Thank you. Now we know who this is.", "Kiitos. Nyt tiedämme, kuka hän on."],
            timeout: 20
        )
        beat(7.0) // the sentence is the last image of the scene
    }

    /// 6b · The family tree, on a family member's phone, after the blind
    /// confirmation — and how a name gets into it, on camera. `-seed
    /// film-tree` is the film fixture with Helmi confirmed, a card for Grandma
    /// and no relation yet; the hand adds the two the way the app adds them:
    /// Helmi's sheet on the tree, "Add a spouse", Toivo — the couple line is
    /// there as the sheet goes down — then "Add a child", Grandma, and the
    /// drop from Helmi's disc. Six taps. Relationships are only ever added by
    /// a person (extraction proposes none), so this is the whole mechanism.
    func testFilmTheTree() throws {
        let app = try roll(["-seed", "film-tree", "-tab", "people", "-screen", "tree"])
        // The drawing itself: the tree has carried no title since 19 Sep 2026.
        _ = try find(app.buttons, ["Helmi"], timeout: 30)
        beat(2.0) // nobody related yet: six people side by side, read first
        try tap(app.buttons, ["Helmi"])
        beat(0.35)
        try tap(app.buttons, ["Add a spouse", "Lisää puoliso"])
        beat(0.35)
        try tapLast(app, "Toivo") // the picker's row, not his disc behind the sheet
        beat(1.2) // the couple, and the line between them
        try tap(app.buttons, ["Helmi"])
        beat(0.35)
        try tap(app.buttons, ["Add a child", "Lisää lapsi"])
        beat(0.35)
        try tapLast(app, "Grandma")
        beat(8.0) // the drop to Grandma: held while the film grows the tree out of the phone
    }

    /// The last button with exactly this label: the picker's row rather than
    /// the tree's disc behind it, which carries the same name — a plain tap
    /// on the name fails as "multiple matching elements" (13 Sep 2026).
    private func tapLast(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 20) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let all = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            // The disc behind the sheet is covered and not hittable; the row is.
            if let row = all.last(where: { $0.isHittable }) {
                row.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        throw NeverArrived(labels: [label])
    }

    /// 7 · The paywall: the offer on a result that proposed no names, the real
    /// RevenueCat paywall with its price, the Test Store purchase, and the
    /// app's thank-you. The card rises only with a key, and the runner cannot
    /// pass one (VIDEO.md §5), so put the public Test Store key in the app's
    /// own defaults before rolling:
    ///
    ///     xcrun simctl spawn "$SIM" defaults write com.kinlore.app rcKey <key>
    ///
    /// Without it there is no card at all and this fails on the first `find`,
    /// which is the right outcome for a take that would have shown nothing.
    ///
    /// The purchase button belongs to RevenueCat's template, so its label is
    /// whatever the dashboard says that day. Measured on the first keyed run,
    /// 13 Sep 2026: "Open the whole archive", one yearly package at 50 USD.
    func testFilmThePaywall() throws {
        let app = try roll([
            "-seed", "family",
            "-defer", "structure",
            "-screen", "interview",
            // The canned memory this screen holds for ten seconds, in the
            // language the film is shot in. Without it `-screen interview`
            // draws `samples[2]`, which is Finnish, and the paywall beat —
            // the one a monetisation judge reads hardest — carries a
            // paragraph nobody in the audience can read (25 Sep 2026).
            "-sample", "film",
            "-tellings-since-upsell", "2",
        ])
        _ = try find(app.staticTexts, ["Memory saved", "Muisto tallennettu"], timeout: 60)
        beat(2.4)
        let open = try reveal(app, app.buttons, ["Open the whole archive", "Avaa koko arkisto"])
        open.tap()
        beat(2.6) // the paywall, and its price, read before anything is bought
        // The dashboard's button says "Open the whole archive" (13 Sep 2026)
        // — the same words as the offer card's button under the sheet, so
        // the tap goes to the last hittable one, which is the paywall's.
        try tapLast(app, "Open the whole archive", timeout: 30)
        // The Test Store answers with its own dialog — "Test Store Purchase",
        // the product's id, title and price, and three buttons. The film cuts
        // it out; the take has to get past it.
        beat(0.8)
        try tap(app.buttons, ["Test valid purchase"], timeout: 30)
        // Nothing left to tap. The sheet closes itself once the family has
        // the archive (`PaywallSheet.spreadToFamily`), and behind it is the
        // same result screen with the offer card gone — that absence is the
        // shot. Until 24 Sep 2026 this take waited for the opposite: the
        // alert saying the payment went through and the archive had not
        // opened, which is what the stubbed world answered when it had no
        // server to ask. An isolated judge read it as the only outcome the
        // film shows of buying anything (REVIEW-v21h.md §5.1).
        //
        // Waited for rather than assumed: a purchase that does not reach the
        // archive leaves the card exactly where it was, and a take of that is
        // a take of the bug.
        let offerEN = app.staticTexts["The free archive"]
        let offerFI = app.staticTexts["Ilmainen arkisto"]
        let deadline = Date().addingTimeInterval(40)
        while offerEN.exists || offerFI.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(
            offerEN.exists || offerFI.exists,
            "the offer card is still on the result screen — the purchase did not open the archive"
        )
        beat(1.6) // the sheet closes on the answer
        // The same place on the same screen, where the offer card stood two
        // taps ago. An absence is only legible against where the thing was.
        app.swipeUp(velocity: .slow)
        beat(4.0) // the result screen, with nothing left on it to buy
    }

    /// 8 · The name still waiting, alone: behind the people list's one quiet
    /// row, on "Names heard", with the sentence it was heard in and its two
    /// answers — and no offer anywhere near it. This is the rule
    /// `UpsellRhythm` keeps — never against a name — filmed as the absence it
    /// is. A separate launch from scene 7 on purpose: the offer needs a result
    /// with no proposals, so the two cannot share a screen, which is the point.
    ///
    /// Until 12 Sep 2026 the name stood on the people list itself, as an
    /// orange "A proposal — confirm this person" row, and the take of that day
    /// shows it there. The list holds confirmed people only now, so the hand
    /// opens the door first. The take has to be shot again.
    func testFilmTheRowAlone() throws {
        // `-people list`, as in the family take: shot on the list, under
        // which the door sits.
        let app = try roll(["-seed", "film", "-tab", "people", "-people", "list"])
        beat(1.6) // the family, and the one quiet row under it
        try tap(app.buttons, ["1 name waiting to be checked", "1 nimi odottaa tarkistusta"])
        _ = try reveal(app, app.buttons, [Self.filmProposal])
        beat(8.0)
    }

    /// 4b · The colours come back, and a person decides whether they stay.
    ///
    /// ARCHITECTURE §24. The photograph's card offers *"Colour it by the
    /// telling"* once somebody has told something about it — `colourable`,
    /// which is why this runs on `-seed film` and not `film-untold`. What
    /// comes back is a proposal and nothing else: `ColourLock` keeps the
    /// photograph's own lightness and takes only the hue from the reply, and
    /// `ColourSheet` asks *"Does it look like this?"* before a single byte is
    /// saved. The take ends on somebody answering it, because rule 4 —
    /// the AI proposes, a human confirms — is the scene rather than the
    /// colours.
    ///
    /// `-api ""` puts `StubColourisationService` behind the button, so the
    /// take needs no key, no network and no credit. What the stub returns is
    /// the film's own captured reply when the shooting day has put one in
    /// `Documents/film-coloured.jpg`, and its warm tint otherwise — the same
    /// arrangement as `filmPhotoFile()`, and for the same reason: a take has
    /// to show what the app really made of what is on its soundtrack.
    func testFilmTheColouring() throws {
        let app = try roll(["-seed", "film", "-tab", "memories"])
        beat(1.6) // the album, and the photograph in it
        try reveal(app, app.buttons, ["Photograph", "Valokuva"]).tap()
        beat(2.6) // the card: the picture, the decade, what was told about it
        try reveal(app, app.buttons, ["Colour it by the telling", "Väritä kerronnan mukaan"]).tap()
        beat(1.0) // "Colouring by the telling…"
        _ = try find(app.staticTexts, ["Does it look like this?", "Näyttääkö tältä?"], timeout: 30)
        beat(3.4) // the colouring, read before anybody answers it
        try tap(app.buttons, ["Yes, keep the colours", "Kyllä, tallenna värit"])
        beat(1.2) // the sheet closes on the answer
        // Back to the top of the card. `reveal` scrolled down to reach the
        // button, so by the time the photograph has colours it is above the
        // fold — and the photograph with its colours beside it, never in its
        // place, is the shot this take exists for.
        //
        // As far as the photograph and no further. The card opened out of its
        // tile, and one more pull at its top closes it back into the album
        // (27 Sep 2026), which two fixed swipes can reach.
        // Both the picture and the title are the untitled photograph's name.
        let untitled = ["Photograph", "Valokuva"]
        let photograph = app.images.matching(NSPredicate(format: "label IN %@", untitled)).firstMatch
        let title = app.navigationBars
            .matching(NSPredicate(format: "identifier IN %@ OR label IN %@", untitled, untitled)).firstMatch
        for _ in 0 ..< 4 where !(photograph.exists && title.exists
            && photograph.frame.minY >= title.frame.maxY - 1) {
            app.swipeDown(velocity: .slow)
        }
        beat(4.0)
    }

    // MARK: - The live takes (the v22 cut)

    // Everything above runs on the stub pipeline. The six takes below run the
    // app against a real Worker, a local one with a database of its own,
    // because three things the v22 cut shows exist only there: the words a
    // telling really said, an invitation carried from one phone to another,
    // and the month's ceiling as the server's own 402, answered by a purchase
    // that the other phone hears about.
    //
    // `rollLive` passes no `-api`, so the app reads its address from its own
    // defaults, and the Test Store key the purchase needs sits beside it
    // there, because nothing in this repository may carry one:
    //
    //     xcrun simctl spawn "$SIM" defaults write com.kinlore.app api http://127.0.0.1:<port>
    //     xcrun simctl spawn "$SIM" defaults write com.kinlore.app rcKey <key>   # by hand
    //
    // Two simulators, both named for filming: `kinlore-film-b` is hers, the
    // grandparent's phone that founds the archive, and `kinlore-film-a` is
    // the grandchild's, which joins it. The takes run in the order below, and
    // each carries on from the state the one before it left.
    //
    // The test cannot act for the Mac. Where only the Mac can (her voice into
    // the microphone, the link from one simulator's pasteboard to the other,
    // the meter filled in the Worker's database), the take prints one line,
    // `CUE <name> <epoch seconds>`, and waits for `<name>.done` in the
    // directory `TEST_RUNNER_KINLORE_CUE_DIR` names. That directory has to be
    // under /tmp, because the simulator cannot see a session's scratchpad
    // (`AccessibilityAudit`). The video project's `tools/live-take.sh` starts
    // the Worker, answers every cue and records the take:
    //
    //     testFilmTheTellingLive     B  clip-1         her telling, into the microphone
    //     testFilmTheInvitationLive  B  invite-copied  the invitation is on B's pasteboard
    //     testFilmTheJoinLive        A  join-link      B's link, opened on A
    //     testFilmTheCeilingLive     B  meter-full     600 of the month's 600 s used, in D1
    //                                   clip-4         her answer, into the microphone
    //     testFilmThePurchaseLive    A  (none)         needs the Test Store key
    //     testFilmTheOpeningLive     B  (none)         the catch-up, after the purchase
    //
    // Telling and Opening spend OpenRouter credit, and Purchase needs
    // RevenueCat's secret in the Worker. Invitation, Join and the ceiling run
    // on a Worker with no keys at all, because the quota is checked before
    // anything goes upstream (`checkAISeconds`, then `/transcribe`).

    /// B · Her telling on the real pipeline: the archive founded if this is
    /// the evening's first take, the button, `clip-1` into the microphone,
    /// the question the model really asked back, and what it made of her
    /// words. `testFilmTheTelling` films the same screens on the canned
    /// answer.
    func testFilmTheTellingLive() throws {
        let app = try rollLive(["-tab", "tell", "-voice", "stub"])
        try foundTheArchiveIfAsked(app)
        beat(2.2) // her button, before anybody presses it
        try startTelling(app)
        try cue("clip-1", orWait: 8)
        beat(0.8) // the last word, through the speaker and the microphone
        try tap(app.buttons, ["Stop telling", "Lopeta kertominen"])
        // Real transcription and extraction: seconds, not the stub's 3.6. A
        // model can also admit no question at all, and then the result comes
        // straight away.
        let enough = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["That is enough for now", "Riittää tältä erää"]))
            .firstMatch
        let saved = app.staticTexts
            .matching(NSPredicate(format: "label IN %@", ["Memory saved", "Muisto tallennettu"]))
            .firstMatch
        try waitForAny([enough, saved], ["That is enough for now", "Memory saved"], timeout: 120)
        if enough.exists {
            beat(3.2) // the question, long enough to be read and heard
            enough.tap()
            _ = try find(app.staticTexts, ["Memory saved", "Muisto tallennettu"], timeout: 30)
        } else {
            print("FILM no question came back; the take goes straight to the result")
        }
        beat(3.4) // her words, and the names in amber
        if let confirm = try? reveal(app, app.buttons, ["Confirm Toivo", "Vahvista Toivo"]) {
            confirm.tap()
        } else {
            print("FILM no Toivo to confirm in what the model heard; the take holds the result as it is")
        }
        beat(8.0)
    }

    /// B · The invitation, made for real: "Sanni" on the family screen, the
    /// Worker's code, the share sheet, and Copy. `invite-copied` lets the
    /// Mac check the link is on this phone's pasteboard, where the join take
    /// picks it up. The stub take stops at the name, because in stub nothing
    /// can make the code.
    func testFilmTheInvitationLive() throws {
        let app = try rollLive(["-screen", "family"])
        try foundTheArchiveIfAsked(app)
        let invite = try reveal(app, app.buttons, ["Invite a family member", "Kutsu perheenjäsen"])
        beat(1.6)
        invite.tap()
        let field = try find(app.textFields, ["Name", "Nimi"], timeout: 20)
        beat(1.2)
        field.tap()
        beat(0.4)
        field.typeText("Sanni")
        beat(1.4)
        try tap(app.buttons, ["Create an invitation", "Luo kutsu"])
        _ = try find(app.staticTexts, ["The invitation is ready", "Kutsu on valmis"], timeout: 40)
        beat(2.4) // the code, readable, before it goes anywhere
        try tap(app.buttons, ["Share the invitation", "Jaa kutsu"])
        beat(1.6) // the share sheet
        // iOS's own sheet. Its rows reach the app's tree as buttons or as
        // cells depending on the release, so any element with the label will do.
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "Kopioi"]))
        let deadline = Date().addingTimeInterval(20)
        while copy.allElementsBoundByIndex.first(where: \.isHittable) == nil {
            guard Date() < deadline else { throw NeverArrived(labels: ["Copy, in the share sheet"]) }
            Thread.sleep(forTimeInterval: 0.3)
        }
        copy.allElementsBoundByIndex.first(where: \.isHittable)?.tap()
        try cue("invite-copied", orWait: 2)
        beat(1.2)
        try tap(app.buttons, ["Done", "Valmis"], timeout: 15)
        beat(2.0)
    }

    /// A · The grandchild joins: the phone out of the box, the invitation
    /// arriving the way a tapped link arrives (`join-link`: the Mac opens the
    /// link from her phone's pasteboard on this one), "Join a family", and
    /// the album with her telling in it, played in her own voice.
    func testFilmTheJoinLive() throws {
        let app = try rollLive([])
        let fork = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Join with an invitation link", "Liity kutsulinkillä"]))
            .firstMatch
        guard fork.waitForExistence(timeout: 40) else {
            throw NeverArrived(labels: ["the onboarding fork — this phone already has an archive; erase it (docs/VIDEO.md)"])
        }
        beat(1.6) // the phone out of the box
        try cue("join-link", orWait: 20)
        // iOS may ask, in English, before a link opens an app — the invitation
        // text itself warns about it — so whichever comes first is taken: the
        // system's question, answered, or the form the link filled in.
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        let form = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Join a family", "Liity perheeseen"]))
            .firstMatch
        try waitForAny([open, form], ["Open, in the system's question", "Join a family"], timeout: 30)
        if open.exists {
            print("FILM iOS asked before opening the link; answering Open")
            beat(0.8)
            open.tap()
        }
        let join = try reveal(app, app.buttons, ["Join a family", "Liity perheeseen"])
        beat(1.4) // the form, filled in by the link
        join.tap()
        guard app.tabBars.firstMatch.waitForExistence(timeout: 60) else {
            throw NeverArrived(labels: ["the family's archive, after Join a family"])
        }
        // The launch after a join opens on the album (docs/UX.md §4.3), and
        // the first pull brings her telling into it. Its "New from the
        // family" row is worked out when the album appears, which is before
        // that pull, so the take opens the moment itself.
        try tap(app.tabBars.buttons, ["Album", "Albumi"])
        let moment = try find(app.buttons, ["Told on", "Kerrottu"], timeout: 90)
        beat(2.4)
        moment.tap()
        beat(2.0) // her words, on the grandchild's phone
        try reveal(app, app.buttons, ["Listen in their own voice", "Kuuntele omalla äänellä"]).tap()
        beat(9.0) // her voice, from the other phone
    }

    /// B · The ceiling, inside the conversation. With the month's meter full
    /// (`meter-full`), she answers the question the model asked in the
    /// telling take, from the first open row on that moment's card, and the
    /// Worker's real 402 lands where the next question would have: "Your
    /// voice is kept", with the day the time renews. Then the album, where the
    /// telling waits for its text.
    ///
    /// On a Worker without keys there is no telling take before this one, so
    /// no card with a question. The take then answers from the Tell tab, which
    /// reaches the same 402: the meter is read before anything goes upstream.
    func testFilmTheCeilingLive() throws {
        let app = try rollLive(["-tab", "memories", "-voice", "stub"])
        try foundTheArchiveIfAsked(app)
        try cue("meter-full", orWait: 20)
        beat(1.6) // the album, as it stands
        var fromTheCard = false
        if let moment = try? find(app.buttons, ["Told on", "Kerrottu"], timeout: 5) {
            moment.tap()
            beat(2.0) // the card, and what she told on it
            if let row = try firstOpenQuestion(app) {
                beat(1.2)
                tapCentre(of: row, in: app)
                fromTheCard = true
            }
        }
        if !fromTheCard {
            print("FILM no open question on a card; answering from the Tell tab")
            try tap(app.tabBars.buttons, ["Tell", "Kerro"])
        }
        beat(1.6) // the question as the title, before she answers
        try startTelling(app)
        try cue("clip-4", orWait: 6)
        beat(0.8)
        try tap(app.buttons, ["Stop telling", "Lopeta kertominen"])
        _ = try find(app.staticTexts, ["Your voice is kept", "Äänesi on tallessa"], timeout: 60)
        // The same heading follows a transcription that failed for any other
        // reason, a Worker that is down included. Only this sentence says it
        // was the month's time, which is the whole take.
        let ceiling = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "free transcription time is used up", "ilmainen litterointiaika on käytetty"
        )).firstMatch
        guard ceiling.waitForExistence(timeout: 10) else {
            throw NeverArrived(labels: ["the ceiling's sentence — the voice was kept for another reason (meter not full? Worker down?)"])
        }
        beat(5.0) // the sentence and its date, read
        try reveal(app, app.buttons, ["Done", "All right", "Valmis", "Selvä"]).tap()
        beat(1.2)
        try tap(app.tabBars.buttons, ["Album", "Albumi"])
        let note = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "One telling is waiting", "Yksi kertomus odottaa"
        )).firstMatch
        if !note.waitForExistence(timeout: 3), app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.element(boundBy: 0).tap() // from the card back to the album
        }
        if !note.waitForExistence(timeout: 20) {
            print("FILM the album's note about the waiting telling never showed")
        }
        beat(5.0)
    }

    /// A · The purchase: the family screen at the ceiling (Free, 10 / 10
    /// min), "Open the whole archive", RevenueCat's paywall, the lifetime
    /// package where the dashboard offers one (`/entitlement/sync` grants it
    /// without a webhook, and it never lapses), the Test Store's dialog, and
    /// the same screen reading Paid. Needs the Test Store key in this phone's
    /// defaults and RevenueCat's secret in the Worker.
    func testFilmThePurchaseLive() throws {
        let app = try rollLive(["-screen", "family"])
        guard statusReads(app, ["Free", "Ilmainen"], timeout: 30) else {
            throw NeverArrived(labels: ["Status: Free, on the family screen"])
        }
        beat(2.6) // Free, and the month's minutes used up
        guard let open = try? reveal(app, app.buttons, ["Open the whole archive", "Avaa koko arkisto"]) else {
            throw NeverArrived(labels: ["Open the whole archive — is the Test Store key in this phone's defaults?"])
        }
        open.tap()
        beat(2.6) // the paywall, and its price, read before anything is bought
        let lifetime = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "lifetime", "elinikäinen"
        )).firstMatch
        if lifetime.waitForExistence(timeout: 6), lifetime.isHittable {
            lifetime.tap()
            beat(1.0)
        } else {
            print("FILM no lifetime package on the paywall; buying the one it selected")
        }
        // The dashboard's button carries the offer card's words (13 Sep
        // 2026), so the last hittable one is the paywall's, as in the
        // stub take.
        try tapLast(app, "Open the whole archive", timeout: 30)
        beat(0.8)
        try tap(app.buttons, ["Test valid purchase"], timeout: 30)
        // The Test Store, then `/entitlement/sync`, then RevenueCat's REST
        // answer, then the refresh: unmeasured, and shown whole either way.
        guard statusReads(app, ["Paid", "Maksullinen"], timeout: 90) else {
            throw NeverArrived(labels: ["Status: Paid — the purchase did not reach the family"])
        }
        beat(6.0)
    }

    /// B · The archive opens, on her phone: at launch the app learns the family
    /// is paid and the catch-up writes the answer the ceiling kept as a voice,
    /// on camera, on the moment's card. Then the question the model asks
    /// next, if it asked one.
    func testFilmTheOpeningLive() throws {
        let app = try rollLive(["-tab", "memories"])
        let moment = try find(app.buttons, ["Told on", "Kerrottu"], timeout: 30)
        beat(1.2)
        moment.tap()
        beat(1.0)
        // A list builds only the rows on screen, so the waiting row is brought
        // into view before its disappearance can mean anything.
        let waiting = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Voice kept", "Ääni tallessa"
        )).firstMatch
        for _ in 0 ..< 4 where !waiting.exists {
            app.swipeUp(velocity: .slow)
            beat(0.5)
        }
        if waiting.exists {
            let deadline = Date().addingTimeInterval(90)
            while waiting.exists, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
            XCTAssertFalse(waiting.exists, "the answer is still only a voice after 90 s: did the family's purchase land?")
        } else {
            print("FILM the answer was written before the card opened; the take shows the words, not the change")
        }
        beat(3.0) // her words, where the voice was
        if try firstOpenQuestion(app) != nil {
            beat(6.0) // the question the model asks next
        } else {
            print("FILM no open question on the card after the catch-up")
            beat(3.0)
        }
    }

    // MARK: - The hand

    private struct NeverArrived: Error, CustomStringConvertible {
        let labels: [String]
        var description: String { "never arrived: \(labels.joined(separator: " / "))" }
    }

    /// Launch, in the phone's own language, with the stub pipeline behind it.
    /// `-api ""` is what every suite here passes: no address, no network, the
    /// canned round.
    private func roll(_ arguments: [String]) throws -> XCUIApplication {
        try launch(["-api", ""] + arguments)
    }

    /// Launch against the backend the device's own defaults name. `roll`
    /// without `-api ""`, which would outrank them: an argument beats a
    /// default, so the live takes pass no address at all (see the live
    /// takes above for what goes into the defaults).
    private func rollLive(_ arguments: [String]) throws -> XCUIApplication {
        try launch(arguments)
    }

    /// The gate both share: a simulator named for filming, or `KINLORE_FILM=1`.
    private func launch(_ arguments: [String]) throws -> XCUIApplication {
        let device = UIDevice.current.name
        try XCTSkipUnless(
            device.localizedCaseInsensitiveContains("film")
                || ProcessInfo.processInfo.environment["KINLORE_FILM"] == "1",
            "FilmDriver is a camera; it runs on a simulator named for filming. This one is \(device)."
        )
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        beat(1.6) // the launch screen, and a moment before anything moves
        return app
    }

    /// Hands one moment to the Mac, and waits until it has been done.
    ///
    /// Prints `CUE <name> <epoch seconds>` — flushed, because a runner's
    /// stdout is not a terminal and would otherwise sit in a buffer while the
    /// take waits on it — and leaves `<name>.cue` in the cue directory for a
    /// log that runs late. Then it waits for `<name>.done` there. Without a
    /// cue directory it is a fixed pause, for whoever answers by hand.
    private func cue(_ name: String, orWait fallback: TimeInterval, timeout: TimeInterval = 180) throws {
        let now = Date().timeIntervalSince1970
        print("CUE \(name) \(String(format: "%.3f", now))")
        fflush(stdout)
        guard let dir = ProcessInfo.processInfo.environment["KINLORE_CUE_DIR"], !dir.isEmpty else {
            beat(fallback)
            return
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? String(format: "%.3f\n", now)
            .write(to: folder.appendingPathComponent("\(name).cue"), atomically: true, encoding: .utf8)
        let done = folder.appendingPathComponent("\(name).done").path
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: done) {
            guard Date() < deadline else { throw NeverArrived(labels: ["the Mac's answer to CUE \(name)"]) }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Her phone on its first launch against an empty Worker: the fork, "Start
    /// a family archive", her name, and the phone marked as a grandparent's —
    /// which is what she holds, and which also skips the first-minute sheet a
    /// founder's own phone raises. A phone that already has its archive shows
    /// the tab bar instead and goes straight on, so any of her takes can be the
    /// evening's first.
    private func foundTheArchiveIfAsked(_ app: XCUIApplication) throws {
        let fork = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Start a family archive", "Aloita perheen arkisto"]))
            .firstMatch
        let bar = app.tabBars.firstMatch
        try waitForAny([fork, bar], ["Start a family archive", "the tab bar"], timeout: 40)
        guard fork.exists else { return }
        beat(1.4)
        fork.tap()
        let name = try find(app.textFields, ["Your name", "Nimesi"], timeout: 20)
        beat(1.0)
        name.tap()
        // Return ends the editing (the field has no submit action), which
        // takes the keyboard off the two answers below it.
        name.typeText("Grandma\n")
        beat(0.8)
        try reveal(app, app.buttons, ["A grandparent's", "Isovanhemman"]).tap()
        beat(1.0)
        try reveal(app, app.buttons, ["Create the archive", "Luo arkisto"]).tap()
        guard bar.waitForExistence(timeout: 40) else {
            throw NeverArrived(labels: ["the archive, after Create the archive"])
        }
        beat(1.6)
    }

    /// The big button, and the recording it starts. On a simulator nobody
    /// granted the microphone, the press raises iOS's prompt instead, and the
    /// stop button then never arrives (`testFilmTheTelling` says what that
    /// cost once).
    private func startTelling(_ app: XCUIApplication) throws {
        try tap(app.buttons, ["Start telling", "Aloita kertominen"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 1.5) {
            throw NeverArrived(labels: [
                "the recording — the microphone prompt is up; grant it before rolling: "
                    + "xcrun simctl privacy <sim> grant microphone com.kinlore.app",
            ])
        }
        _ = try find(app.buttons, ["Stop telling", "Lopeta kertominen"], timeout: 15)
    }

    /// The first open question on the card on screen, whatever the model
    /// asked: the button right under the "Open questions" header.
    /// Nothing else identifies it — its label is the question — so this
    /// reads one snapshot for the header and the rows under it, and scrolls
    /// until the row is clear of the tab bar: a list row built under the bar
    /// reports hittable and takes the tap on a corner that opens nothing
    /// (`TargetedQuestionTests`). Nil when the card has no open question.
    private func firstOpenQuestion(_ app: XCUIApplication, attempts: Int = 5) throws -> CGRect? {
        let headers = ["open questions", "avoimia kysymyksiä"]
        let notQuestions = ["Ask the family", "Kysy perheeltä"]
        for _ in 0 ..< attempts {
            var header: CGRect?
            var bar: CGRect?
            var buttons: [CGRect] = []
            func walk(_ node: XCUIElementSnapshot) {
                if headers.contains(node.label.lowercased()) { header = node.frame }
                if node.elementType == .tabBar { bar = node.frame }
                if node.elementType == .button, !notQuestions.contains(node.label) { buttons.append(node.frame) }
                node.children.forEach(walk)
            }
            walk(try app.snapshot())
            if let header {
                let floor = (bar?.minY ?? app.frame.maxY) - 8
                let row = buttons
                    .filter { $0.minY >= header.maxY - 2 && $0.minY < floor }
                    .min { $0.minY < $1.minY }
                if let row, row.midY < floor { return row }
            }
            app.swipeUp(velocity: .slow)
            beat(0.6)
        }
        return nil
    }

    private func tapCentre(of frame: CGRect, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }

    /// Whether the family screen's Status row reads one of these words: as
    /// its row's value, or as a text of its own, whichever this iOS builds
    /// out of a `LabeledContent`.
    private func statusReads(_ app: XCUIApplication, _ words: [String], timeout: TimeInterval) -> Bool {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Status", "Tila"]))
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for row in rows.allElementsBoundByIndex {
                if let value = row.value as? String, words.contains(value) { return true }
            }
            if words.contains(where: { app.staticTexts[$0].exists }) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// Whichever of these turns up first; `labels` name them for the error.
    private func waitForAny(_ elements: [XCUIElement], _ labels: [String], timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !elements.contains(where: \.exists) {
            guard Date() < deadline else { throw NeverArrived(labels: labels) }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// The pause between two acts. Long enough to read what is on screen —
    /// which is the whole difference between a test and a take.
    private func beat(_ seconds: TimeInterval = 1.4) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The first of these labels that turns up, exactly or as a prefix.
    ///
    /// A list rather than one string, because half of what this taps is
    /// labelled in whichever language the string happens to have reached, and
    /// a driver that breaks the day a translation lands is a driver nobody
    /// will run on filming night. Prefixes because several labels carry the
    /// subject's own name — "Vahvista Aino", "Eeva, 1 muisto".
    private func find(
        _ query: XCUIElementQuery,
        _ labels: [String],
        timeout: TimeInterval = 25
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let exact = query[label]
                if exact.exists { return exact }
                let prefixed = query
                    .matching(NSPredicate(format: "label BEGINSWITH %@", label))
                    .firstMatch
                if prefixed.exists { return prefixed }
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        throw NeverArrived(labels: labels)
    }

    private func tap(
        _ query: XCUIElementQuery,
        _ labels: [String],
        timeout: TimeInterval = 25
    ) throws {
        try find(query, labels, timeout: timeout).tap()
    }

    /// Scroll it into view first, the way the other suites do: these screens
    /// are longer than a phone, and an element that exists off-screen taps at
    /// the wrong place or not at all.
    private func reveal(
        _ app: XCUIApplication,
        _ query: XCUIElementQuery,
        _ labels: [String]
    ) throws -> XCUIElement {
        for _ in 0 ..< 5 {
            if let found = try? find(query, labels, timeout: 1.5), found.isHittable { return found }
            app.swipeUp()
            beat(0.6)
        }
        return try find(query, labels, timeout: 8)
    }
}
