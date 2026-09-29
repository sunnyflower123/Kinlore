import XCTest

/// The example on an install somebody is trying the app out on (`TryIt`).
///
/// It is the one thing `-tryIt YES` changes, and the promise has two sides.
/// The example is there on the first Tell screen of a trial install, in the
/// place of the opening starters, and it outlasts the process that was given
/// the argument. And it is nowhere else: not on an install that never saw the
/// argument, which is every phone the app is really used on, and not once
/// anything has been told. The second side is the one that fails quietly — an
/// example sentence on a grandmother's first screen would look like a feature.
///
/// `launch` passes `-tryIt NO` unless a test names the argument itself, so an
/// install this class left in trial mode is put back by the next launch.
final class TryItTests: XCTestCase {
    /// The example as the Finnish table has it, which is what the suite runs in.
    static let sentence = "Mummoni Anna kasvoi Helsingissä. Hän meni naimisiin Valtterin kanssa joskus viisikymmentäluvulla, ja kamera oli aina Valtterilla."

    /// The example on the screen, found by its label. `staticTexts[sentence]`
    /// throws before it looks: a query refuses an identifier over 128
    /// characters, and the Finnish sentence has 129.
    static func example(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", sentence)).firstMatch
    }

    /// The first of the opening starters, which the example stands in for.
    private static let starter = "Kuka on vanhin ihminen, jonka muistat?"

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheExampleIsOfferedOnlyWhenTryingItOut() {
        let trying = launch(["-seed", "empty", "-tryIt", "YES"])
        XCTAssertTrue(
            Self.example(in: trying).waitForExistence(timeout: 15),
            "a trial install's first Tell screen has no example"
        )
        XCTAssertTrue(trying.buttons["Kirjoita se puolestani"].exists, "no way to have the example typed")
        XCTAssertFalse(trying.staticTexts[Self.starter].exists, "the starters are offered beside the example")
        trying.terminate()

        let plain = launch(["-seed", "empty"])
        XCTAssertTrue(
            plain.staticTexts[Self.starter].waitForExistence(timeout: 15),
            "the first launch lost its starters"
        )
        XCTAssertFalse(Self.example(in: plain).exists, "the example is offered on an install nobody is trying out")
        XCTAssertFalse(plain.buttons["Kirjoita se puolestani"].exists, "the example's button is on an ordinary install")
        plain.terminate()

        // A trial install with something told already: the archive is past
        // the moment the example is for.
        let told = launch(["-seed", "archive", "-tryIt", "YES"])
        XCTAssertTrue(told.buttons["Aloita kertominen"].waitForExistence(timeout: 15), "never arrived: the record button")
        XCTAssertFalse(Self.example(in: told).exists, "the example is offered over an archive with tellings in it")
        told.terminate()
    }

    /// The button fills the field and sends nothing: the telling is saved by
    /// the same *Tallenna* as anything typed. Once it is, the example has done
    /// its work and is gone.
    func testTypingTheExampleFillsTheFieldAndTheFirstTellingPutsItAway() {
        let app = launch(["-seed", "empty", "-tryIt", "YES"])
        let typeIt = app.buttons["Kirjoita se puolestani"]
        XCTAssertTrue(typeIt.waitForExistence(timeout: 15), "no way to have the example typed")
        typeIt.tap()

        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the typing field did not open")
        XCTAssertEqual(field.value as? String, Self.sentence, "the field does not hold the example")
        XCTAssertFalse(app.staticTexts["Muisto tallennettu"].exists, "the example was saved before anybody saved it")

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "never arrived: the keyboard's Tallenna")
        save.tap()
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "the typed example was not saved"
        )

        let another = app.buttons["Kerro toinen muisto"]
        for _ in 0 ..< 4 where !another.isHittable { app.swipeUp() }
        XCTAssertTrue(another.waitForExistence(timeout: 10), "never arrived: the way on")
        another.tap()

        XCTAssertTrue(
            app.buttons["Aloita kertominen"].waitForExistence(timeout: 10),
            "finishing did not return to the idle screen"
        )
        XCTAssertFalse(Self.example(in: app).exists, "the example outlived the first telling")
        XCTAssertFalse(app.buttons["Kirjoita se puolestani"].exists, "the example's button outlived the first telling")
    }

    /// A launch argument lasts one process. Opened again from its icon, the
    /// same install is launched with none, and has to remember that it is
    /// being tried out.
    func testTryingItOutSurvivesALaunchWithoutTheArgument() {
        let app = launch(["-seed", "empty", "-tryIt", "YES"])
        XCTAssertTrue(
            Self.example(in: app).waitForExistence(timeout: 15),
            "a trial install's first Tell screen has no example"
        )
        app.terminate()

        var arguments = app.launchArguments
        if let at = arguments.firstIndex(of: "-tryIt") {
            arguments.removeSubrange(at ... at + 1)
        }
        XCTAssertFalse(arguments.contains("-tryIt"), "the relaunch still carries the argument")
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(
            Self.example(in: app).waitForExistence(timeout: 15),
            "the install forgot it was being tried out when the argument went"
        )
        app.terminate()
    }
}
