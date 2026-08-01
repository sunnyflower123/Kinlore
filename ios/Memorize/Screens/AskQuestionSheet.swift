import SwiftUI

/// A family member asks a question about a subject.
///
/// The other half of the open-question loop: extraction already generates
/// questions, and this lets a person do the same. The question lands in the
/// same `prompt_question` flow, appears on the family's Tell screen as an
/// invitation, and the answer comes back as an ordinary structured memory on
/// this subject. The asker's name travels with it — "Ville kysyy" carries a
/// pull no machine question has.
struct AskQuestionSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let subject: Subject

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mitä haluaisit tietää?")
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                TextField(
                    "Esimerkiksi: Millainen kesä mökillä oli?",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(3...)
                .font(.body)
                .lineSpacing(Elder.lineSpacing)
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                .focused($isFocused)

                Text("Kysymys näkyy koko perheelle Kerro-näytöllä, ja vastaus tallentuu muistoksi tähän kohteeseen.")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    send()
                } label: {
                    Text("Lähetä kysymys")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)
            }
            .padding(Elder.screenPadding)
            .navigationTitle(subject.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Peruuta") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        // The asker claims only themselves; the server enforces the same rule.
        // The name is written locally too, so the attribution shows before the
        // first sync — and on this same device, where the server never echoes
        // the row back.
        let question = FollowUpQuestion(
            subjectID: subject.id,
            text: trimmed,
            authorID: session.identity.memberID,
            authorName: store.authorName
        )
        store.add(questions: [question])
        dismiss()
    }
}
