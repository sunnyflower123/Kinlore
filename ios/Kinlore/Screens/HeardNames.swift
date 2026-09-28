import SwiftUI

/// The door at the bottom of the people list: the names the extraction heard
/// and nobody has checked. See `HeardNamesScreen`.
struct HeardNamesRoute: Hashable {}

/// The sentence a name was heard in.
///
/// A name alone on a row asks her to remember where it came up; the sentence
/// lets her recognise it. Matched on the name as a prefix, which is what
/// Finnish inflection leaves intact most of the time — "Puumalassa" carries
/// "Puumala", "Ainon" carries "Aino" — and a name whose stem changes ("Matin"
/// for Matti) gets no sentence rather than a wrong one. One rule for the
/// result screen, the memory row and the door, so they cannot drift apart.
enum HeardSentence {
    static func find(_ name: String, in text: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) })
        guard let hit = sentences.first(where: { $0.localizedCaseInsensitiveContains(name) })
        else { return nil }
        let trimmed = hit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "”\(trimmed)”"
    }
}

/// A name heard and not yet checked: the name, what it was heard as, the
/// sentence it was heard in, and the two answers — it is somebody, or it is
/// not. The name itself opens the card, where "Korjaa nimi" is; a field for
/// the name here would be a second implementation of the result screen's row.
///
/// "Vahvista" and "Poista" are the words that row already uses for the same
/// two acts (ARCHITECTURE §21). The cross asks first there and it asks first
/// here, because the hand holding this phone shakes.
struct HeardNameRow: View {
    let subject: Subject
    let sentence: String?
    let onConfirm: () -> Void
    let onReject: () -> Void
    /// How the name opens its card inside a row that holds more than the
    /// name — a telling (`MemoryRow`), with its words and every other name
    /// it heard. Nil on a row of its own, which the link may take whole.
    var open: ((Subject) -> Void)? = nil

    @State private var isConfirmingReject = false

    private var name: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // The name on its own line, exactly as the people
                // list shows it: the tests find a person by the name
                // alone, and so does VoiceOver's rotor. The kind is a
                // runtime String — the Finnish IS the key — handed
                // over as a key to be looked up.
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizedStringKey(subject.kind.label))
                    // The identifier is for
                    // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                    // and nothing else (26 Sep 2026).
                    .accessibilityIdentifier("heardName.kind")
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
                if let sentence {
                    Text(verbatim: sentence)
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Elder.supporting)
        }
        // The whole width answers, the gap between the name and its chevron
        // included. A plain button answers only where it draws, and inside a
        // telling the row is no longer the list's to take (28 Sep 2026).
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A button inside a telling. As a link there it took the
            // telling's whole row, and every other name's link with it: on a
            // telling that heard Puumalassa, Aino and Toivo, a tap on Aino —
            // or on the story's words — pushed all three cards, Toivo's on
            // top (28 Sep 2026).
            if let open {
                Button {
                    open(subject)
                } label: {
                    name
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: subject) {
                    name
                }
                .buttonStyle(.plain)
                // The row draws its own chevron, in `Elder.supporting`; the list
                // would add its grey one at the far edge, and two arrows on one
                // row read as two places to go.
                .navigationLinkIndicatorVisibility(.hidden)
            }

            HStack(spacing: 16) {
                Button("Vahvista", action: onConfirm)
                    .buttonStyle(.elderSecondary)
                    .elderTapTarget()
                    .accessibilityLabel("Vahvista \(subject.title)")
                Button("Poista") { isConfirmingReject = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Elder.destructive)
                    .elderTapTarget()
                    .accessibilityLabel("Poista \(subject.title)")
            }
        }
        .padding(.vertical, 6)
        .alert("Poistetaanko \(subject.title)?", isPresented: $isConfirmingReject) {
            Button("Poista", role: .destructive, action: onReject)
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Nimi poistuu perheen listalta. Kertomasi teksti ei muutu.")
        }
    }
}

/// The names the extraction heard and nobody has checked, one screen behind
/// the people list.
///
/// Until 12 Sep 2026 they sat on the list itself as orange "Ehdotus" rows,
/// beside the family — a guess next to the people it was a guess about, and
/// a card the front screen could offer. Here each carries the sentence it was
/// heard in, so a wrong name is recognised rather than recalled, and the
/// answer is one tap: it is somebody, or it is not.
struct HeardNamesScreen: View {
    @Environment(MemoryStore.self) private var store

    private var heard: [Subject] {
        store.subjects(of: .person).filter { !$0.confirmed }
    }

    /// The newest telling that named the person, for the sentence — the tidied
    /// text first, the verbatim transcript when the tidying lost the name.
    private func sentence(for subject: Subject) -> String? {
        for memory in store.memories(mentioning: subject.id) {
            if let hit = HeardSentence.find(subject.title, in: memory.body) { return hit }
            if let raw = memory.rawTranscript,
               let hit = HeardSentence.find(subject.title, in: raw) { return hit }
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                Text("Nämä nimet kuultiin kerronnassa. Emme lisää sukuun ketään jota et ole hyväksynyt.")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
                    .listRowBackground(Color.clear)
            }
            Section {
                if heard.isEmpty {
                    Text("Kaikki kuullut nimet on tarkistettu.")
                        .elderBody()
                        .listRowBackground(Elder.paper)
                }
                ForEach(heard) { subject in
                    HeardNameRow(
                        subject: subject,
                        sentence: sentence(for: subject),
                        onConfirm: { store.confirm(subjectID: subject.id) },
                        onReject: { store.remove(subjectID: subject.id) }
                    )
                    .listRowBackground(Elder.paper)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Kuullut nimet")
        .navigationBarTitleDisplayMode(.large)
        .elderSurface()
    }
}
