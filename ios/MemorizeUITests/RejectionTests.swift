import XCTest

/// Rejecting a person the extraction proposed.
///
/// The rejection is a tombstone rather than a removal, so that it reaches the
/// rest of the family: a row taken off one device is a row the next pull hands
/// straight back, and rejecting is only offered in the seconds after telling —
/// so what came back could never be got rid of again.
///
/// That the tombstone travels, and that a stale device cannot revive it, is
/// checked against SQLite on the schema. What is checked here is the risk the
/// change introduces at the other end: **a subject that is kept must not still
/// be shown.** Every list and lookup in the store had to learn to skip it, and
/// missing one would put the rejected person back on the people list — the exact
/// thing this was meant to stop, arrived at from the opposite direction.
///
/// The demo archive carries a rejected person for this. Driving a real rejection
/// through the UI was tried and needs the keyboard's accessory toolbar, which is
/// reliably there on its own and not reliably there in a suite run; a test that
/// passes alone and fails in company is worse than no test.
final class RejectionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testARejectedPersonIsNotOnThePeopleList() throws {
        let app = launch(["-seed", "guess", "-tab", "people"])

        XCTAssertTrue(
            app.staticTexts["Aino"].waitForExistence(timeout: 10),
            "the people list, so that the absence below means something"
        )
        XCTAssertFalse(
            app.staticTexts["Skotlanti"].exists,
            "a rejected person is kept only so the rejection can travel, and must not be shown"
        )
    }
}
