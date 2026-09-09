import SwiftUI

/// Where a telling belongs, chosen from the cards the family already has.
///
/// The AI's placement is the most important piece of the result and, until
/// 5 Sep 2026, the one nobody could correct (founder's-eye review, finding
/// #27). This sheet is the correction, from the result screen in the moment
/// and from the memory's own row the day after — the same sheet, so the two
/// doors hand out the same choice (`MemoryStore.move`).
///
/// People, places and events with a name on them, **confirmed ones only**: a
/// telling filed under a proposal would make the proposal look like a fact,
/// which is rule 4 read backwards. Photographs are not offered: a telling
/// about a photograph starts from the photograph, and an archive's hundred
/// untitled "Valokuva" rows would be a list nobody can choose from.
struct MoveMemorySheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The card the telling is on now, which is not offered.
    let current: String
    let onPick: (Subject) -> Void

    private var candidates: [(kind: SubjectKind, title: LocalizedStringKey, subjects: [Subject])] {
        [
            (.person, "Ihmiset", store.subjects(of: .person)),
            (.place, "Paikat", store.subjects(of: .place)),
            (.event, "Tapahtumat", store.subjects(of: .event)),
        ].map { kind, title, subjects in
            (kind, title, subjects.filter { $0.id != current && $0.confirmed && !$0.title.isEmpty })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.allSatisfy(\.subjects.isEmpty) {
                    // Words of our own rather than a `ContentUnavailableView`,
                    // whose text the framework caps — the same trade the
                    // empty gallery made.
                    VStack(spacing: 12) {
                        Text("Ei muita kortteja")
                            .font(.title2.weight(.semibold))
                        Text("Kortit syntyvät kertomisesta. Kun perhe on kertonut ihmisistä, paikoista ja tapahtumista, muiston voi siirtää niille.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(candidates, id: \.kind) { group in
                            if !group.subjects.isEmpty {
                                Section {
                                    ForEach(group.subjects) { subject in
                                        Button {
                                            onPick(subject)
                                            dismiss()
                                        } label: {
                                            Text(subject.displayTitle)
                                                .font(.body)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .elderTapTarget()
                                        }
                                    }
                                } header: {
                                    Text(group.title)
                                        .foregroundStyle(Elder.supporting)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mihin muisto kuuluu?")
            .navigationBarTitleDisplayMode(.inline)
            // A row rather than a toolbar button: a toolbar button's text
            // barely grows with Dynamic Type, which would put the way out of
            // this sheet in the smallest text on it — the audit reported it on
            // the first run. The same shape as the invite sheet's.
            .safeAreaInset(edge: .bottom) {
                Button("Peruuta") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
                    .padding(Elder.screenPadding)
                    .background(.bar)
            }
            .elderSurface()
        }
    }
}
