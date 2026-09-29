import SwiftUI

/// The Tiedot section of a person's card (docs/ARCHITECTURE.md §26): what
/// the family knows about her in words, one chip per fact, and the chip that
/// adds one. Its own file rather than `SubjectDetailScreen`'s, so that the
/// card's other sections can move without moving this one; the screen says
/// where the section goes and nothing more.
///
/// Each chip is the whole fact in one `Text`, so that VoiceOver says it as
/// one sentence with its pauses (*"Syntynyt, 1930-luku, Puumala"*) rather
/// than as three elements, and each chip presents its own sheet: a sheet on
/// a `List` row is in the hierarchy exactly when the row is, which a sheet
/// on the section's header would not be once the header had scrolled off.
/// The chips share one row since 27 Sep 2026, so that is still true of it.
struct PersonFactsSection: View {
    let subject: Subject

    var body: some View {
        Section {
            // Honey chips on one row, where each fact was a grey row of its
            // own until 27 Sep 2026: a fact is a few words, and a row of
            // them reads as what the card knows, where a column of rows read
            // as a form. One chip under another at the accessibility sizes
            // (`ChipRow`).
            ChipRow {
                ForEach(subject.liveFacts) { fact in
                    FactRowButton(subject: subject, fact: fact)
                }
                AddFactRow(subject: subject)
            }
        } header: {
            Text("Tiedot")
                .foregroundStyle(Elder.supporting)
                // Keyed for the audit's default-size simulation since the
                // caption under the portrait and the inline title moved the
                // section (29 Sep 2026); the measurement is in
                // `AccessibilityPolicy`.
                .accessibilityIdentifier("facts.heading")
        }
    }
}

/// One fact on the card, as a chip, and the sheet that changes or removes it.
private struct FactRowButton: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject
    let fact: PersonFact
    @State private var isChanging = false

    var body: some View {
        Button {
            isChanging = true
        } label: {
            // Ink on honey (`elderSecondary`, from the row's `ChipRow`) and
            // not the accent: a fact is what the card says, and a sentence
            // in the accent reads as somewhere to go. The style keeps the
            // chip at the tap target's minimum height; nothing here adds to
            // it, or every chip would stand 84 points tall.
            Text(FactRow.text(for: fact, in: store))
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(FactRow.spoken(for: fact, in: store))
        .sheet(isPresented: $isChanging) {
            FactSheet(subject: subject, fact: fact)
        }
    }
}

/// The section's last chip, *"Lisää tieto"*, and the sheet behind it. The
/// identifier is on the words, for the audit's default-size simulation
/// (`AccessibilityPolicy.simulationArtefactIdentifiers`, where the
/// measurement is written down).
private struct AddFactRow: View {
    let subject: Subject
    @State private var isAdding = false

    var body: some View {
        Button {
            isAdding = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Lisää tieto")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fact.add")
            }
            .font(.body.weight(.medium))
        }
        .sheet(isPresented: $isAdding) {
            FactSheet(subject: subject)
        }
    }
}

