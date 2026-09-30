import XCTest

/// Settings from Kerro and from both views of Sukupuu, since 30 Sep 2026
/// (`SettingsGear`). Until then the gear stood on the people list alone, and
/// on a phone that opens Sukupuu on the drawn tree the way to Settings was a
/// row in the tree's menu.
///
/// Not from Albumi. The gear stood there at first, and with the map, "+"
/// and the search it pressed the album's title into "Alb…" whenever the
/// album had scrolled (`GalleryScreen` says how it was measured).
///
/// A grandparent's Kerro keeps no gear either, because there the tab is the
/// button and nothing else (`TellScreen.showsSettings`). She finds Settings
/// on Sukupuu, at every text size.
final class SettingsGearTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A reader's phone with a confirmed family, so that Sukupuu opens on the
    /// tree: the one bar that had no gear at all. Each tab's Settings opens
    /// the help page as well, on that tab's own stack, because a stack that
    /// pushes a route it has no destination for does nothing and says
    /// nothing (`settingsDestinations`). The album is where it starts, with
    /// its "+" and no gear.
    func testKerroAndTheTreeOpenSettings() {
        let app = launch([
            "-seed", "related", "-tab", "memories",
            "-people", "default", "-people.showsList", "NO",
            "-elder.largerText", "NO",
        ])
        XCTAssertTrue(app.buttons["Lisää kuvia"].waitForExistence(timeout: 10), "never arrived: the album's \"+\"")
        XCTAssertFalse(app.buttons["settings"].exists, "a gear in the album's bar")
        for tab in ["Kerro", "Sukupuu"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 10), "no tab called \(tab)")
            tabButton.tap()
            let gear = app.buttons["settings"]
            XCTAssertTrue(gear.waitForExistence(timeout: 10), "\(tab) has no way to Settings")
            gear.tap()
            XCTAssertTrue(
                app.navigationBars["Asetukset"].waitForExistence(timeout: 10),
                "the gear on \(tab) did not open Settings"
            )
            let help = app.buttons["Näin tämä toimii"]
            for _ in 0 ..< 3 where !(help.exists && help.isHittable) { app.swipeUp() }
            help.tap()
            XCTAssertTrue(
                app.navigationBars["Näin tämä toimii"].waitForExistence(timeout: 10),
                "the help page did not open from Settings on \(tab)"
            )
        }
    }

    /// A grandparent's phone: the button and nothing else on Kerro, no gear
    /// on Albumi, and the gear on Sukupuu, which is then her one way in and
    /// so has to open Settings.
    func testAGrandparentsKerroKeepsTheButtonAlone() {
        let app = launch(["-seed", "archive", "-tab", "tell", "-elder.largerText", "YES"])
        XCTAssertTrue(
            app.staticTexts["Paina ja ala puhua"].waitForExistence(timeout: 10),
            "never arrived: the Kerro tab"
        )
        XCTAssertFalse(app.buttons["settings"].exists, "a gear on a grandparent's Kerro")
        app.tabBars.buttons["Albumi"].tap()
        XCTAssertTrue(app.buttons["Lisää kuvia"].waitForExistence(timeout: 10), "never arrived: the album's \"+\"")
        XCTAssertFalse(app.buttons["settings"].exists, "a gear in the album's bar on a grandparent's phone")
        app.tabBars.buttons["Sukupuu"].tap()
        let gear = app.buttons["settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Sukupuu has no way to Settings on a grandparent's phone")
        gear.tap()
        XCTAssertTrue(
            app.navigationBars["Asetukset"].waitForExistence(timeout: 10),
            "the gear on Sukupuu did not open Settings on a grandparent's phone"
        )
    }

    /// At the largest text size Settings still open from Sukupuu, on a
    /// reader's phone and on a grandparent's, whose Kerro has no gear at any
    /// size, and the album's bar keeps "+" with no gear beside it. Whoever
    /// reads the largest text is the person rule 1 is about, and a way to
    /// Settings that went with the room would shut her out of them.
    func testAtTheLargestSizeSettingsOpenFromIhmiset() {
        for grandparent in [false, true] {
            let phone = grandparent ? "a grandparent's phone" : "a reader's phone"
            let app = launch(
                ["-seed", "archive", "-tab", "memories", "-elder.largerText", grandparent ? "YES" : "NO"],
                textSize: "UICTContentSizeCategoryAccessibilityXXXL"
            )
            // "+" first, so the right-hand side of the bar is known to be
            // built before the gear's absence is read off it.
            XCTAssertTrue(
                app.buttons["Lisää kuvia"].waitForExistence(timeout: 10),
                "never arrived: the album's \"+\" on \(phone)"
            )
            XCTAssertFalse(
                app.buttons["settings"].exists,
                "a gear in the album's bar at the largest size on \(phone)"
            )
            app.tabBars.buttons["Sukupuu"].tap()
            let gear = app.buttons["settings"]
            XCTAssertTrue(
                gear.waitForExistence(timeout: 10),
                "Sukupuu has no way to Settings at the largest size on \(phone)"
            )
            gear.tap()
            XCTAssertTrue(
                app.navigationBars["Asetukset"].waitForExistence(timeout: 10),
                "the gear on Sukupuu did not open Settings at the largest size on \(phone)"
            )
            app.terminate()
        }
    }
}
