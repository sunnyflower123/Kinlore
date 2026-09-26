import SwiftUI

/// The invitation, from tap to share sheet, in one implementation.
///
/// Two screens offer it — the family view, and the finished-memory screen's
/// offer slot while the family is one person (docs/UX.md §3.2) — and they must
/// produce the same invitation: the same code, the same key, the same words
/// around them. The button opens a small sheet that asks who the invitation is
/// for, makes the code with that name on it, and hands the text to the system
/// share sheet.
///
/// Unstyled on purpose: the family view shows it as an ordinary row and the
/// offer card makes it prominent, and `buttonStyle` reaches it from either
/// call site. §22's one-blue-button rule is decided where the button is
/// placed, not here.
struct InviteShareButton: View {
    @Environment(Session.self) private var session

    /// The words on the button. The first minute answers its own question
    /// with it — "Omalla puhelimellaan" beside "Tällä puhelimella" — and every
    /// other screen keeps the button as it always was.
    var title: LocalizedStringKey = "Kutsu perheenjäsen"

    /// Whom the invitation starts out made to, when the screen offering it
    /// already knows — the first minute's "whose memories" has just been
    /// answered. Empty everywhere else, which is the button as it always was.
    var suggestedName = ""

    /// The card the invitation is made for, when the screen offering it has
    /// one — the first minute's, again. Whoever joins through the code is
    /// linked to it, so the grandmother who opens the link becomes the card
    /// her grandchild made. Nil everywhere else.
    var personSubjectID: String? = nil

    @Environment(SyncEngine.self) private var sync: SyncEngine?

    @State private var name = ""
    @State private var code: String?
    @State private var isSharing = false
    @State private var couldNotCreate = false
    /// From the tap until the code is back. Longer than `session.isWorking`,
    /// which starts only once the card the invitation names has been pushed.
    @State private var isCreating = false

