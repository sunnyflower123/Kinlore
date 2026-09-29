import XCTest

/// Settings from every tab, since 30 Sep 2026 (`SettingsGear`). Until then
/// the gear stood on the people list alone, and on a phone that opens Ihmiset
/// on the drawn tree the way to Settings was a row in the tree's menu, so
/// somebody who wanted a setting from the album had to know which tab kept
/// it.
///
/// A grandparent's Kerro keeps no gear, because there the tab is the button
/// and nothing else (`TellScreen.showsSettings`). She has the one on Albumi
/// and Ihmiset like everybody.
final class SettingsGearTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A reader's phone with a confirmed family, so that Ihmiset opens on the
    /// tree: the one bar that had no gear at all. Each tab's Settings opens
    /// the help page as well, on that tab's own stack, because a stack that
    /// pushes a route it has no destination for does nothing and says
    /// nothing (`settingsDestinations`).
    func testEveryTabOpensSettings() {
        let app = launch([
            "-seed", "related", "-tab", "memories",
            "-people", "default", "-people.showsList", "NO",
            "-elder.largerText", "NO",
        ])
        for tab in ["Albumi", "Kerro", "Sukupuu"] {
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

    /// A grandparent's phone: the button and nothing else on Kerro, and the
    /// gear on the other two tabs.
    func testAGrandparentsKerroKeepsTheButtonAlone() {
        let app = launch(["-seed", "archive", "-tab", "tell", "-elder.largerText", "YES"])
        XCTAssertTrue(
            app.staticTexts["Paina ja ala puhua"].waitForExistence(timeout: 10),
            "never arrived: the Kerro tab"
        )
        XCTAssertFalse(app.buttons["settings"].exists, "a gear on a grandparent's Kerro")
        for tab in ["Albumi", "Ihmiset"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(
                app.buttons["settings"].waitForExistence(timeout: 10),
                "\(tab) has no way to Settings on a grandparent's phone"
            )
        }
    }
}
