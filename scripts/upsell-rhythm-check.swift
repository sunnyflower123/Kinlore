// Checks when the finished-memory screen offers the paid archive.
//
// The rhythm is four lines of arithmetic over one UserDefaults key, and every
// way it can go wrong is silent. Too eager and the app asks an 80-year-old to
// buy something after every story she tells; too shy and nobody is ever asked;
// wrong about proposals and the offer lands next to the names she has to check,
// which is rule 4's mechanism and the one place a wrong person becomes a fact.
//
// It also holds the one offer that does not wait for a telling: the purchase
// beside a ceiling the family has hit, which stands on every phone with a
// store, a grandparent's included.
//
// None of that shows up in a screenshot, and none of it fails a build. Run it
// after touching UpsellRhythm.swift — the command is in docs/DEVELOPMENT.md.
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
            UpsellRhythm.card(membersInFamily: nil, isPaid: false, onGrandparentsPhone: false, canPurchase: true), nil
        )
        checkCard(
            "a family of one is offered the family, never the archive",
            UpsellRhythm.card(membersInFamily: 1, isPaid: false, onGrandparentsPhone: false, canPurchase: true), .invite
        )
        checkCard(
            "a paid family of one is still offered the family",
            UpsellRhythm.card(membersInFamily: 1, isPaid: true, onGrandparentsPhone: false, canPurchase: true), .invite
        )
        checkCard(
            "a free family of two is offered the archive",
            UpsellRhythm.card(membersInFamily: 2, isPaid: false, onGrandparentsPhone: false, canPurchase: true), .archive
        )
        checkCard(
            "a paid family is offered nothing",
            UpsellRhythm.card(membersInFamily: 3, isPaid: true, onGrandparentsPhone: false, canPurchase: true), nil
        )

        // Whose phone it is. The one holding a grandparent's phone is the one
        // the archive is for, and somebody else pays for it (docs/PLAN.md §9):
        // the card never asks her after a telling. The invitation is not a
        // purchase, and a grandparent alone needs it more than anybody to
        // bring the family in. A ceiling is another rule. It is the family's,
        // the same wall on every phone, and since 26 Sep 2026 so is the way
        // past it: on the phone of the one who does most of the telling, a
        // wall with nothing beside it says only that there is no way up.
        print("— on a grandparent's phone —")
        checkCard(
            "a free family is not offered the archive there",
            UpsellRhythm.card(membersInFamily: 2, isPaid: false, onGrandparentsPhone: true, canPurchase: true), nil
        )
        checkCard(
            "however large the family",
            UpsellRhythm.card(membersInFamily: 7, isPaid: false, onGrandparentsPhone: true, canPurchase: true), nil
        )
        checkCard(
            "a grandparent alone is still offered the family",
            UpsellRhythm.card(membersInFamily: 1, isPaid: false, onGrandparentsPhone: true, canPurchase: true), .invite
        )
        check(
            "but the purchase beside a ceiling she has hit is",
            UpsellRhythm.offersPurchaseAtCeiling(onGrandparentsPhone: true, canPurchase: true), true
        )
        check(
            "as it is on a reader's phone",
            UpsellRhythm.offersPurchaseAtCeiling(onGrandparentsPhone: false, canPurchase: true), true
        )

        // And whether there is anything to buy. `canPurchase` is whether a
        // RevenueCat key is configured, and on a phone opened from its home
        // screen there is none: `-rcKey` does not outlive the launch it came
        // with. Until 26 Sep 2026 the card rose there anyway and drew no
        // button — every third telling ended on an offer nobody could take.
        print("— with nothing to buy —")
        checkCard(
            "a free family is offered nothing",
            UpsellRhythm.card(membersInFamily: 2, isPaid: false, onGrandparentsPhone: false, canPurchase: false), nil
        )
        checkCard(
            "a family of one is still offered the family",
            UpsellRhythm.card(membersInFamily: 1, isPaid: false, onGrandparentsPhone: false, canPurchase: false), .invite
        )
        check(
            "nor is the purchase beside a ceiling",
            UpsellRhythm.offersPurchaseAtCeiling(onGrandparentsPhone: false, canPurchase: false), false
        )
        check(
            "on a grandparent's phone either",
            UpsellRhythm.offersPurchaseAtCeiling(onGrandparentsPhone: true, canPurchase: false), false
        )

        print("— whether the slot shows —")
        check(
            "the invitation shows without the rhythm, once the names are answered",
            UpsellRhythm.slotShows(card: .invite, rhythm: false, proposalsRemaining: false), true
        )
        check(
            "the invitation waits while a name is still on the screen",
            UpsellRhythm.slotShows(card: .invite, rhythm: true, proposalsRemaining: true), false
        )
        check(
            "the archive keeps the rhythm",
            UpsellRhythm.slotShows(card: .archive, rhythm: false, proposalsRemaining: false), false
        )
        check(
            "the archive shows when the rhythm says so",
            UpsellRhythm.slotShows(card: .archive, rhythm: true, proposalsRemaining: false), true
        )
        check(
            "nothing to hold, nothing shown",
            UpsellRhythm.slotShows(card: nil, rhythm: true, proposalsRemaining: false), false
        )

        UpsellRhythm.reset()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