    var body: some View {
        Button {
            // No network here any more. The sheet asks who the invitation is
            // for, and the code is made once that is answered — a code made
            // before the question could not carry the answer.
            name = suggestedName
            isSharing = true
        } label: {
            Label(title, systemImage: "person.badge.plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        }
        .alert("Kutsua ei voitu luoda", isPresented: $couldNotCreate) {
            Button("Selvä", role: .cancel) {}
        } message: {
            Text(session.lastError ?? String(localized: "Yritä uudelleen, kun verkkoyhteys toimii."))
        }
        .sheet(isPresented: $isSharing, onDismiss: reset) { sheet }
    }

    /// Two states, in the order the acts happen: name the person, then share it.
    ///
    /// The naming step is added to the inviter's path in order to take a step
    /// off the joiner's, and that trade is the whole point — the inviter is a
    /// grandchild with a keyboard, and the joiner is the person rule 1 is
    /// about. It is skippable: an invitation with nobody's name on it is what
    /// this button made until now, and it still works.
    ///
    /// **No `presentationDetents`, which is a fix and not an omission.** The
    /// sheet was `.medium` while its whole content was one share row; a title,
    /// a field, a paragraph and a button do not fit in half a screen, and the
    /// audit did not report them as overflowing — it reported the title, the
    /// paragraph and the button as *clipped*, and the paragraph as failing
    /// contrast, which reads like three unrelated styling defects and was one
    /// squeezed sheet. Full height, like `AskQuestionSheet`, which met the same
    /// wall first.
    @ViewBuilder
    private var sheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let code {
                    Text("Kutsu on valmis")
                        .font(Elder.display(.title2))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Lähetä se viestillä sille, jolle kutsun teit. Linkki toimii viikon ja päästää sisään yhden ihmisen.")
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)

                    ShareLink(item: Self.inviteText(code: code)) {
                        Label("Jaa kutsu", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    // The 60 pt minimum belongs to the control and not to the
                    // label inside it: applied to the label it fights the
                    // button style over the box the text goes in, and the
                    // audit reports the label as clipped. `AskQuestionSheet`
                    // records the same lesson at length.
                    .buttonStyle(.borderedProminent)
                    .elderTapTarget()

                    Spacer()

                    Button("Valmis") { isSharing = false }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                } else {
                    Text("Kenelle kutsu menee?")
                        .font(Elder.display(.title2))
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Nimi", text: $name)
                        .textInputAutocapitalization(.words)
                        .font(.body)
                        .padding(12)
                        .elderCard(radius: 16)

                    // Says what the name buys, because otherwise it reads as
                    // one more field to fill in — and the whole reason it is
                    // here is that somebody else does not have to fill one in.
                    Text("Nimi näkyy hänen muistojensa vieressä. Kun kirjoitat sen tähän, hänen ei tarvitse kirjoittaa mitään liittyessään.")
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        isCreating = true
                        Task {
                            // The card goes along only while the name is still
                            // the one it was offered under: an invitation
                            // renamed to somebody else is for somebody else,
                            // and linking them to her card would put the wrong
                            // person in the tree.
                            let card = isStillForTheCard ? personSubjectID : nil
                            // Up before the invitation names it, so that the
                            // join finds the card and links her there and
                            // then. A join survives a card that has not
                            // arrived, and her phone links itself later; this
                            // is what keeps that the rare case.
                            if card != nil { await sync?.syncAfterRoundInFlight() }
                            code = await session.createInvite(displayName: name, personSubjectID: card)
                            isCreating = false
                            if code == nil {
                                // Said out loud, on the path to the product's
                                // second user. A spinner that returns to a
                                // resting button is a refusal that looks like
                                // nothing happening — the shape the
                                // leave-family screen names as the worst
                                // possible answer to a deliberate act.
                                isSharing = false
                                couldNotCreate = true
                            }
                        }
                    } label: {
                        if session.isWorking || isCreating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Luo kutsu")
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .elderTapTarget()
                    .disabled(session.isWorking || isCreating)

                    Spacer()

                    // A row rather than a toolbar button: a toolbar button's
                    // text barely grows with Dynamic Type, which would put the
                    // way out of this screen in the smallest text on it.
                    Button("Peruuta") { isSharing = false }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
            }
            .padding(Elder.screenPadding)
            .navigationTitle("Kutsu")
            .navigationBarTitleDisplayMode(.inline)
            // The ground only. Everything else this sheet is owed — the serif
            // on "Kutsu on valmis", the code at a size somebody can read
            // across a kitchen table — is phase E and is not this commit's.
            // The paper is, because a white sheet in a parchment app is a
            // screen that looks broken rather than unfinished, and this one is
            // in a take.
            .elderSurface()
        }
    }

    /// Whether the name in the sheet is still the one the card was offered
    /// under. Case and surrounding spaces do not make it somebody else.
    private var isStillForTheCard: Bool {
        let offered = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(offered) == .orderedSame
    }

    /// A dismissed sheet starts over. A code left behind would be shared to
    /// whoever the next invitation was for, under the previous one's name.
    private func reset() {
        code = nil
        name = ""
    }

    /// The shared text contains both the link and the code. The link is quick,
    /// but the code works even when the messaging app does not make the link
    /// tappable — and grandmother cannot be asked to work out why a link will
    /// not open.
    ///
    /// **Both halves carry the family key since PLAN.md §10 lever 3**, joined
    /// to the invite code by `#`. They have to be the same string: the paste
    /// field exists so that somebody who cannot open a link can still get in,
    /// and a fallback that produced a member who could not read anything would
    /// be worse than no fallback.
    ///
    /// This is also where the honesty about lever 3 has to be stated, because
    /// it is the one thing about it a user could be misled by. The server
    /// never sees this key — that is the whole design — but **whatever carried
    /// this message did.** Sending it over a chat app puts the key wherever
    /// that app keeps it. It is still a large improvement on the archive
    /// itself being readable in a dump, and it is not the same claim as
    /// end-to-end.
    ///
    /// **Each sentence is looked up on its own, in the inviter's language.**
    /// Until 26 Sep 2026 this was one `"""` literal, which is a `String` and
    /// never a key, so an English phone shared its invitation in Finnish. The
    /// link and the code are not words and stay outside every lookup, so no
    /// translation can touch the line `code(inPasted:)` finds the code on.
    /// And the message now says what joining takes before anybody tries: an
    /// iPhone and the app. Somebody on another phone used to find out from a
    /// link that did nothing.
    static func inviteText(code: String) -> String {
        let shared = FamilyKey.shareable().map { "\(code)#\($0)" } ?? code
        let join = String(localized: "Liity perheen muistoarkistoon:")
        let needs = String(localized: "Tarvitset iPhonen ja Kinloren.")
        let open = String(localized: "Puhelin voi kysyä englanniksi luvan avata Kinlore — vastaa \"Open\".")
        let orPaste = String(localized: "Tai avaa sovellus ja liitä tämä koodi:")
        return """
        \(join)
        kinlore://join?code=\(shared)

        \(needs) \(open)

        \(orPaste)
        \(shared)
        """
    }
}
