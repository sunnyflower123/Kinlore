// Checks when the finished-memory screen offers the paid archive.
//
// The rhythm is four lines of arithmetic over one UserDefaults key, and every
// way it can go wrong is silent. Too eager and the app asks an 80-year-old to
// buy something after every story she tells; too shy and nobody is ever asked;
// wrong about proposals and the offer lands next to the names she has to check,
// which is rule 4's mechanism and the one place a wrong person becomes a fact.
//
// None of that shows up in a screenshot, and none of it fails a build. Run it
// after touching UpsellRhythm.swift — the command is in CLAUDE.md.
//
//   swiftc -parse-as-library -o /tmp/upsell-rhythm-check \
//     scripts/upsell-rhythm-check.swift ios/Kinlore/Services/UpsellRhythm.swift

import Foundation

@main
enum UpsellRhythmCheck {
    @MainActor
    static func main() {
        var failures = 0

        func check(_ label: String, _ actual: Bool, _ expected: Bool) {
            if actual == expected {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): got \(actual), expected \(expected)")
            }
        }

        /// Every case starts from a phone that has never been asked.
        func fresh() { UpsellRhythm.reset() }

        print("— the rhythm —")
        fresh()
        check("first telling is quiet", UpsellRhythm.shouldShow(hasProposals: false), false)
        check("second telling is quiet", UpsellRhythm.shouldShow(hasProposals: false), false)
        check("third telling offers", UpsellRhythm.shouldShow(hasProposals: false), true)
        check("and the count starts again", UpsellRhythm.shouldShow(hasProposals: false), false)
        check("second after that is quiet too", UpsellRhythm.shouldShow(hasProposals: false), false)
        check("sixth telling offers", UpsellRhythm.shouldShow(hasProposals: false), true)

        print("— never against a name to confirm —")
        fresh()
        _ = UpsellRhythm.shouldShow(hasProposals: false)
        _ = UpsellRhythm.shouldShow(hasProposals: false)
        check(
            "a telling that proposed names shows nothing, however long it has been",
            UpsellRhythm.shouldShow(hasProposals: true),
            false
        )
        // The rhythm must not stall behind an archive that names somebody every
        // time: the count kept running, so the next quiet telling is the one.
        check(
            "the next telling without names offers at once",
            UpsellRhythm.shouldShow(hasProposals: false),
            true
        )

        print("— a run of names never turns into a run of offers —")
        fresh()
        for _ in 0 ..< 10 {
            check("still nothing", UpsellRhythm.shouldShow(hasProposals: true), false)
        }

        print("— emptying the device forgets it —")
        fresh()
        _ = UpsellRhythm.shouldShow(hasProposals: false)
        _ = UpsellRhythm.shouldShow(hasProposals: false)
        UpsellRhythm.reset()
        check("the count is gone, not merely paused", UpsellRhythm.shouldShow(hasProposals: false), false)

        // The slot's other half: which card it holds once the rhythm has said
        // it shows at all. A family of one offered the paid archive is being
        // told "yksi maksaja avaa sen koko perheelle" with nobody to open it
        // for; a family of one offered nothing never finds the invitation at
        // all, four levels deep in Settings. docs/UX.md §3.2.
        func checkCard(
            _ label: String, _ actual: UpsellRhythm.Card?, _ expected: UpsellRhythm.Card?
        ) {
            if actual == expected {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): got \(String(describing: actual)), "
                    + "expected \(String(describing: expected))")
            }
        }

        print("— what the slot holds —")
        checkCard(
            "no family details, nothing offered",
            UpsellRhythm.card(membersInFamily: nil, isPaid: false), nil
        )
        checkCard(
            "a family of one is offered the family, never the archive",
            UpsellRhythm.card(membersInFamily: 1, isPaid: false), .invite
        )
        checkCard(
            "a paid family of one is still offered the family",
            UpsellRhythm.card(membersInFamily: 1, isPaid: true), .invite
        )
        checkCard(
            "a free family of two is offered the archive",
            UpsellRhythm.card(membersInFamily: 2, isPaid: false), .archive
        )
        checkCard(
            "a paid family is offered nothing",
            UpsellRhythm.card(membersInFamily: 3, isPaid: true), nil
        )

        UpsellRhythm.reset()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
