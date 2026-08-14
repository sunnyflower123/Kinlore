import SwiftUI

/// Correcting a name the speech recognition got wrong, after the moment of
/// telling has passed.
///
/// The Tell screen already offers this in the seconds after a memory is told,
/// and that is the best moment: the teller still remembers what they said. But
/// it was the *only* moment. Recognition is wrong about one proper noun in three
/// (68 % on proper nouns, `backend/wrangler.jsonc`), the correction screen goes
/// past quickly, and during an interview the proposals pile up unhandled — so a
/// name missed there was a wrong person in the family tree for good.
///
/// That is the failure rule 4 exists to prevent, and the archive had no way out
/// of it. Sync has had a conflict rule for "a subject renamed on two devices"
/// from the beginning; until now the app could not produce that situation
/// outside those few seconds.
///
/// See docs/ARCHITECTURE.md §17.
struct CorrectNameSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    /// Called with whether the correction merged this subject into another one.
    var onSave: (Bool) -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool
    @State private var isConfirmingMerge = false

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUnchanged: Bool {
        trimmed.isEmpty || trimmed == subject.title
    }

    /// Somebody the family already has under the corrected name. Saying so
    /// before the tap is the difference between a merge and a surprise: the two
    /// cards become one, and the memories on this one move across.
    private var existing: Subject? {
        guard !isUnchanged else { return nil }
        return store.subjects(of: subject.kind).first {
            $0.id != subject.id
                && $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nimi", text: $name)
                        .font(.title3)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .elderTapTarget()
                } footer: {
                    // Said plainly rather than discovered afterwards. The text of
                    // the memories is left alone on purpose: re-writing every
                    // one of them would need the model and the family's minutes,
                    // and the right name on the card matters more than the
                    // wording inside a story — the same trade the correction at
                    // telling time already makes when re-extraction fails.
                    Text(existing == nil
                        ? "Nimi korjataan tähän korttiin ja sukuun. Kerrottujen muistojen teksti jää ennalleen."
                        : "Perheessä on jo \(existing?.displayTitle ?? ""). Kortit yhdistetään, ja tämän muistot siirtyvät sinne.")
                        .foregroundStyle(Elder.supporting)
                }

                // Both actions are rows rather than a row and a toolbar button.
                // A toolbar button's text barely grows with Dynamic Type — the
                // audit calls it "partially unsupported" and it is right — and
                // on this screen that would put the way out of a mistake in the
                // smallest text on it. Rows grow, and they are 60 pt targets.
                Section {
                    // Two different acts behind one button, so only the heavier
                    // one asks. A rename can be undone by renaming back; a merge
                    // moves another person's memories onto this card and leaves
                    // a tombstone behind, and nothing in the app undoes that.
                    // The footer says so beforehand, but a footer is read by
                    // somebody who is already looking for it.
                    Button("Tallenna") {
                        if existing == nil { save() } else { isConfirmingMerge = true }
                    }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                        .disabled(isUnchanged)

                    Button("Peruuta") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
            }
            .navigationTitle("Korjaa nimi")
            .navigationBarTitleDisplayMode(.inline)
            // The field is filled but not focused. Raising the keyboard on
            // appear pushed both buttons under it at the largest text size —
            // the audit caught "Peruuta" behind the keys, which is the way out
            // of a mistake hidden at exactly the size where mistakes are most
            // likely. It reads better too: the name to be corrected is the
            // thing to look at first, and the keyboard arrives when it is
            // wanted.
            .onAppear { name = subject.title }
            .confirmationDialog(
                "Yhdistetäänkö kortit?",
                isPresented: $isConfirmingMerge,
                titleVisibility: .visible
            ) {
                Button("Yhdistä", role: .destructive) { save() }
                Button("Peruuta", role: .cancel) {}
            } message: {
                Text("Perheessä on jo \(existing?.displayTitle ?? ""). Tämän kortin muistot siirtyvät hänelle, eikä yhdistämistä voi perua.")
            }
        }
    }

    private func save() {
        guard !isUnchanged else { return }
        let mergesInto = existing != nil
        // `rename` does the whole job: it renames, or it merges into the subject
        // that already has that name and leaves a tombstone with a forwarding
        // address so nothing anywhere points at nothing. See MemoryStore.rename
        // and docs/ARCHITECTURE.md §2.5.
        store.rename(subjectID: subject.id, to: trimmed)
        dismiss()
        onSave(mergesInto)
    }
}
