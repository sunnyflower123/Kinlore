import SwiftUI

/// The family's members and the invite link.
///
/// The invite link is the entire security boundary: anyone who receives it sees
/// all of the family's memories. That is why this screen shows who has joined
/// and when, which invitations are still open and for whom — and, since 5 Sep
/// 2026, gives the owner the one remedy for a link that went astray: *"Poista
/// perheestä"* on every row but their own. It is the only visibility into that
/// boundary, and the only hand on it.
///
/// Every sentence here that used to be a computed `String` property is a
/// `Text` with a literal key now, because a `String` is never looked up. This
/// screen showed *"Käytetty 2 kertaa"* and *"kaikki lähetetty klo 9.05"* on an
/// English phone (founder's-eye review, 3 Sep 2026, finding #38), and neither
/// had a key: the first sat in a ternary, where `localisation-check.mjs` does
/// not look, and the second was a `String` as well.
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
    /// The member the owner is about to remove, while the dialog asks.
    @State private var removing: Session.Member?
    @State private var isConfirmingRemoval = false
    @State private var removeFailed = false
    @State private var isRenamingSelf = false

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
                        Group {
                            if family.entitlement == "archive" {
                                Text("Maksullinen")
                            } else {
                                Text("Ilmainen")
                            }
                        }
                        .foregroundStyle(Elder.supporting)
                    }
                    // The same fact as the note on Muistot, in the place
                    // somebody comes to when they want to check rather than to
                    // be told: with a time on it, and shown even when there is
                    // nothing waiting — "kaikki lähetetty" is the answer to the
                    // question, not the absence of one.
                    LabeledContent("Lähetys") {
                        syncText
                            .foregroundStyle(Elder.supporting)
                    }
                    // The other direction: the family's photographs and voices
                    // on this phone, so the phone is a copy of the archive and
                    // not a window onto one. See `FullCopy` and
                    // docs/RECOVERY.md. Said with a number, because a copy that
                    // never started looks exactly like one that is complete.
                    // The sentence explaining it lives on the help page under
                    // "Jos puhelin katoaa", where the rest of that story is.
                    if let copy = sync?.fullCopy {
                        LabeledContent("Kopio tällä puhelimella") {
                            copyText(copy)
                                .foregroundStyle(Elder.supporting)
                        }
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
                        // One `Text` each, chosen in a helper, rather than a
                        // `Group` holding an if/else: two views for one value
                        // gave the audit's default-size simulation a label
                        // to stumble on — see `minutesText`.
                        LabeledContent("Kertominen tässä kuussa") {
                            minutesText(usage)
                                .foregroundStyle(Elder.supporting)
                        }
                        LabeledContent("Kuvat") {
                            photosText(usage)
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
                        MemberRow(
                            member: member,
                            isYou: member.id == family.you.id,
                            // The owner's remedy for a link that went astray,
                            // on every row but their own: leaving is their own
                            // road, and it knows how to hand ownership on.
                            onRemove: family.you.role == "owner" && member.id != family.you.id
                                ? { removing = member; isConfirmingRemoval = true }
                                : nil
                        )
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
                    Text("Kutsu on voimassa viikon ja päästää sisään yhden ihmisen. Kuka tahansa linkin saanut näkee perheen kaikki muistot, joten lähetä se vain sille, jolle sen teit.")
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
                    offlineText
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                }
            }
        }
        .navigationTitle("Perhe")
        .alert("Kutsua ei voitu perua", isPresented: $revokeFailed) {
            Button("Selvä", role: .cancel) {}
        } message: {
            Text(session.lastError ?? String(localized: "Kutsu on yhä voimassa. Yritä uudelleen, kun verkkoyhteys toimii."))
        }
        // Confirmed, like every other removal in this app: it cannot be undone
        // from here, and the person holding the phone may be 80. The message
        // says the two things that are not obvious — what they told stays, and
        // the open invitations go, because the invite text carries the family
        // key and the person being removed may hold any live link.
        //
        // **An alert, not a `confirmationDialog`, and that was measured.** This
        // was first written as a confirmation dialog like every other removal
        // in the app, and the sweep's tap on *"Peruuta"* found no such button:
        // on iOS 26 the dialog comes up as a popover anchored to the top of the
        // list (`app.popovers.count == 1`, 240 pt wide, under the navigation
        // bar), and a popover adaptation draws no cancel action at all. The
        // sheet held "Poista perheestä" and nothing else; the only way out was
        // a tap in the dimmed area beside it. Screenshotted 5 Sep 2026 on the
        // Settings screen's own "Poistutaanko perheestä?", which presents the
        // same way — so this is every confirmation in the app, not this one.
        // An alert draws both buttons, and the way out is the one an
        // 80-year-old can see.
        .alert(
            "Poistetaanko \(removing?.displayName ?? "") perheestä?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Poista perheestä", role: .destructive) {
                guard let member = removing else { return }
                Task {
                    if await !session.removeMember(id: member.id) {
                        removeFailed = true
                    }
                }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("\(removing?.displayName ?? "") ei enää näe perheen muistoja eikä voi kertoa niitä. Hänen kertomansa muistot jäävät perheelle. Avoimet kutsut peruuntuvat samalla, joten tee uusi kutsu sille, jolle se kuuluu.")
        }
        // One's own name, changed — behind the pencil the person card uses
        // for "Korjaa nimi", so one symbol means one act across the app. Not
        // a row: the members list rests, at the default size, with its last
        // invite row twelve points above the tab bar, and one row's worth of
        // height on the owner's row put that row into the deep fade, measured
        // at 1.59:1 (6 Sep 2026). The bar's own item changes no geometry.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isRenamingSelf = true
                } label: {
                    Image(systemName: "pencil")
                        .elderTapTarget()
                }
                .accessibilityLabel("Vaihda nimi")
            }
        }
        .sheet(isPresented: $isRenamingSelf) {
            NameSheet(title: "Vaihda nimi", initial: session.family?.you.displayName ?? "") { name in
                await session.rename(displayName: name)
            }
        }
        .alert("Jäsentä ei voitu poistaa", isPresented: $removeFailed) {
            Button("Selvä", role: .cancel) {}
        } message: {
            Text(session.lastError
                ?? String(localized: "Hän on yhä perheessä. Yritä uudelleen, kun verkkoyhteys toimii."))
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
        .elderSurface()
    }

    /// What the sync has actually managed, in one line.
    ///
    /// The waiting case wins over the clock: a time from an hour ago beside
    /// three memories that never left would be a true sentence answering the
    /// wrong question.
    private var syncText: Text {
        let waiting = store.waitingToBeSent
        if sync?.state == .syncing { return Text("lähetetään…") }
        // The one sync state whose waiting never ends by itself. The likely
        // cause is the shared Keychain: emptying another phone on the same
        // Apple ID renews the identity there and takes this one's with it.
        if sync?.state == .refused {
            return Text("lähetys ei onnistu — palvelin ei tunnistanut tätä laitetta")
        }
        // The other: no round runs without the family's key (`SyncSeal`).
        if sync?.state == .keyMissing {
            return Text("lähetys ei onnistu — tästä laitteesta puuttuu perheen avain")
        }
        if waiting > 0 {
            return waiting == 1 ? Text("1 odottaa verkkoa") : Text("\(waiting) odottaa verkkoa")
        }
        guard let at = sync?.lastSyncedAt else { return Text("kaikki lähetetty") }
        // A time of day for today and a date for anything older; nobody needs
        // the year of a sync. The phone's own locale spells both — it was a
        // fixed `fi_FI` formatter writing "klo" into an English screen.
        if Calendar.current.isDateInToday(at) {
            return Text("kaikki lähetetty klo \(at.formatted(date: .omitted, time: .shortened))")
        }
        return Text("kaikki lähetetty \(at.formatted(date: .numeric, time: .shortened))")
    }

    /// The month's telling, as one `Text`.
    private func minutesText(_ usage: EntitlementClient.Usage) -> Text {
        guard let limit = usage.aiSeconds.limit else { return Text("rajaton") }
        return Text("\(usage.aiSeconds.used / 60) / \(limit / 60) min")
    }

    private func photosText(_ usage: EntitlementClient.Usage) -> Text {
        guard let limit = usage.photos.limit else { return Text("rajaton") }
        return Text("\(usage.photos.used) / \(limit)")
    }

    /// How far the copy has got, and if it stopped, why — in the words of the
    /// rules in `FullCopy`.
    private func copyText(_ copy: FullCopy) -> Text {
        let have = copy.progress.have
        let total = copy.progress.total
        if total == 0 { return Text("ei vielä kuvia eikä ääniä") }
        if copy.isRunning { return Text("haetaan, \(have) / \(total)") }
        if copy.progress.isComplete { return Text("kaikki tallessa") }
        switch copy.halt {
        case .expensiveNetwork: return Text("\(have) / \(total), odottaa wifi-yhteyttä")
        case .lowDisk: return Text("\(have) / \(total), puhelimessa ei ole tilaa")
        case .failures: return Text("\(have) / \(total), jatkuu kun yhteys palaa")
        case .none: return Text("\(have) / \(total)")
        }
    }

    /// The same thing said where the family details could not be fetched at all.
    private var offlineText: Text {
        switch store.waitingToBeSent {
        // "Lähtevät itsestään", not "synkronoituvat" — the two branches below
        // this one have said it plainly all along, in the same property, and
        // the app has one word for this everywhere else it comes up: the
        // Lähetys row, "kaikki lähetetty", "odottaa lähetystä". A person who
        // has just been told the connection is gone should not have to decode
        // a verb from someone else's trade. See docs/ARCHITECTURE.md §21.
        case 0: Text("Voit silti kertoa muistoja. Ne lähtevät itsestään kun yhteys palaa.")
        case 1: Text("Yksi kertomasi muisto odottaa lähetystä. Se lähtee itsestään kun yhteys palaa.")
        case let waiting: Text("\(waiting) kertomaasi muistoa odottaa lähetystä. Ne lähtevät itsestään kun yhteys palaa.")
        }
    }

}

