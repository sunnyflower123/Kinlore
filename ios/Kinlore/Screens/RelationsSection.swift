import SwiftUI

/// A person's relatives — and, since 21 Sep 2026, their friends, listed apart.
///
/// Lists, on every phone. A list carries the same information as a drawing,
/// works at the largest text size and is readable with VoiceOver, which is why
/// a grandparent's phone has only this. Since 13 Sep 2026 a family member's
/// phone also draws the whole family (`FamilyTreeView`, what Ihmiset opens on
/// there); until then the drawing was a cut in the plan (PLAN.md §5).
struct RelationsSection: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    @State private var adding: RelationKind?

    var body: some View {
        Section {
            group("Vanhempi", store.relatives(of: subject.id, kind: .parentOf), kind: .parentOf)
            group("Lapsi", store.relatives(of: subject.id, kind: .parentOf, asParent: true), kind: .parentOf, asParent: true)
            group("Puoliso", store.relatives(of: subject.id, kind: .spouseOf), kind: .spouseOf)
            group("Sisarus", store.relatives(of: subject.id, kind: .siblingOf), kind: .siblingOf)

            // A sheet of plain buttons, not a `Menu`, since 21 Sep 2026 — the
            // choice the tree's person sheet had already made. Measured the
            // day the friend was added as a fifth item after a divider: on
            // iOS 26.5 that item never fired, tapped at its centre, at its
            // edge, pressed, with the menu opened upward over its own row
            // and downward clear of it, while the four above it fired every
            // time. And the menu opened only under its words, so a finger
            // in the middle of the row met nothing. The whole row takes the
            // tap now, and the sheet's rows grow with the text size.
            // A honey chip since 27 Sep 2026, the shape the card's other
            // additions have (`ChipRow`: *Lisää tieto*, the date and the
            // name on a photograph), and ink on it rather than the accent,
            // which is the red of removal (`Elder.wax`).
            ChipRow {
                Button {
                    isChoosingKind = true
                } label: {
                    // An `HStack` and not a `Label`, like the card's other
                    // chips: measured under `ChipFlow`'s unspecified
                    // proposal, a `Label` in a `List` answered 120 points
                    // wide and several hundred tall, its words and icon at
                    // the bottom of a honey column (27 Sep 2026).
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Lisää sukulainen")
                            .fixedSize(horizontal: false, vertical: true)
                            // The identifier is for
                            // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                            // and nothing else (26 Sep 2026). On the words
                            // rather than the button: the audit reports the
                            // label.
                            .accessibilityIdentifier("relative.add")
                    }
                    .font(.body.weight(.medium))
                }
                // Both sheets hang off this one row, not off the section. A
                // modifier on a `Section` in a `List` reaches every row in it,
                // so a section with relatives on it presented the sheet from
                // each of them at once, and the presentations that lost put the
                // binding back: the sheet came up and went away on its own,
                // measured 21 Sep 2026 as a button that existed and could not
                // be tapped. The kind is carried across the sheet's dismissal
                // rather than acted on inside it: two sheets cannot change
                // places on the same frame, which is the tree's
                // `afterPersonSheet` and `RelationPicker`'s own rule about the
                // name sheet.
                .sheet(isPresented: $isChoosingKind, onDismiss: startAdding) {
                    RelativeKindSheet { kind, asChild in
                        pending = (kind, asChild)
                        isChoosingKind = false
                    }
                }
                .sheet(item: $adding) { kind in
                    RelationPicker(subject: subject, kind: kind, asChild: isAddingChild) {
                        adding = nil
                        isAddingChild = false
                    }
                }
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

        // Friends, apart from the relatives (21 Sep 2026): a friend is a
        // person card like any other, and the line to one is not kinship, so
        // it is not under *Suku* and the tree draws it apart. The section
        // exists only while somebody is in it — the way in is the row above
        // — so a card with no friend carries no empty heading.
        let friends = store.relatives(of: subject.id, kind: .friendOf)
        if !friends.isEmpty {
            Section {
                ForEach(friends) { person in
                    RelativeRow(subject: subject, relative: person, kind: .friendOf, groupTitle: "Ystävä")
                }
            } header: {
                Text("Ystävät")
                    .foregroundStyle(Elder.supporting)
                    // Keyed for the audit's default-size simulation since the
                    // Tiedot section stood above it (26 Sep 2026); the
                    // measurement is in `AccessibilityPolicy`.
                    .accessibilityIdentifier("friends.heading")
            }
        }
    }

    @State private var isAddingChild = false
    @State private var isChoosingKind = false
    @State private var pending: (kind: RelationKind, asChild: Bool)?

    private func startAdding() {
        guard let (kind, asChild) = pending else { return }
        pending = nil
        isAddingChild = asChild
        adding = kind
    }

    private var hasUnconfirmed: Bool {
        store.hasUnconfirmedRelation(for: subject.id)
    }

    /// A `LocalizedStringKey`, not a `String`. As a `String` the four captions
    /// were shown exactly as written, so an English phone read "Vanhemmat"
    /// under every parent until 13 Sep 2026.
    ///
    /// In the singular since 27 Sep 2026, as the friend's always was: each
    /// row is one person, and VoiceOver reads the name and the caption as
    /// one phrase — "Toivo, Vanhempi", where it read "Toivo, Vanhemmat".
    @ViewBuilder
    private func group(
        _ title: LocalizedStringKey, _ people: [Subject], kind: RelationKind, asParent: Bool = false
    ) -> some View {
        if !people.isEmpty {
            ForEach(people) { person in
                RelativeRow(subject: subject, relative: person, kind: kind, asParent: asParent, groupTitle: title)
            }
        }
    }
}

