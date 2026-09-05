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

    @ViewBuilder
    private func group(_ title: String, _ people: [Subject]) -> some View {
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
    let groupTitle: String

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

/// Choosing a relative from the people already known.
///
/// No typing a name: a person is born out of telling, not out of a form. If the
/// person you want is not in the list, nobody has told about them yet — and that
/// is the correct order.
private struct RelationPicker: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    let kind: RelationKind
    let asChild: Bool
    let onDone: () -> Void

    private var candidates: [Subject] {
        store.subjects(of: .person).filter { $0.id != subject.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Ei muita henkilöitä", systemImage: "person.2")
                    } description: {
                        Text("Henkilöt syntyvät kertomisesta. Kerro ensin muisto jossa mainitset heidät.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }
                } else {
                    List(candidates) { person in
                        Button {
                            // `parentOf` reads from → to. Adding a child flips
                            // the direction; otherwise the family tree would
                            // come out upside down.
                            if asChild {
                                store.addRelation(from: subject.id, to: person.id, kind: kind)
                            } else if kind == .parentOf {
                                store.addRelation(from: person.id, to: subject.id, kind: kind)
                            } else {
                                store.addRelation(from: subject.id, to: person.id, kind: kind)
                            }
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
            }
            .navigationTitle(asChild ? "Kuka on lapsi?" : "Kuka on \(kind.addLabel.lowercased())?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Peruuta") { dismiss(); onDone() }
                }
            }
        }
    }
}

extension RelationKind: Identifiable {
    var id: String { rawValue }
}
