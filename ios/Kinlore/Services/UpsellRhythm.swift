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
    static func card(membersInFamily members: Int?, isPaid: Bool) -> Card? {
        guard let members else { return nil }
        if members <= 1 { return .invite }
        return isPaid ? nil : .archive
    }
}