/// A fact on a person's card, written by hand: what kind of thing it is,
/// then the parts that kind asks for (docs/ARCHITECTURE.md §26).
///
/// Two steps in one sheet, and the first is a column of rows rather than a
/// picker, for `DateSheet`'s reason: rows grow with Dynamic Type and a menu
/// does not. Choosing a kind opens its parts under the same title; a fact
/// being changed opens on its parts straight away with its kind fixed — a
/// birth does not become an occupation, it is taken off and another
/// written.
///
/// The time is `DateSheet`'s own question asked over this sheet, and the
/// answer comes back here rather than being written to the person
/// (`DateSheet.init(current:onAnswer:)`), so a person's `dateHint` goes on
/// meaning what the card says it means, which is nothing. The place is one
/// of the archive's, chosen from the list or made by name in
/// `FactPlaceSheet`, so that it is one card and one point on the map.
///
/// *"Tallenna"* waits for the part without which the fact says nothing — a
/// birth needs a time or a place, a name needs the name — and nothing here
/// is inferred: what is saved is what was typed and chosen (rule 4).
struct FactSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    /// The fact being changed, or nil for a new one.
    private let existing: PersonFact?

    @State private var kind: PersonFactKind?
    @State private var text: String
    @State private var date: DateHint?
    @State private var placeSubjectID: String?
    @State private var isDating = false
    @State private var isChoosingPlace = false
    @State private var isConfirmingRemoval = false

    init(subject: Subject, fact: PersonFact? = nil) {
        self.subject = subject
        existing = fact
        _kind = State(initialValue: fact.map { PersonFactKind.of($0.kind) })
        _text = State(initialValue: fact?.text ?? "")
        _date = State(initialValue: fact?.date)
        _placeSubjectID = State(initialValue: fact?.placeSubjectID)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var placeName: String? {
        placeSubjectID.flatMap { store.subject(id: $0) }.map(\.displayTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let kind {
                    parts(of: kind)
                } else {
                    kinds
                }
            }
            // A form of text buttons, so ink and not the accent: *Tallenna*
            // and *Peruuta* in wax were the red of *Poista tieto* between
            // them (`Elder.wax`).
            .tint(Color.primary)
            .elderSurface()
            .navigationTitle(existing == nil ? String(localized: "Lisää tieto") : String(localized: "Muuta tietoa"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isDating) {
            // "En tiedä" is an answer on a photograph, where it clears a date
            // the extraction wrote; on a fact it is the absence of one.
            DateSheet(current: date) { answer in
                date = answer.precision == .unknown ? nil : answer
            }
        }
        .sheet(isPresented: $isChoosingPlace) {
            FactPlaceSheet(chosen: placeSubjectID) { placeSubjectID = $0 }
        }
        .alert("Poistetaanko tieto?", isPresented: $isConfirmingRemoval) {
            Button("Poista", role: .destructive) { remove() }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Tieto poistuu kortilta kaikissa perheen puhelimissa.")
        }
    }

    /// Step one: which kind of fact. The way out sits under the rows, as it
    /// does on every sheet here (`DateSheet` says why not the toolbar).
    private var kinds: some View {
        Section {
            ForEach(PersonFactKind.known) { choice in
                Button {
                    kind = choice
                } label: {
                    Text(choice.label)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                }
            }
            Button("Peruuta") { dismiss() }
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        } header: {
            // A List styles its own headers below the contrast minimum.
            Text("Mikä tieto?")
                .foregroundStyle(Elder.supporting)
        }
    }

    /// Step two: the parts the kind asks for, in the order it asks them.
    @ViewBuilder
    private func parts(of kind: PersonFactKind) -> some View {
        Section {
            ForEach(kind.asks, id: \.self) { part in
                switch part {
                case .text:
                    TextField(kind.label, text: $text)
                        .font(.title3)
                        .autocorrectionDisabled()
                        .elderTapTarget()
                        .onChange(of: text) { _, typed in
                            if typed.count > PersonFact.textLimit {
                                text = String(typed.prefix(PersonFact.textLimit))
                            }
                        }
                case .date:
                    Button {
                        isDating = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                            Text(date?.displayText ?? String(localized: "Lisää ajankohta"))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }
                case .place:
                    Button {
                        isChoosingPlace = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(placeName ?? String(localized: "Valitse paikka"))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }
                }
            }
        } header: {
            Text(kind.label)
                .foregroundStyle(Elder.supporting)
        } footer: {
            if kind.needs == .dateOrPlace {
                Text("Riittää, että tiedät ajan tai paikan.")
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section {
            Button("Tallenna") { save(kind) }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .elderTapTarget()
                .disabled(!isComplete(kind) || !hasRoom(for: kind))

            if existing != nil {
                Button("Poista tieto") { isConfirmingRemoval = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Elder.destructive)
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }

            Button("Peruuta") { dismiss() }
                .frame(maxWidth: .infinity)
                .elderTapTarget()
        } footer: {
            // The one refusal `setFact` has, said before the button is
            // offered rather than after it did nothing: the list has a
            // ceiling on the wire (`PersonFact.listByteLimit`).
            if !hasRoom(for: kind) {
                Text("Kortille ei mahdu enempää tietoja.")
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isComplete(_ kind: PersonFactKind) -> Bool {
        switch kind.needs {
        case .text: !trimmed.isEmpty
        case .place: placeSubjectID != nil
        case .dateOrPlace: date != nil || placeSubjectID != nil
        }
    }

    /// What was typed and chosen, and nothing the kind did not ask for: a
    /// text left over from a kind without one would be shown by a build
    /// that reads every part of a kind it does not know. The words are cut
    /// as `PersonFact.cut` cuts them, which the field above already did.
    private func fact(of kind: PersonFactKind) -> PersonFact {
        var fact = existing ?? PersonFact(kind: kind.id)
        fact.text = kind.asks.contains(.text) ? PersonFact.cut(text) : nil
        fact.date = kind.asks.contains(.date) ? date : nil
        fact.placeSubjectID = kind.asks.contains(.place) ? placeSubjectID : nil
        return fact
    }

    private func hasRoom(for kind: PersonFactKind) -> Bool {
        store.factsHaveRoom(for: fact(of: kind), on: subject.id)
    }

    private func save(_ kind: PersonFactKind) {
        if store.setFact(fact(of: kind), on: subject.id) { dismiss() }
    }

    private func remove() {
        guard let existing else { return }
        store.removeFact(id: existing.id, from: subject.id)
        dismiss()
    }
}

/// One of the archive's places for a fact: chosen from the list, or made by
/// name (§26). Made, it is an ordinary confirmed place of the archive —
/// `PlaceResolver` looks the name up as it does any other, and the place
/// lands on the family's map (§18) — and the fact points at it by id. A name
/// the archive already has answers with that place rather than a second one,
/// which is `addPerson`'s rule for people.
struct FactPlaceSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(PlaceResolver.self) private var places: PlaceResolver?
    @Environment(\.dismiss) private var dismiss

    let chosen: String?
    /// Takes the chosen place's id, or nil for none; the sheet closes itself.
    let choose: (String?) -> Void

    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var known: [Subject] {
        store.subjects(of: .place).sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paikan nimi", text: $name)
                        .font(.title3)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .elderTapTarget()
                    Button("Lisää paikka") { add() }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                        .disabled(trimmed.isEmpty)
                    Button("Peruuta") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                } header: {
                    Text("Uusi paikka")
                        .foregroundStyle(Elder.supporting)
                }

                if !known.isEmpty {
                    Section {
                        ForEach(known) { place in
                            Button {
                                choose(place.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text(place.displayTitle)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if place.id == chosen {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .elderTapTarget()
                            }
                            .accessibilityAddTraits(place.id == chosen ? .isSelected : [])
                        }
                        if chosen != nil {
                            Button("Ei paikkaa") {
                                choose(nil)
                                dismiss()
                            }
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                        }
                    } header: {
                        Text("Arkiston paikat")
                            .foregroundStyle(Elder.supporting)
                    }
                }
            }
            // Ink, for `FactSheet`'s reason.
            .tint(Color.primary)
            .elderSurface()
            .navigationTitle("Valitse paikka")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func add() {
        guard let place = store.addPlace(named: trimmed) else { return }
        if let places {
            Task { await places.resolve(place, in: store) }
        }
        choose(place.id)
        dismiss()
    }
}

/// The words of a fact as the card shows and speaks them.
@MainActor
enum FactRow {
    /// *"Syntynyt 1930-luku, Puumala"*; *"Ammatti: kansakoulunopettaja,
    /// 1960-luku"*. The kind's word and then its parts in the order the kind
    /// asks them, each only where the fact has it.
    static func text(for fact: PersonFact, in store: MemoryStore) -> String {
        let kind = PersonFactKind.of(fact.kind)
        let parts = values(of: fact, in: store)
        return parts.isEmpty ? kind.word : kind.word + " " + parts.joined(separator: ", ")
    }

    /// The same with a pause after the word — *"Syntynyt, 1930-luku,
    /// Puumala"* — which is how VoiceOver says a sentence rather than a word
    /// and a number run together.
    static func spoken(for fact: PersonFact, in store: MemoryStore) -> String {
        let kind = PersonFactKind.of(fact.kind)
        let word = kind.word.hasSuffix(":") ? String(kind.word.dropLast()) : kind.word
        return ([word] + values(of: fact, in: store)).joined(separator: ", ")
    }

    private static func values(of fact: PersonFact, in store: MemoryStore) -> [String] {
        PersonFactKind.of(fact.kind).asks.compactMap { part in
            switch part {
            case .text: fact.text.flatMap { $0.isEmpty ? nil : $0 }
            case .date: fact.date.flatMap { $0.precision == .unknown ? nil : $0.displayText }
            case .place: fact.placeSubjectID.flatMap { store.subject(id: $0) }.map(\.displayTitle)
            }
        }
    }
}
