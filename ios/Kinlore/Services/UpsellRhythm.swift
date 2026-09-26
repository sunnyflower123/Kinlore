import Foundation

/// How often the finished-memory screen offers the paid archive.
///
/// The moment is right and stays: value peaks when a telling has just been saved
/// (§6), and the card blocks nothing — telling is never paywalled (rule 2). What
/// was wrong is that it appeared **every single time**, on the screen somebody
/// reaches when they are most tired, between the names they have to check and
/// the way out.
///
/// Two rules, and the first matters more than the second:
///
/// 1. **Never against a name.** A proposal on that screen is rule 4's whole
///    mechanism — a wrong person becomes a fact if nobody looks — and an offer
///    to buy something is the worst possible neighbour for it. A telling that
///    proposes names shows no card at all, however long it has been.
/// 2. **Not every time.** One in three finished tellings, counted on the device.
///
/// Both are the *paid card's* rules. The invitation a family of one is shown
/// instead follows only the first, and by waiting rather than by hiding — see
/// `slotShows`. On a grandparent's phone, and on any phone with no store to
/// buy from, only the invitation is ever held — see `card`. The purchase
/// beside a ceiling the family has hit is another rule — see
/// `offersPurchaseAtCeiling`.
///
/// The count is `UserDefaults` and never syncs, for the same reason the question
/// ladder's comfort does not (§12): it describes the person holding the phone,
/// and a family has no business seeing how often somebody has been asked to pay.
/// "Tyhjennä tämä laite" clears it with the rest of what this phone knows.
@MainActor
enum UpsellRhythm {
    /// One in three. Low enough that the offer is not the shape of the app, high
    /// enough that somebody who tells often meets it in a week.
    static let every = 3

    private static let key = "tellings-since-upsell"

    /// Called once per finished telling, when the result screen is built.
    ///
    /// It counts even when it answers false: a telling that proposed names is
    /// still a telling, and the rhythm should not stall behind an archive that
    /// happens to name somebody every time.
    static func shouldShow(hasProposals: Bool) -> Bool {
        let count = UserDefaults.standard.integer(forKey: key) + 1
        guard !hasProposals, count >= every else {
            UserDefaults.standard.set(count, forKey: key)
            return false
        }
        UserDefaults.standard.set(0, forKey: key)
        return true
    }

    /// Part of emptying the device, like the ladder's own reset.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - What the slot holds

    /// The two cards the offer slot on the finished-memory screen can carry.
    /// One slot, one card — §22's framed exception, transferred rather than
    /// duplicated.
    enum Card {
        /// "Kutsu perheenjäsen": the family is still one person.
        case invite
        /// "Avaa koko arkisto": a real family on the free tier.
        case archive
    }

    /// Which card the slot holds, once `shouldShow` has said it shows at all.
    ///
    /// While the family is one person the thing worth offering is the family
    /// itself — *"yksi maksaja avaa sen koko perheelle"* is a false sentence
    /// with nobody to open it for — and the paid archive follows once there is
    /// somebody to share it with. See docs/UX.md §3.2.
    ///
    /// `members` is the fetched member count, nil when `Session.family` is:
    /// with no family details there is nothing to decide from — offline, or a
    /// single-device archive — and the slot stays empty. A family that has
    /// paid is offered nothing; it is never asked to invite either, wrongly,
    /// because a paid family of one still deserves the invitation.
    ///
    /// The paid archive is this card only where there is something to buy.
    /// `canPurchase` is whether a RevenueCat key is configured
    /// (`RevenueCatPurchases.configuredKey`), handed in rather than read here
    /// so that this stays arithmetic the check can run. Until 26 Sep 2026 the
    /// card rose without one and simply drew no button, and `-rcKey` is a
    /// launch argument that does not outlive its launch (docs/VIDEO.md §5) —
    /// so on a phone opened from its home screen, every third telling ended on
    /// an offer with nothing to tap.
    ///
    /// And never on a grandparent's phone, which is the text-floor signal
    /// (`Elder.largerTextKey`) that the tree, the search and the blind card
    /// already follow, while the invitation still is: she is exactly who a
    /// family of one needs to bring the others in. The person holding that
    /// phone is the one the archive is for, and the one who pays is somebody
    /// else (docs/PLAN.md §9). This card is a sale rising at the end of the
    /// one act the phone is for, so there it asks the wrong person. The
    /// family screen keeps its button, because somebody goes there on
    /// purpose, and a ceiling keeps its own (`offersPurchaseAtCeiling`).
    static func card(
        membersInFamily members: Int?, isPaid: Bool,
        onGrandparentsPhone: Bool, canPurchase: Bool
    ) -> Card? {
        guard let members else { return nil }
        if members <= 1 { return .invite }
        guard canPurchase, !onGrandparentsPhone else { return nil }
        return isPaid ? nil : .archive
    }

    /// Whether "Avaa koko arkisto" stands beside a ceiling the family has hit:
    /// the photographs' total and the month's transcription time, on Albumi
    /// and on the screen that says a voice is safe.
    ///
    /// Only where there is something to buy, as for the card: without a key
    /// the paywall would be a dead button.
    ///
    /// And on a grandparent's phone as well, which is where this parts from
    /// the card. The ceiling is the family's — `quota.ts` counts it per
    /// family, not per phone — so the wall is the same on every phone, and
    /// since 26 Sep 2026 so is the way past it. The card is a sale after a
    /// telling; this is the answer to a wall somebody has just met, and on
    /// the phone of the one who does most of the telling, a wall with
    /// nothing beside it says only that there is no way up. It was hidden
    /// there for part of that day, on the card's reasoning, and put back.
    ///
    /// `onGrandparentsPhone` is handed in and not read. The views say whose
    /// phone it is and this decides what that means, as `card` does, so the
    /// answer for her phone is written once, where
    /// `scripts/upsell-rhythm-check.swift` holds it, rather than in the three
    /// views that ask.
    static func offersPurchaseAtCeiling(onGrandparentsPhone: Bool, canPurchase: Bool) -> Bool {
        canPurchase
    }

    /// Whether the slot shows, given what it would hold.
    ///
    /// The paid archive keeps the rhythm above: one in three, never against a
    /// name. The invitation does not. It is not an offer to buy something but
    /// the product's second user — and, for a family of one, the only other
    /// holder of the key that the whole archive rests on (docs/PLAN.md §10
    /// lever 3). On the shared rhythm it was hidden whenever a telling
    /// proposed names, which a telling about relatives does every time, so a
    /// founder who told about the family never saw it (founder's-eye review,
    /// 3 Sep 2026, finding #41). So the invitation shows on every finished
    /// telling of a family of one — but only once the names are answered:
    /// rule 1 above is kept to the letter, by waiting rather than by hiding.
    /// `proposalsRemaining` is the live count, not the one the rhythm saw.
    static func slotShows(card: Card?, rhythm: Bool, proposalsRemaining: Bool) -> Bool {
        switch card {
        case .invite: !proposalsRemaining
        case .archive: rhythm
        case nil: false
        }
    }
}
