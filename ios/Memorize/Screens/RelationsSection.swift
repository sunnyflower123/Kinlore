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
                    .elderTapTarget()
            }
        } header: {
            Text("Suku")
        } footer: {
            if hasUnconfirmed {
                Text("Oranssilla merkityt ovat tekoälyn ehdotuksia. Vahvista vain ne jotka tiedät oikeiksi — väärä sukulaisuus on pahempi kuin puuttuva.")
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
        store.relations.contains {
            !$0.confirmed && ($0.fromSubjectID == subject.id || $0.toSubjectID == subject.id)
        }
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

    private var relation: Relation? {
        store.relations.first {
            ($0.fromSubjectID == subject.id && $0.toSubjectID == relative.id)
                || ($0.fromSubjectID == relative.id && $0.toSubjectID == subject.id)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: relation?.confirmed == true
                ? "person.crop.circle"
                : "person.crop.circle.badge.questionmark")
                .font(.title3)
                .foregroundStyle(relation?.confirmed == true ? Color.secondary : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(relative.displayTitle)
                    .font(.body.weight(.medium))
                Text(groupTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            if let relation {
                Button("Poista", role: .destructive) { store.removeRelation(id: relation.id) }
            }
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
