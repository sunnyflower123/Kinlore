import SwiftUI

/// A person's relatives.
///
/// Lists rather than a drawn tree — the graph is a deliberate cut in the plan
/// (PLAN.md §5). A list carries the same information, works at the largest text
/// size and is readable with VoiceOver.
struct RelationsSection: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    @State private var adding: RelationKind?

    var body: some View {
        Section {
            group("Vanhemmat", store.relatives(of: subject.id, kind: .parentOf))
            group("Lapset", store.relatives(of: subject.id, kind: .parentOf, asParent: true))
            group("Puoliso", store.relatives(of: subject.id, kind: .spouseOf))
            group("Sisarukset", store.relatives(of: subject.id, kind: .siblingOf))

            Menu {
                ForEach(RelationKind.allCases, id: \.self) { kind in
                    Button(kind.addLabel) { adding = kind }
                }
                Button("Lapsi") { adding = .parentOf; isAddingChild = true }
            } label: {
                Label("Lisää sukulainen", systemImage: "person.badge.plus")
                    .font(.body.weight(.medium))
                    // A Menu's label truncates before it wraps, and half of
                    // "Lisää sukulainen" is not a thing anybody can act on.
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .elderTapTarget()
            }
        } header: {
            Text("Suku")
                .foregroundStyle(Elder.supporting)
        } footer: {
            if hasUnconfirmed {
                // "Sovelluksen", not "tekoälyn". The help page says "Sovellus
                // arvaa puheesta nimiä ja sukulaisuuksia" and its heading is
                // "Sovellus ehdottaa, ihminen päättää"; this was the one screen
                // still naming the same thing differently, and it is the screen
                // where somebody decides whether to believe a proposal. Rule 4
                // is about who confirms, not about advertising what guessed.
                Text("Oranssilla merkityt ovat sovelluksen ehdotuksia. Vahvista vain ne jotka tiedät oikeiksi — väärä sukulaisuus on pahempi kuin puuttuva.")
                    .foregroundStyle(Elder.supporting)
            }
        }
        .sheet(item: $adding) { kind in
            RelationPicker(subject: subject, kind: kind, asChild: isAddingChild) {
                adding = nil
                isAddingChild = false
            }
        }
    }

    @State private var isAddingChild = false

    private var hasUnconfirmed: Bool {
        store.hasUnconfirmedRelation(for: subject.id)
    }

    /// A `LocalizedStringKey`, not a `String`. As a `String` the four captions
    /// were shown exactly as written, so an English phone read "Vanhemmat"
    /// under every parent until 13 Sep 2026.
    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ people: [Subject]) -> some View {
        if !people.isEmpty {
            ForEach(people) { person in
                RelativeRow(subject: subject, relative: person, groupTitle: title)
            }
        }
    }
}

private struct RelativeRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject
    let relative: Subject
    let groupTitle: LocalizedStringKey

    @State private var isConfirmingRemoval = false

    private var relation: Relation? {
        store.relation(between: subject.id, and: relative.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: relation?.confirmed == true
                ? "person.crop.circle"
                : "person.crop.circle.badge.questionmark")
                .font(.title3)
                .foregroundStyle(relation?.confirmed == true ? Elder.supporting : Elder.proposal)

            VStack(alignment: .leading, spacing: 2) {
                Text(relative.displayTitle)
                    .font(.body.weight(.medium))
                Text(groupTitle)
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
            }

            Spacer()

            if let relation, !relation.confirmed {
                Button("Vahvista") { store.confirmRelation(id: relation.id) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .elderTapTarget()
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            if relation != nil {
                Button("Poista", role: .destructive) { isConfirmingRemoval = true }
            }
        }
        // A swipe is easy to make by accident and this one used to delete on the
        // spot. The relationship can be added back from the same card, which is
        // why the dialog says so — the recovery is not obvious, and telling
        // somebody about it costs one sentence.
        .alert(
            "Poistetaanko sukulaisuus?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Poista", role: .destructive) {
                if let relation { store.removeRelation(id: relation.id) }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("\(relative.displayTitle) ei enää näy tämän henkilön suvussa. Voit lisätä sukulaisuuden myöhemmin uudelleen.")
        }
    }
}

/// Choosing a relative: somebody the family already has, or somebody new.
///
/// Until 13 Sep 2026 this said "no typing a name: a person is born out of
/// telling, not out of a form", and the list stayed empty until a telling had
/// named somebody. That order suits the person talking and fails whoever sets
/// the archive up, who knows the family's shape before anyone has said a word
/// — and a family tree cannot be drawn out of people nobody may add. A typed
/// name is confirmed by the person who typed it, since rule 4 is about who
/// vouches, and a name the family already has is the same card rather than a
/// second one (`MemoryStore.addPerson`).
private struct RelationPicker: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    let kind: RelationKind
    let asChild: Bool
    let onDone: () -> Void

    @State private var isAddingSomeoneNew = false
    @State private var addedSomeoneNew = false

    private var candidates: [Subject] {
        store.subjects(of: .person).filter { $0.id != subject.id }
    }

    /// One whole sentence per kind rather than a word dropped into one:
    /// "Kuka on \(addLabel)?" was a key no table had, and English needs an
    /// article Finnish does not.
    private var title: LocalizedStringKey {
        if asChild { return "Kuka on lapsi?" }
        switch kind {
        case .parentOf: return "Kuka on vanhempi?"
        case .spouseOf: return "Kuka on puoliso?"
        case .siblingOf: return "Kuka on sisarus?"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // First, because it is the row this list could not offer
                // until 13 Sep 2026 — see the note above this type.
                Button {
                    isAddingSomeoneNew = true
                } label: {
                    Label("Joku uusi", systemImage: "person.badge.plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                }

                ForEach(candidates) { person in
                    Button {
                        relate(person)
                        dismiss()
                        onDone()
                    } label: {
                        Text(person.displayTitle)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .elderTapTarget()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Peruuta") { dismiss(); onDone() }
                }
            }
            // The picker closes only once the name sheet has gone, so two
            // sheets are not dismissed on the same frame.
            .sheet(isPresented: $isAddingSomeoneNew, onDismiss: {
                if addedSomeoneNew { dismiss(); onDone() }
            }) {
                NameSheet(title: title, initial: "") { name in
                    guard let person = store.addPerson(named: name) else { return false }
                    relate(person)
                    addedSomeoneNew = true
                    return true
                }
            }
            .elderSurface()
        }
    }

    /// `parentOf` reads from → to. Adding a child flips the direction;
    /// otherwise the family tree would come out upside down.
    private func relate(_ person: Subject) {
        if asChild {
            store.addRelation(from: subject.id, to: person.id, kind: kind)
        } else if kind == .parentOf {
            store.addRelation(from: person.id, to: subject.id, kind: kind)
        } else {
            store.addRelation(from: subject.id, to: person.id, kind: kind)
        }
    }
}

extension RelationKind: Identifiable {
    var id: String { rawValue }
}
