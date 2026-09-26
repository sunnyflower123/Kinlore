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
    /// button, her telling, and what the app made of it — ending on one name
    /// confirmed by a person and the other left open, which is rule 4
    /// happening on camera.
    ///
    /// `-seed film-untold` is the film's archive a minute before she speaks,
    /// so the Kerro tab offers the photograph; `-sample film` makes the stub
    /// write down the film's own telling — the words her voice says on the
    /// soundtrack — and return the extraction the pipeline gave them. The
    /// listening runs longer than her clip (7.5 s): the film lays the voice
    /// over the take, and the take must not stop first. The 10 Sep cut's
    /// version of this scene ran on `-seed empty` and the rotating samples.
    func testFilmTheTelling() throws {
        let app = try roll(["-seed", "film-untold", "-sample", "film", "-tab", "tell"])
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
        _ = try find(app.staticTexts, ["Memory saved", "Muisto tallennettu"], timeout: 40)
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
        app.swipeDown(velocity: .slow)
        app.swipeDown(velocity: .slow)
        beat(4.0)
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
        let device = UIDevice.current.name
        try XCTSkipUnless(
            device.localizedCaseInsensitiveContains("film")
                || ProcessInfo.processInfo.environment["KINLORE_FILM"] == "1",
            "FilmDriver is a camera; it runs on a simulator named for filming. This one is \(device)."
        )
        let app = XCUIApplication()
        app.launchArguments += ["-api", ""] + arguments
        app.launch()
        beat(1.6) // the launch screen, and a moment before anything moves
        return app
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
