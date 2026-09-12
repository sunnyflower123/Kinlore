import SwiftUI

/// A name typed by hand.
///
/// Two places open it, since 6 Sep 2026, and they were the two names in the
/// archive nothing could change after the fact. A photograph's title was
/// whatever its first telling left — a place and a year, until 12 Sep 2026,
/// when a telling stopped naming anything and this sheet became the only way
/// a picture or a moment gets a name — and the card had a way to date the
/// picture but none to name it. And a member's own name was written once, at the
/// join, and never again: a joiner who left the form's name empty on a code
/// made without one was *"Perheenjäsen"* beside every telling for good
/// (founder's-eye review, findings #12 and #64).
///
/// The person's word overwrites, as `MemoryStore.setDateHint` does and for
/// the same reason: `describe` speaks for the extraction and fills only an
/// empty field, and this is not the extraction. Saving is handed in, because
/// one of the two names lives on this phone and the other on the server —
/// and the server's can fail, which is why `save` answers and the sheet
/// stays open to say so.
///
/// The same shape as `CorrectNameSheet`, and the same two lessons from it:
/// the actions are rows and not a toolbar button, because a toolbar button's
/// text barely grows with Dynamic Type; and the field is filled but not
/// focused, because a keyboard raised on appear pushed both buttons under it
/// at the largest text size.
struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    let initial: String
    /// Saves the trimmed name. `false` keeps the sheet open, with the reason.
    let save: (String) async -> Bool

    @State private var name: String
    @State private var isSaving = false
    @State private var failed = false

    init(title: LocalizedStringKey, initial: String, save: @escaping (String) async -> Bool) {
        self.title = title
        self.initial = initial
        self.save = save
        _name = State(initialValue: initial)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUnchanged: Bool {
        trimmed.isEmpty || trimmed == initial
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nimi", text: $name)
                        .font(.title3)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .elderTapTarget()
                }

                if failed {
                    Section {
                        Label(
                            "Nimi ei nyt vaihtunut. Yritä uudelleen, kun verkkoyhteys toimii.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Elder.proposal)
                        .elderBody()
                    }
                }

                Section {
                    Button("Tallenna") {
                        Task {
                            isSaving = true
                            failed = false
                            if await save(trimmed) {
                                dismiss()
                            } else {
                                failed = true
                            }
                            isSaving = false
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
                    .disabled(isUnchanged || isSaving)

                    Button("Peruuta") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .elderSurface()
        }
    }
}