private struct RelativeRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject
    let relative: Subject
    let kind: RelationKind
    /// For `parentOf` only: whether this row's person is the subject's child.
    var asParent = false
    let groupTitle: LocalizedStringKey

    @State private var isConfirmingRemoval = false

    /// The one relationship this row is about, by kind and direction. Until
    /// 21 Sep 2026 the lookup took whatever live relationship joined the two,
    /// which was right while two people could only be joined once. Somebody
    /// can now be a sister and a friend, and a row that took the first line
    /// it found would confirm or remove the other one.
    private var relation: Relation? {
        if kind == .parentOf, !asParent {
            return store.relation(between: relative.id, and: subject.id, kind: kind)
        }
        return store.relation(between: subject.id, and: relative.id, kind: kind)
    }

    /// Typed, so both branches are keys: a `String` ternary is shown as it is.
    private var removalTitle: LocalizedStringKey {
        kind == .friendOf ? "Poistetaanko ystävyys?" : "Poistetaanko sukulaisuus?"
    }

    private var removalMessage: LocalizedStringKey {
        kind == .friendOf
            ? "\(relative.displayTitle) ei enää näy tämän henkilön ystävissä. Voit lisätä ystävyyden myöhemmin uudelleen."
            : "\(relative.displayTitle) ei enää näy tämän henkilön suvussa. Voit lisätä sukulaisuuden myöhemmin uudelleen."
    }

    var body: some View {
        // One VoiceOver element per relative, "Matti, Vanhempi", with the
        // swipe action below as its action. Until 21 Sep 2026 the row was
        // three stops — the icon read as "Tili", the symbol's own name, then
        // the name, then the caption — and the first sweep over a card with
        // relatives on it failed the two texts as hit areas: the swipe action
        // makes every element in the row actionable, and they measured 20
        // and 14 points tall. Twelve findings on six relatives at the default
        // text size, none at the largest, where both fonts reach 44. The
        // element is the whole left of the row, never under the tap target's
        // minimum — and on a confirmed relative, the whole tile.
        Group {
            if relation?.confirmed == true {
                // A confirmed relative is a way to her own card (27 Sep
                // 2026). Until then the row said who somebody was and led
                // nowhere, and her card was back on the list and down it by
                // name — on a grandparent's phone, where no tree is drawn,
                // the only way there was. The whole tile takes the tap, its
                // padding too: the edge of a card that does nothing is where
                // an old finger lands.
                NavigationLink(value: relative) {
                    tile {
                        identity
                        Spacer(minLength: 0)
                        // Its own chevron, in the palette, as on the names
                        // heard (`HeardNamesScreen`); the list's is hidden
                        // rather than doubled.
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Elder.supporting)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .navigationLinkIndicatorVisibility(.hidden)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken)
                .accessibilityHint("Avaa henkilön kortin.")
            } else {
                // A proposal leads nowhere. The card at the end of a guess is
                // the guess drawn as fact (rule 4), and the proposal's one
                // action is on its row.
                tile {
                    identity
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken)
                        .accessibilityAddTraits(.isStaticText)

                    Spacer()

                    if let relation, !relation.confirmed {
                        Button("Vahvista") { store.confirmRelation(id: relation.id) }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.primary)
                            .elderTapTarget()
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions {
            if relation != nil {
                // No `role: .destructive` on the swipe button. With it, iOS
                // treats the tap as the row's removal and animates the row
                // away before the button's action has done anything, and the
                // alert this row presents never appears — measured 21 Sep
                // 2026 on iOS 26.5, `alerts.count` 0 after the tap, the card
                // unchanged. Only the alert's own "Poista" is destructive,
                // because it is the one that deletes. The tint is the palette's
                // own red: the system's measures 3.57:1 on this paper.
                Button("Poista") { isConfirmingRemoval = true }
                    .tint(Elder.destructive)
            }
        }
        // A swipe is easy to make by accident and this one used to delete on the
        // spot. The relationship can be added back from the same card, which is
        // why the dialog says so — the recovery is not obvious, and telling
        // somebody about it costs one sentence.
        .alert(removalTitle, isPresented: $isConfirmingRemoval) {
            Button("Poista", role: .destructive) {
                if let relation { store.removeRelation(id: relation.id) }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    /// The disc, the name, and what the relative is to this person.
    private var identity: some View {
        HStack(spacing: 12) {
            // The relative's own disc since 27 Sep 2026 — her face, when
            // her card has one — where every confirmed relative wore the
            // same grey outline of a head. A proposal keeps the outline
            // with the question mark: the shape that says nobody has
            // checked it (rule 4), in the colour that says the same.
            if relation?.confirmed == true {
                SubjectAvatar(subject: relative)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(Elder.proposal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(relative.displayTitle)
                    .font(.body.weight(.medium))
                Text(groupTitle)
                    // The identifier is for
                    // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                    // and nothing else (26 Sep 2026).
                    .accessibilityIdentifier("relative.caption")
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
            }
        }
        .frame(minHeight: Elder.minTapTarget)
    }

    /// The name and the caption in one breath, "Toivo, Vanhempi".
    private var spoken: Text {
        Text(relative.displayTitle) + Text(", ") + Text(groupTitle)
    }

    /// A tile of its own on the paper since 27 Sep 2026, in the card's shape
    /// (`elderCard`), one under another, rather than a line of the section's
    /// white block; the swipe slides the tile aside as it slid the line.
    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .elderCard()
    }
}

/// Which relative to add, on a sheet of plain buttons — the shape the tree's
/// `TreePersonSheet` already had, and for the same reasons: a menu's rows
/// barely grow with the text size, and a menu's fifth item never fired (see
/// the note at *"Lisää sukulainen"* in `RelationsSection`). The friend's
/// button stands after a gap: not kin, so not among them (§21, "Perhe is not
/// suku"), while the row that opens this still says *Lisää sukulainen*.
private struct RelativeKindSheet: View {
    @Environment(\.dismiss) private var dismiss

    let choose: (RelationKind, Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    action("Lisää vanhempi") { choose(.parentOf, false) }
                    action("Lisää lapsi") { choose(.parentOf, true) }
                    action("Lisää puoliso") { choose(.spouseOf, false) }
                    action("Lisää sisarus") { choose(.siblingOf, false) }
                    action("Lisää ystävä") { choose(.friendOf, false) }
                        .padding(.top, 8)

                    Button {
                        dismiss()
                    } label: {
                        Text("Sulje")
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .padding(.top, 12)
                }
                .padding(Elder.screenPadding)
                // A sheet of text buttons, so ink and not the accent
                // (`Elder.wax`, which is the red of removal).
                .tint(Color.primary)
            }
            .navigationTitle("Lisää sukulainen")
            .navigationBarTitleDisplayMode(.inline)
            .elderSurface()
        }
    }

    /// The tree's `action`: the width inside the label, so the whole row
    /// takes the tap.
    private func action(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderTapTarget()
        }
        .buttonStyle(.borderless)
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
///
/// Not private since 13 Sep 2026: the drawn tree adds relatives through it too,
/// so a card and the tree cannot come to disagree about how that is done.
struct RelationPicker: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    let kind: RelationKind
    let asChild: Bool
    let onDone: () -> Void

    @State private var isAddingSomeoneNew = false
    @State private var addedSomeoneNew = false

    /// Confirmed people only, as on Ihmiset since 12 Sep 2026. A heard name
    /// nobody has checked was offered here until 13 Sep, and picking one drew
    /// nothing in the tree, which draws the confirmed only. Typing that name
    /// under "Joku uusi" still reaches its card, and confirms it.
    private var candidates: [Subject] {
        store.subjects(of: .person).filter { $0.id != subject.id && $0.confirmed }
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
        case .friendOf: return "Kuka on ystävä?"
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
            // Names to choose from, in ink: in the accent they were the red of
            // removal (`Elder.wax`).
            .tint(Color.primary)
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
