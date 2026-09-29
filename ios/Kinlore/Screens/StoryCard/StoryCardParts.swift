import SwiftUI

/// The story's pieces on a card (ARCHITECTURE §27). `SubjectDetailScreen`
/// says where each goes and carries the state; these draw it.
///
/// Every colour is one Elder.swift already measures: the story is ink on
/// `card`, its notes are `supporting`, a button is ink on `honey`
/// (`elderSecondary`) or ink on the paper, and *Poista tarina* is
/// `destructive`. None of them uses the accent, which is the card's one wax
/// button, *Kerro tästä muisto*.

// MARK: - The story

/// The story's text, a paragraph at a time, with the `rule` hairline between
/// paragraphs: a story of three tellers reads as three voices, and the line
/// is where one hands over to the next.
struct StoryBody: View {
    let text: String

    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                if index > 0 {
                    Rectangle().fill(Elder.rule).frame(height: 1)
                        .accessibilityHidden(true)
                }
                // Verbatim: the story is the family's words, not a key.
                Text(verbatim: paragraph)
                    .elderBody()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storyCard.story")
    }
}

/// Under the story: where it came from, and the way to change it. The two
/// on one line while both fit on it whole, and the button under the words
/// at the accessibility sizes, where beside them it would be a column.
struct StoryProvenance: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let memoryCount: Int
    let edited: Bool
    let onEdit: () -> Void

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Group {
                if edited {
                    Text("Muokattu käsin")
                } else if memoryCount == 1 {
                    Text("Koottu yhdestä muistosta")
                } else {
                    Text("Koottu \(memoryCount) muistosta")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact` and
            // nothing else (29 Sep 2026), as are the three below.
            .accessibilityIdentifier("storyCard.provenance")
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            // Ink, like every text button since the accent became the red of
            // removal (`Elder.wax`).
            Button("Muokkaa tarinaa", action: onEdit)
                .buttonStyle(.borderless)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .elderTapTarget()
                .accessibilityIdentifier("storyCard.editStory")
        }
    }
}

/// A telling taken back from under a story a person corrected — here or on
/// another phone. The plan leaves an edited story alone (`StoryPlan.plan`),
/// so the card says what is gone and a person decides: keep the story as it
/// is, or let it go — composed again from what is still told, or deleted
/// when nothing is. Keeping is the honey button and asks nothing; either way
/// of letting go loses the person's own words, so each asks once more first
/// (rule 1: the safe answer is the easy one to hit).
struct StoryTakenBack: View {
    /// How many of the story's tellings are gone, of how many it was made.
    let gone: Int
    let of: Int
    /// Whether a story can be composed again at all: a telling is still on
    /// the card — the story's own remainder or one told since — and this
    /// phone composes. Otherwise the offer is to delete the story.
    let canCompose: Bool
    let onKeep: () -> Void
    let onLetGo: () -> Void

    @State private var isConfirmingRecompose = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if gone == of, of == 1 {
                    Text("Tarinan ainoa muisto on poistettu")
                } else if gone == of {
                    Text("Tarinan kaikki muistot on poistettu")
                } else if gone == 1 {
                    Text("Yksi tarinan muistoista on poistettu")
                } else {
                    Text("\(gone) tarinan muistoista on poistettu")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("storyCard.takenBack")
            Group {
                if canCompose {
                    Text("Tarina on muokattu käsin, joten sitä ei koota uudelleen itsestään. Voit pitää tarinan sellaisenaan tai koota sen uudelleen jäljellä olevista muistoista, jolloin käsin tehdyt muutokset katoavat.")
                } else {
                    Text("Tarina on muokattu käsin, joten se ei poistu itsestään. Voit pitää tarinan tai poistaa sen.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("storyCard.takenBackNote")
            Button(action: onKeep) {
                Text("Pidä tarina")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.elderSecondary)
            .accessibilityIdentifier("storyCard.keepStory")
            if canCompose {
                Button { isConfirmingRecompose = true } label: {
                    Text("Kokoa uudelleen")
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.primary)
                .accessibilityIdentifier("storyCard.recomposeStory")
            } else {
                Button { isConfirmingRemoval = true } label: {
                    Text("Poista tarina")
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Elder.destructive)
                .accessibilityIdentifier("storyCard.removeStory")
            }
        }
        .padding(16)
        .elderCard()
        .alert("Kootaanko tarina uudelleen?", isPresented: $isConfirmingRecompose) {
            Button("Kokoa uudelleen", role: .destructive, action: onLetGo)
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Tarina kootaan uudelleen jäljellä olevista muistoista. Käsin tehdyt muutokset katoavat.")
        }
        .alert("Poistetaanko tarina?", isPresented: $isConfirmingRemoval) {
            Button("Poista tarina", role: .destructive, action: onLetGo)
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Tarinan tekstiä ei voi palauttaa. Muistot ja äänitykset eivät muutu.")
        }
    }
}

/// The story being composed. Shown under a story that is being composed
/// again as well as in place of one that does not exist yet.
struct StoryComposing: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Kootaan tarinaa…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storyCard.composing")
    }
}

/// The composer failed. The tellings are on the card either way, and the
/// note says so before it offers another try — a story is a reading of
/// them, and the reading failing is not the memory failing.
struct StoryComposeFailed: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tarinaa ei saatu koottua nyt. Muistot ovat tallessa.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
            Button("Yritä uudelleen", action: onRetry)
                .buttonStyle(.borderless)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .elderTapTarget()
        }
        .accessibilityIdentifier("storyCard.composeFailed")
    }
}

/// What the model composed from tellings made after a person corrected the
/// story: under it, never in it, until somebody says (rule 4's shape). Two
/// full-width buttons one above the other rather than side by side, because
/// at the largest text size side by side is one button.
struct StoryProposalCard: View {
    let proposal: StoryProposal
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Uutta kerrottua")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Elder.supporting)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: proposal.text)
                .elderBody()
                .accessibilityIdentifier("storyCard.proposal")
            Text("Koottu muistoista, jotka on kerrottu tarinan muokkaamisen jälkeen. Lisätäänkö tarinan perään?")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("storyCard.proposalNote")
            Button(action: onAccept) {
                Text("Lisää tarinaan")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.elderSecondary)
            .accessibilityIdentifier("storyCard.acceptProposal")
            Button(action: onDismiss) {
                Text("Älä lisää")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.elderSecondary)
            .accessibilityIdentifier("storyCard.dismissProposal")
        }
        .padding(16)
        .elderCard()
    }
}

/// Where the tellings go when a story is composed, in the words the
/// colouring uses for its own trip (`RootView`): the service by name, what
/// is sent, when, and what it is not used for.
struct StoryConsent: View {
    var body: some View {
        Text("Tarina kootaan kerrotuista muistoista: ne lähetetään OpenRouter-palvelun kautta tekoälylle, kun uusi muisto on kerrottu. Niillä ei opeteta tekoälyä.")
            .font(.subheadline)
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("storyCard.consent")
    }
}

/// The story, corrected by hand. What the family said stays in the log
/// (rule 3); the story is a reading of it, and a person's reading wins.
/// `MemoryTextSheet`'s shape, for the same kind of correction.
struct StoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initial: String
    let onSave: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(initial: String, onSave: @escaping (String) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // `MemoryTextSheet`'s field and its cap, for its reason: a
                // long story scrolls inside the field rather than pushing
                // the buttons under the keyboard.
                TextField("Tarinan teksti", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.body)
                    .lineSpacing(Elder.lineSpacing)
                    .padding(12)
                    .elderCard()
                    .focused($isFocused)
                    .accessibilityLabel("Tarinan teksti")

                Text("Muistot ja äänitykset säilyvät ennallaan. Tekoäly ei kirjoita muokatun tarinan päälle.")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                    dismiss()
                } label: {
                    Text("Tallenna")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .elderTapTarget()
                .disabled(trimmed.isEmpty || trimmed == initial)

                Button("Peruuta") { dismiss() }
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }
            .padding(Elder.screenPadding)
            .navigationTitle("Muokkaa tarinaa")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isFocused = true }
        }
    }
}
