import SwiftUI

/// The family's members and the invite link.
///
/// The invite link is the entire security boundary: anyone who receives it sees
/// all of the family's memories. That is why this screen shows who has joined
/// and how many people have used the link — it is the only visibility into that
/// boundary.
struct FamilyScreen: View {
    @Environment(Session.self) private var session
    @Environment(MemoryStore.self) private var store
    @Environment(SyncEngine.self) private var sync: SyncEngine?

    @State private var isShowingPaywall = false
    /// A revocation the server did not hear. The row staying put is passively
    /// honest, but the person just did the one deliberate thing the boundary
    /// offers, and a failure that looks like nothing happening is the answer
    /// the leave-family screen already refuses to give.
    @State private var revokeFailed = false

    var body: some View {
        List {
            if let family = session.family {
                // Every header on this screen says its colour out loud. The
                // "Kutsut" header below learned this first and its comment
                // believed it was the last bare one — it was only the last
                // *measured* one. The first audit of this screen's top reported
                // "Käyttö" and "Jäsenet" at once; "Perhe" survives today only
                // because it sits inside the navigation bar's forgiveness band,
                // which is a place, not a colour.
                Section {
                    // The values are written out rather than handed to
                    // `LabeledContent(_:value:)`: that initialiser draws them in
                    // the framework's own grey, which measured 3.44:1 on this
                    // screen at the largest text size — under the minimum, on
                    // the rows people come here to read. The same framework
                    // default rule 1 already bans as `.secondary`; the audit
                    // never met these rows because the family test scrolls past
                    // them to the invites.
                    LabeledContent("Nimi") {
                        Text(family.name)
                            .foregroundStyle(Elder.supporting)
                    }
                    LabeledContent("Tila") {
                        Text(family.entitlement == "archive" ? "Maksullinen" : "Ilmainen")
                            .foregroundStyle(Elder.supporting)
                    }
                    // The same fact as the note on Muistot, in the place
                    // somebody comes to when they want to check rather than to
                    // be told: with a time on it, and shown even when there is
                    // nothing waiting — "kaikki lähetetty" is the answer to the
                    // question, not the absence of one.
                    LabeledContent("Lähetys") {
                        Text(syncText)
                            .foregroundStyle(Elder.supporting)
                    }
                } header: {
                    Text("Perhe")
                        .foregroundStyle(Elder.supporting)
                }

                if let usage = session.usage {
                    Section {
                        // Not "AI-minuutit". The same quota is called "kertomista
                        // tässä kuussa jäljellä" where somebody actually meets
                        // it — on the card after a telling — and one of the two
                        // names is jargon aimed at the person least able to
                        // decode it. The app should have one word for one thing.
                        LabeledContent("Kertominen tässä kuussa") {
                            Text(usage.aiSeconds.limit == nil
                                ? "rajaton"
                                : "\(usage.aiSeconds.used / 60) / \(usage.aiSeconds.limit! / 60) min")
                                .foregroundStyle(Elder.supporting)
                        }
                        LabeledContent("Kuvat") {
                            Text(usage.photos.limit == nil
                                ? "rajaton"
                                : "\(usage.photos.used) / \(usage.photos.limit!)")
                                .foregroundStyle(Elder.supporting)
                        }

                        // The second way in. The first is the moment a memory
                        // finishes, which is where value peaks — but a
                        // grandchild who came here to look at the limits should
                        // not have to go and dictate something to find this.
                        if !usage.isPaid, RevenueCatPurchases.configuredKey != nil {
                            Button {
                                isShowingPaywall = true
                            } label: {
                                Label("Avaa koko arkisto", systemImage: "sparkles")
                                    .font(.body.weight(.semibold))
                                    .elderTapTarget()
                            }
                        }
                    } header: {
                        Text("Käyttö")
                            .foregroundStyle(Elder.supporting)
                    }
                }

                Section {
                    ForEach(family.members) { member in
                        MemberRow(member: member, isYou: member.id == family.you.id)
                    }
                } header: {
                    Text("Jäsenet")
                        .foregroundStyle(Elder.supporting)
                }

                Section {
                    // Shared with the finished-memory screen's offer card, so
                    // the two doors hand out the same invitation. See
                    // `InviteShareButton`.
                    InviteShareButton()

                    ForEach(family.invites) { invite in
                        InviteRow(invite: invite) {
                            Task {
                                if await !session.revokeInvite(code: invite.code) {
                                    revokeFailed = true
                                }
                            }
                        }
                    }

                    // A row rather than a footer — the fourth time this app has
                    // had to make that move, after two toolbar buttons and the
                    // guessing card's way out.
                    //
                    // §4 calls the invite link the entire security boundary, and
                    // this is the sentence that says so. As a `List` footer it
                    // was drawn in the framework's own grey, which measures
                    // about 4.2:1 and is under the minimum; it was capped so it
                    // could not grow with Dynamic Type at all — "unsupported",
                    // not "partially"; and it was clipped. Three findings on one
                    // sentence, on the first run that could reach this screen.
                    //
                    // As an ordinary row it is `Elder.supporting` at 6.6:1 and
                    // scales like any other body text. The sentence that decides
                    // who sees a family's memories should not be the faintest,
                    // smallest, most truncated thing on the screen.
                    Text("Kutsu on voimassa viikon. Kuka tahansa linkin saanut näkee perheen kaikki muistot, joten jaa se vain niille joille se kuuluu.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                } header: {
                    // Said out loud, like every other header in Settings. A
                    // `List` styles its own headers below the contrast minimum,
                    // and this one was the last bare `Text` left on the screen —
                    // the audit had it at "nearly passed", which is a fail with
                    // a kind word. It sits directly above the row that explains
                    // who can see the family's memories.
                    Text("Kutsut")
                        .foregroundStyle(Elder.supporting)
                }
            } else {
                Section {
                    // The family details are not a precondition for use:
                    // membership is local state and the app works offline.
                    Label("Perheen tietoja ei saatu haettua", systemImage: "wifi.slash")
                        .foregroundStyle(Elder.supporting)
                    // Concrete when there is something concrete to say. This is
                    // the screen somebody opens *because* they are worried, and
                    // the general reassurance was the only thing here — while
                    // the app knew exactly how many tellings were still waiting.
                    Text(offlineText)
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                }
            }
        }
        .navigationTitle("Perhe")
        .alert("Kutsua ei voitu perua", isPresented: $revokeFailed) {
            Button("Selvä", role: .cancel) {}
        } message: {
            Text(session.lastError ?? "Kutsu on yhä voimassa. Yritä uudelleen, kun verkkoyhteys toimii.")
        }
        // Room under the last row for the floating tab bar.
        //
        // iOS 26's bar is a capsule that content scrolls beneath, and at the
        // bottom of a list there is nothing left to scroll: the final line of
        // the invite footer — *"…joten jaa se vain niille joille se kuuluu"*,
        // which is the sentence that explains the whole security boundary —
        // ended underneath it with no way to bring it out. Measured at 61.7 pt
        // of text whose frame stopped exactly at the bar's edge, on the first
        // run that could reach this screen at all.
        .contentMargins(.bottom, Elder.minTapTarget, for: .scrollContent)
        .task { await session.refresh() }
        .refreshable { await session.refresh() }
        .paywallSheet(isPresented: $isShowingPaywall)
    }

    /// What the sync has actually managed, in one line.
    ///
    /// The waiting case wins over the clock: a time from an hour ago beside
    /// three memories that never left would be a true sentence answering the
    /// wrong question.
    private var syncText: String {
        let waiting = store.waitingToBeSent
        if sync?.state == .syncing { return "lähetetään…" }
        // The one sync state whose waiting never ends by itself. The likely
        // cause is the shared Keychain: emptying another phone on the same
        // Apple ID renews the identity there and takes this one's with it.
        if sync?.state == .refused {
            return "lähetys ei onnistu — palvelin ei tunnistanut tätä laitetta"
        }
        if waiting > 0 { return waiting == 1 ? "1 odottaa verkkoa" : "\(waiting) odottaa verkkoa" }
        guard let at = sync?.lastSyncedAt else { return "kaikki lähetetty" }
        return "kaikki lähetetty \(Self.moment(at))"
    }

    /// The same thing said where the family details could not be fetched at all.
    private var offlineText: String {
        switch store.waitingToBeSent {
        // "Lähtevät itsestään", not "synkronoituvat" — the two branches below
        // this one have said it plainly all along, in the same property, and
        // the app has one word for this everywhere else it comes up: the
        // Lähetys row, "kaikki lähetetty", "odottaa lähetystä". A person who
        // has just been told the connection is gone should not have to decode
        // a verb from someone else's trade. See docs/ARCHITECTURE.md §21.
        case 0: "Voit silti kertoa muistoja. Ne lähtevät itsestään kun yhteys palaa."
        case 1: "Yksi kertomasi muisto odottaa lähetystä. Se lähtee itsestään kun yhteys palaa."
        case let waiting: "\(waiting) kertomaasi muistoa odottaa lähetystä. Ne lähtevät itsestään kun yhteys palaa."
        }
    }

    /// A time of day for today and a date for anything older. Nobody needs the
    /// year of a sync, and "12.8. klo 9.05" is read at a glance.
    private static func moment(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fi_FI")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'klo' H.mm" : "d.M. 'klo' H.mm"
        return formatter.string(from: date)
    }

}

private struct MemberRow: View {
    let member: Session.Member
    let isYou: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Decoration: the row says "Perustaja" or "Jäsen" in words right
            // beside it. Left visible to VoiceOver it read out
            // "person.crop.circle.badge.checkmark" — the symbol's own name, in
            // English, in the middle of a Finnish family list, which is the same
            // defect the onboarding mark had. Nothing had ever caught this one
            // because nothing could reach this screen (`-seed family`).
            Image(systemName: member.role == "owner" ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(Elder.supporting)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "\(member.displayName) (sinä)" : member.displayName)
                    .font(.body.weight(.medium))
                // The date is half of what this list is for. §4 calls the invite
                // link the entire security boundary and names four things that
                // hold it up, one of them being that the family can see who has
                // joined **and when** — the server has always sent it and the
                // row has always decoded it, and nothing showed it. A stranger
                // in the list is a question; a stranger who arrived last Tuesday
                // is an answer about which link went astray and when.
                Text("\(member.role == "owner" ? "Perustaja" : "Jäsen") · \(Self.joined(member.joinedAt))")
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    /// A plain Finnish date. Not "2 viikkoa sitten": the question this answers
    /// is which day somebody appeared, and a relative phrase makes the reader do
    /// the arithmetic.
    private static func joined(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fi_FI")
        formatter.dateFormat = "d.M.yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

private struct InviteRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let invite: Session.Invite
    let onRevoke: () -> Void

    private var expiryText: String {
        // Ceiling, not truncation: a just-created week-long invite read
        // "vanhenee 6 päivän päästä" directly above the row promising
        // "voimassa viikon" — a one-day contradiction on the screen that
        // exists so numbers can be checked.
        let days = Int(ceil((invite.expiresAt - Date().timeIntervalSince1970) / 86_400))
        if days <= 0 { return "vanhenee tänään" }
        return days == 1 ? "vanhenee huomenna" : "vanhenee \(days) päivän päästä"
    }

    /// Side by side normally, stacked at accessibility sizes.
    ///
    /// The button keeps a third of the row's width whatever the text does, so at
    /// XXXL what is left for the words is a column about six characters wide:
    /// *"Käytet-"* / *"ty 2"* / *"kertaa"*, hyphenated down the side of a lone
    /// *"Poista"*. Nothing clipped and the audit was content — it measures
    /// contrast, growth and targets, not whether a sentence has been shredded —
    /// so this one had to be looked at.
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                description
                button
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                description
                Spacer()
                button
            }
            .padding(.vertical, 4)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(invite.usedCount == 0
                ? "Avoin kutsu"
                : "Käytetty \(invite.usedCount) kertaa")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(expiryText)
                .font(.caption)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var button: some View {
            // "Poista", not "Mitätöi". The app has one word for taking a thing
            // away and it is this one — "Poista tämä muisto", "Poista Aino",
            // "Poistetaanko sukulaisuus?" — and *mitätöidä* is the register of
            // an authority annulling a document, which is not the register of
            // anything else this app says. The row beside it already says what
            // is being removed. See docs/ARCHITECTURE.md §21.
            Button("Poista", role: .destructive, action: onRevoke)
                .font(.subheadline.weight(.medium))
                // `role: .destructive` draws the label in iOS's own red, and
                // **measured off this screen it is rgb(255, 56, 60) — 3.57:1
                // against the row, under the 4.5:1 minimum**. That is the number
                // `Elder.destructive` exists to replace, and this is the app's
                // only inline destructive label that was still the system's:
                // everywhere else the role appears it is inside a swipe action
                // or a system dialog, which iOS draws and we do not.
                //
                // The audit does not catch it. It passed this screen twice
                // before the pixels were counted, which is worth knowing about
                // the audit as much as about the button.
                .foregroundStyle(Elder.destructive)
                .elderTapTarget()
    }
}

#Preview {
    NavigationStack {
        FamilyScreen()
            .environment(Session())
            .environment(MemoryStore(filename: "preview-store.json"))
    }
}
