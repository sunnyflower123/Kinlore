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
            Text("\(round.memory.authorName) kertoi tämän")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)

            Text(round.maskedBody)
                .elderBody()
                .lineLimit(previewLines)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            Label("Kuka hän oli?", systemImage: "person.crop.circle.badge.questionmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
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

    @State private var chosen: Subject?
    @State private var isTelling = false

    private var isRevealed: Bool { chosen != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(round.memory.authorName) kertoi:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)

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

                    if let chosen {
                        reveal(chosen: chosen)
                    } else {
                        options
                    }
                }
                .padding(Elder.screenPadding)
            }
            .navigationTitle("Kuka hän oli?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isRevealed ? "Valmis" : "Sulje") { dismiss() }
                }
            }
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
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // Not knowing is an ordinary answer, and for the person this app is
            // built for it is the most likely one. Without this button the only
            // way out of the screen is a wrong answer.
            Button {
                dismiss()
            } label: {
                Text("En muista")
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func reveal(chosen: Subject) -> some View {
        let isCorrect = chosen.id == round.answer.id

        VStack(alignment: .leading, spacing: 16) {
            // Shape and word carry the result, not colour alone — the user of
            // this app is precisely the one who cannot rely on colour.
            Label(
                isCorrect ? "Oikein. Hän oli \(round.answer.displayTitle)." : "Hän oli \(round.answer.displayTitle).",
                systemImage: isCorrect ? "checkmark.circle.fill" : "person.crop.circle"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(isCorrect ? Color.green : Color.primary)
            .fixedSize(horizontal: false, vertical: true)

            // A wrong guess is stated plainly and left alone. No "väärin", no
            // red: the person guessing may be the one whose memory is going.
            if !isCorrect {
                Text("Sinä arvasit: \(chosen.displayTitle).")
                    .elderBody()
                    .foregroundStyle(.secondary)
            }

            if let others = othersText {
                Text(others)
                    .elderBody()
                    .foregroundStyle(.secondary)
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
    /// hearing that the family knew who she meant.
    private var othersText: String? {
        let names = store.guesses(for: round.memory.id)
            .filter { $0.memberID != session.identity.memberID && $0.subjectID == round.answer.id }
            .map(\.memberName)
        guard !names.isEmpty else { return nil }
        if names.count == 1 { return "\(names[0]) tunnisti hänet myös." }
        return "\(names.count) muuta perheenjäsentä tunnisti hänet."
    }

    private func choose(_ option: Subject) {
        chosen = option
        store.record(
            Guess(
                memoryID: round.memory.id,
                memberID: session.identity.memberID,
                subjectID: option.id,
                memberName: store.authorName
            ),
            answer: round.answer
        )
    }
}
