import SwiftUI

/// "Someone tells a story and the others guess who it was about."
///
/// This is the archive's reading loop. The writing loop already exists — an open
/// question is a reason to come back and tell something — but it asks for effort
/// from the family members who have the least of it. Guessing costs one tap, and
/// it makes an old memory worth opening a second time, which is the exact thing
/// family archives fail at.
///
/// It is also the confirmation UI for the people the AI proposed. See
/// `MemoryStore.record(_:answer:)` for why a blind guess counts for more than a
/// card with the answer already written on it.
///
/// No score, no streak, no timer, no leaderboard. These are memories of people
/// who have died; the payoff is that grandmother sees her sister was recognised,
/// not that somebody won.
struct GuessSection: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var playing: GuessRound?

    /// The card is a teaser, not the story — the whole text is on the next
    /// screen. At accessibility sizes four lines filled the phone and pushed
    /// "Kuka hän oli?" under the tab bar, so the card looked like a wall of text
    /// with no way in. Two lines is enough to make somebody curious.
    private var previewLines: Int {
        typeSize.isAccessibilitySize ? 2 : 4
    }

    /// One round at a time. A queue would turn the memories screen into a game
    /// feed, and this is not a game app.
    private var round: GuessRound? {
        GuessRoundBuilder.nextRound(store: store, memberID: session.identity.memberID)
    }

    /// The round on the card — or, while the sheet is open, the one being
    /// answered.
    ///
    /// The fallback is not decoration. Answering removes the round from `round`
    /// immediately, and this whole view disappears with it; the `.sheet` is
    /// attached here, so it would be torn out of the tree at the exact moment
    /// the reveal appeared. Holding the answered round keeps the section alive
    /// until the sheet is dismissed.
    private var visible: GuessRound? { playing ?? round }

    var body: some View {
        if let visible {
            VStack(alignment: .leading, spacing: 12) {
                Text("Muistatko kuka?")
                    .font(.title3.weight(.semibold))

                Button {
                    playing = visible
                } label: {
                    card(for: visible)
                }
                .buttonStyle(.plain)
            }
            .sheet(item: $playing) { round in
                GuessRoundSheet(round: round)
            }
        }
    }

    private func card(for round: GuessRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Not tinted. Blue on the card's grey passed the contrast audit only
            // "nearly", and nearly is not a pass for an 80-year-old's eyes. The
            // hierarchy is carried by weight and size instead, which is the same
            // rule the person list already follows: meaning never rides on
            // colour alone.
            Text("\(round.memory.authorName) kertoi tämän")
                .font(.subheadline.weight(.semibold))

            Text(round.maskedBody)
                .elderBody()
                .lineLimit(previewLines)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            // The whole card is the button, so the call to action does not need
            // to be blue to be tappable — and blue here failed the same contrast
            // check as the line above.
            Label("Kuka hän oli?", systemImage: "person.crop.circle.badge.questionmark")
                .font(.body.weight(.semibold))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(round.memory.authorName) kertoi tämän. \(spoken(round.maskedBody)). Kuka hän oli?"
        )
        .accessibilityHint("Avaa arvauksen")
    }

    /// VoiceOver reads a run of em dashes as punctuation or as nothing at all,
    /// and either way the gap — which is the entire question — disappears. Spoken
    /// aloud the sentence needs a word in the hole.
    private func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: GuessRoundBuilder.mask, with: "joku")
    }
}

// MARK: - The round