private struct MemberRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let member: Session.Member
    let isYou: Bool
    /// Present on the rows the owner may remove: everybody but themselves.
    let onRemove: (() -> Void)?

    /// Side by side normally, stacked at accessibility sizes — the same shape
    /// as `InviteRow` below, for the same reason: a button that keeps a third
    /// of the row leaves a name six characters wide at XXXL.
    var body: some View {
        if let onRemove, typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                description
                removeButton(onRemove)
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                description
                if let onRemove {
                    Spacer()
                    removeButton(onRemove)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var description: some View {
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
                Group {
                    if isYou {
                        Text("\(member.displayName) (sinä)")
                    } else {
                        Text(member.displayName)
                    }
                }
                .font(.body.weight(.medium))
                // The date is half of what this list is for. §4 calls the invite
                // link the entire security boundary and names four things that
                // hold it up, one of them being that the family can see who has
                // joined **and when** — the server has always sent it and the
                // row has always decoded it, and nothing showed it. A stranger
                // in the list is a question; a stranger who arrived last Tuesday
                // is an answer about which link went astray and when.
                Text("\(roleName) · \(Self.joined(member.joinedAt))")
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Looked up on each branch. A ternary of two literals inside the
    /// interpolation above was a String, and "Perustaja" reached an English
    /// screen as it was.
    private var roleName: String {
        member.role == "owner" ? String(localized: "Perustaja") : String(localized: "Jäsen")
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button("Poista perheestä", role: .destructive, action: action)
            .font(.subheadline.weight(.medium))
            // The system's destructive red measures 3.57:1 here; see the
            // invite row's button for the measurement.
            .foregroundStyle(Elder.destructive)
            .elderTapTarget()
            // Three rows may carry the same visible word. VoiceOver hears whose.
            .accessibilityLabel("Poista \(member.displayName) perheestä")
    }

    /// A plain date, in the phone's own numeric form. Not "2 viikkoa sitten":
    /// the question this answers is which day somebody appeared, and a relative
    /// phrase makes the reader do the arithmetic.
    ///
    /// Pinned to `fi_FI` and `d.M.yyyy` until 21 Sep 2026, a choice from before
    /// the app had a second language: an English phone read *"Founder ·
    /// 12.8.2026"*, which an American reads as the 8th of December. The
    /// phone's own form is *8/12/2026* there and exactly *12.8.2026* on a
    /// Finnish phone, so nothing a Finnish reader sees has changed.
    private static func joined(_ timestamp: Double) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .numeric, time: .omitted)
    }
}

private struct InviteRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let invite: Session.Invite
    let onRevoke: () -> Void

    private var expiryText: Text {
        // Ceiling, not truncation: a just-created week-long invite read
        // "vanhenee 6 päivän päästä" directly above the row promising
        // "voimassa viikon" — a one-day contradiction on the screen that
        // exists so numbers can be checked.
        let days = Int(ceil((invite.expiresAt - Date().timeIntervalSince1970) / 86_400))
        if days <= 0 { return Text("vanhenee tänään") }
        return days == 1 ? Text("vanhenee huomenna") : Text("vanhenee \(days) päivän päästä")
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
            // Whom the code was made for. A code admits one person, so
            // "käytetty 2 kertaa" is a sentence no row can say any more, and
            // two open codes are told apart by the name the inviter typed.
            Group {
                if let name = invite.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    Text("Kutsu: \(name)")
                } else {
                    Text("Kutsu ilman nimeä")
                }
            }
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            expiryText
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
