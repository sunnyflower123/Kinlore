import SwiftUI

/// A family member asks a question about a subject.
///
/// The other half of the open-question loop: extraction already generates
/// questions, and this lets a person do the same. The question lands in the
/// same `prompt_question` flow, appears on the family's Tell screen as an
/// invitation, and the answer comes back as an ordinary structured memory on
/// this subject. The asker's name travels with it — "Ville kysyy" carries a
/// pull no machine question has.
///
/// It can also be asked of one member by name, since 25 Sep 2026. That
/// narrows two things only: whose Kerro tab offers it, and who is told. The
/// card still shows it to everyone, and anyone who knows may answer it.
struct AskQuestionSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    let subject: Subject

    @State private var text = ""
    /// The member it is asked of, or nil for the whole family.
    @State private var targetID: String?
    @FocusState private var isFocused: Bool

    /// Who it can be asked of: the family's other members, each with a name to
    /// show. Empty outside a family, and then there is no choice to offer.
    /// Both ids are left out, because the demo family's "you" is not the
    /// Keychain's member — and on a real phone they are one and the same.
    private var others: [Session.Member] {
        guard let family = session.family else { return [] }
        return family.members.filter { member in
            member.id != family.you.id && member.id != session.identity.memberID
                && !member.displayName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                    .elderCard()
                    .focused($isFocused)

                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            // The picker carries the same words as its label, so
                            // VoiceOver reads them once, with the choice after.
                            Text("Kenelle?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Elder.supporting)
                                .accessibilityHidden(true)
                            Picker("Kenelle?", selection: $targetID) {
                                Text("Koko perhe").tag(String?.none)
                                ForEach(others) { member in
                                    // A name, not a key: nothing to look up.
                                    Text(verbatim: member.displayName).tag(String?.some(member.id))
                                }
                            }
                            .pickerStyle(.menu)
                            // Ink, not the accent: wax is the red of removal
                            // since 26 Sep 2026 (`Elder.wax`), and it belongs
                            // to *Lähetä kysymys* below.
                            .tint(Color.primary)
                            .elderTapTarget()
                        }
                    }

                    Group {
                        if targetID == nil {
                            Text("Kysymys näkyy koko perheelle Kerro-näytöllä, ja vastaus tallentuu muistoksi tähän kohteeseen.")
                        } else {
                            Text("Kysymys näkyy koko perheelle, mutta Kerro-näytöllä se tarjotaan vain valitsemallesi ihmiselle. Vastaus tallentuu muistoksi tähän kohteeseen.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Elder.screenPadding)
            }
            // The buttons ride above the keyboard, and what they leave
            // scrolls. At the largest text size the column they used to
            // close put "Lähetä kysymys" under the keys — 663 pt down against
            // a keyboard at 583, measured 25 Sep 2026 on the sheet as it was
            // before "Kenelle?" made it taller still. The audit forgives what
            // the keyboard covers, so only a frame could say so
            // (`TargetedQuestionTests`).
            //
            // Side by side below the accessibility sizes, because a stacked
            // pair is 184 pt of a screen the keyboard has already halved: at
            // the ordinary size it covered the sentence under the field at
            // rest, cut through the middle of a line (25 Sep 2026). The text
            // size decides it, as it does for the invite row, and not
            // `ViewThatFits`: the audit refused that on both buttons at the
            // ordinary size — "Dynamic Type font sizes are partially
            // unsupported", the finding the family tree met with it first.
            //
            // Paper and a hairline rather than `.bar`, which the two sheets
            // with a lone "Peruuta" use: above the keyboard the audit failed
            // "Peruuta" on the material in three runs out of three, while its
            // pixels read the accent at 6.2:1 on it. Presumably the audit
            // never said so on those sheets because at their foot the
            // button's frame reaches into the tab bar's, whose contrast
            // findings the policy forgives. Paper is the ground the palette's
            // ratios are measured on, and what scrolls under it is covered
            // rather than blurred.
            .safeAreaInset(edge: .bottom) {
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 16) {
                            sendButton
                            cancelButton
                        }
                    } else {
                        HStack(spacing: 16) {
                            cancelButton
                            sendButton
                        }
                    }
                }
                .padding(Elder.screenPadding)
                .background(Elder.paper)
                .overlay(alignment: .top) {
                    Rectangle().fill(Elder.rule).frame(height: 1)
                }
            }
            .navigationTitle(subject.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isFocused = true }
            .elderSurface()
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            // Allowed to wrap. The audit's clipping check asks whether
            // the text could still be read if it grew, and a label
            // pinned to one line inside a fixed-height button cannot.
            Text("Lähetä kysymys")
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        // The 60 pt minimum belongs to the **button**, not to the text
        // inside it. Applied to the label it fought the button style
        // over the box the text goes in, and the audit reported "Lähetä
        // kysymys" as clipped at the ordinary text size — on the one
        // screen nothing had ever actually opened, so nothing had ever
        // measured it. Constrain the control; let the label be a label.
        .buttonStyle(.borderedProminent)
        .elderTapTarget()
        .disabled(trimmed.isEmpty)
    }

    // A row rather than a toolbar button. A toolbar button's text
    // barely grows with Dynamic Type — the audit calls it
    // "partially unsupported", and it is right — which put the way
    // out of this screen in the smallest text on it. The audit only
    // saw it once the test started actually opening this sheet.
    private var cancelButton: some View {
        Button("Peruuta") { dismiss() }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .elderTapTarget()
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        // The asker claims only themselves; the server enforces the same rule.
        // The name is written locally too, so the attribution shows before the
        // first sync — and on this same device, where the server never echoes
        // the row back.
        // The aim's name is written locally for the same reason; the server
        // answers every other phone with the member's own display name.
        let target = others.first { $0.id == targetID }
        let question = FollowUpQuestion(
            subjectID: subject.id,
            text: trimmed,
            authorID: session.identity.memberID,
            authorName: store.authorName,
            targetMemberID: target?.id,
            targetName: target?.displayName
        )
        store.add(questions: [question])
        dismiss()
    }
}