private struct GuessRoundSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let round: GuessRound

    /// Answered and what with. `chosen` stays nil for "En muista", which is an
    /// answer of its own — so the two have to be separate flags.
    @State private var isRevealed = false
    @State private var chosen: Subject?
    @State private var isTelling = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(round.memory.authorName) kertoi:")
                        .font(.subheadline.weight(.semibold))

                    // The story is shown in full, masked before the answer and
                    // whole after it. Seeing the sentence complete is the reward,
                    // and it is also the moment the memory gets read properly.
                    Text(isRevealed ? round.memory.body : round.maskedBody)
                        .elderBody()
                        .accessibilityLabel(
                            isRevealed
                                ? round.memory.body
                                : round.maskedBody.replacingOccurrences(
                                    of: GuessRoundBuilder.mask, with: "joku"
                                )
                        )

                    if isRevealed {
                        reveal
                    } else {
                        options
                    }

                    // A row rather than a toolbar button, which is the third
                    // time this app has had to make that move (AskQuestionSheet,
                    // CorrectNameSheet). A toolbar button's text barely grows
                    // with Dynamic Type — the audit calls it "partially
                    // unsupported" and it is right — so the way out of the
                    // screen was the smallest text on it. Nothing had measured
                    // this one: the audit stopped at the question and never
                    // opened the answer.
                    Button(isRevealed ? "Valmis" : "Sulje") { dismiss() }
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .padding(Elder.screenPadding)
            }
            .navigationTitle("Kuka hän oli?")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isTelling) {
                NavigationStack {
                    TellScreen(target: round.answer)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Sulje") { isTelling = false }
                            }
                        }
                }
            }
        }
    }

    private var options: some View {
        VStack(spacing: 12) {
            ForEach(round.options) { option in
                Button {
                    choose(option)
                } label: {
                    Text(option.displayTitle)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                        // A long name must wrap rather than truncate: half a
                        // name is not a choice anybody can make.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .elderTapTarget()
                        .background(
                            .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16)
                        )
                }
                // Not `.bordered`. That style writes its label in the accent
                // colour, and blue on its grey fill measured *below* the
                // contrast minimum on all four options at once — on the primary
                // controls of the screen, for the one user whose eyesight this
                // app is built around. `.plain` leaves the label the primary
                // colour and the fill still says "button".
                .buttonStyle(.plain)
            }

            // Not knowing is an ordinary answer, and for the person this app is
            // built for it is the most likely one. It reveals the answer like
            // any other, because learning who it was is the whole payoff — and
            // it is recorded, or this round would come back forever and stand in
            // front of every other one.
            //
            // No fill, so it does not compete with the four names, and no tint,
            // for the same contrast reason as above.
            Button {
                choose(nil)
            } label: {
                Text("En muista")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var reveal: some View {
        let isCorrect = chosen.map { $0.id == round.answer.id } ?? false

        VStack(alignment: .leading, spacing: 16) {
            // Shape and word carry the result, not colour alone — the user of
            // this app is precisely the one who cannot rely on colour.
            Label(
                isCorrect ? "Oikein. Hän oli \(round.answer.displayTitle)." : "Hän oli \(round.answer.displayTitle).",
                systemImage: isCorrect ? "checkmark.circle.fill" : "person.crop.circle"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(isCorrect ? Elder.affirmative : Color.primary)
            .fixedSize(horizontal: false, vertical: true)

            // A wrong guess is stated plainly and left alone. No "väärin", no
            // red: the person guessing may be the one whose memory is going.
            // "En muista" gets no line at all — there is nothing to report back
            // to someone who already said they did not know.
            if let chosen, !isCorrect {
                Text("Sinä arvasit: \(chosen.displayTitle).")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
            }

            if let others = othersText {
                Text(others)
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
            }

            // The point of the whole round: the person is now on screen and
            // somebody is thinking about them.
            Button {
                isTelling = true
            } label: {
                Label("Kerro sinäkin hänestä", systemImage: "mic.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// "Ville tunnisti hänet myös." The teller's reward is not a score but
    /// hearing that the family knew who she meant. The same rule as the memory
    /// card uses, asked of the store rather than reimplemented here — a merged
    /// person has to keep counting on both screens or on neither.
    private var othersText: String? {
        let names = store.recognisers(of: round.memory, excluding: session.identity.memberID)
        guard !names.isEmpty else { return nil }
        if names.count == 1 { return "\(names[0]) tunnisti hänet myös." }
        return "\(names.count) muuta perheenjäsentä tunnisti hänet."
    }

    /// `option` is nil for "En muista".
    private func choose(_ option: Subject?) {
        chosen = option
        isRevealed = true
        store.record(
            Guess(
                memoryID: round.memory.id,
                memberID: session.identity.memberID,
                subjectID: option?.id,
                memberName: store.authorName
            ),
            answer: round.answer
        )
    }
}
