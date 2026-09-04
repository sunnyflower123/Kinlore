import SwiftUI

/// Three tabs, because four is already too many to remember.
/// Telling is in the middle and is the default — the app opens on what it exists
/// for, not on a list.
struct RootView: View {
    private enum Tab: Hashable {
        case memories, tell, people

        /// Telling is the default: the app opens on what it exists for, not on
        /// a list. Two states outrank it, both about arrival rather than
        /// preference — joining, and tellings from others waiting unseen.
        ///
        /// Development and screenshot aid: `-tab memories` or `-tab people` as
        /// a launch argument opens the given tab directly, so screenshots can be
        /// taken without any tapping. DEBUG builds only.
        static func initial(newFromFamily: Bool) -> Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "tab") {
            case "memories": return .memories
            case "people": return .people
            default: break
            }
            #endif
            // The one launch after joining a family opens on Muistot: the
            // invitation was to something that already exists, and the
            // arrival should show it rather than an empty Tell screen.
            // Consumed here, so every later launch opens on Kerro as ever.
            // See docs/UX.md §4.3.
            if UserDefaults.standard.bool(forKey: Session.arrivalPendingKey) {
                UserDefaults.standard.removeObject(forKey: Session.arrivalPendingKey)
                return .memories
            }
            // The reader's return: the family has told things this phone has
            // not seen, so the app opens on them — the reading loop finally
            // pointing both ways (docs/UX.md §6). If the phase E visit shows
            // this flip costs the teller her button, this one condition is
            // the thing to revert; the section stays either way.
            if newFromFamily { return .memories }
            return .tell
        }
    }

    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var selection: Tab

    /// The caller decides whether unseen tellings are waiting, because it has
    /// the store and a `@State`'s initial value cannot ask the environment.
    /// Evaluated once per root-view identity, so a person's own tab choice is
    /// never overridden mid-session.
    init(opensOnNewFromFamily: Bool = false) {
        _selection = State(initialValue: Tab.initial(newFromFamily: opensOnNewFromFamily))
    }

    var body: some View {
        TabView(selection: $selection) {
            GalleryScreen()
                .tabItem { Label("Muistot", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.memories)

            // The one Tell screen that is nobody's destination, and so the one
            // that has to find its own subject. Every other use of this screen
            // was navigated to from a photo, a person or a question and already
            // knows what it is about.
            TellScreen(usesDeck: true)
                .tabItem { Label("Kerro", systemImage: "mic.circle.fill") }
                .tag(Tab.tell)

            PeopleScreen()
                .tabItem { Label("Ihmiset", systemImage: "person.2.fill") }
                .tag(Tab.people)
        }
    }
}

/// Marks the family view as a navigation destination, so it can be pushed by
/// value rather than only by tapping the toolbar button.
struct FamilyRoute: Hashable {}

/// The same for Settings, which is where the family view now lives one step
/// down. See docs/ARCHITECTURE.md §14.
struct SettingsRoute: Hashable {}

/// And for the help page, one step below Settings.
struct HelpRoute: Hashable {}

/// And for opening a single-device archive to a family, one step below
/// Settings and offered only there. See `EnableSharingScreen`.
struct SharingRoute: Hashable {}

/// The people in the family. The same `subject` table as the photos and the same
/// memory view — only the listing differs.
struct PeopleScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var path = NavigationPath()
    /// What is typed in the search field. Empty means no search is running, and
    /// `subjects(of:matching:)` hands back everything for an empty query — so
    /// there is one code path rather than two.
    @State private var query = ""

    private var people: [Subject] { store.subjects(of: .person, matching: query) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.subjects(of: .person).isEmpty {
                    ContentUnavailableView {
                        Label("Ei vielä ihmisiä", systemImage: "person.2")
                    } description: {
                        // "Ihmiset", not "suvun henkilöt": the tab is called
                        // Ihmiset and so is this screen, and a person who has
                        // just tapped one word should not be answered in
                        // another. The distinction the app does keep is one
                        // level down — *suku* is the web of relations on a
                        // person's card, and it is a different thing from the
                        // list. See docs/ARCHITECTURE.md §21.
                        Text("Ihmiset kertyvät tähän sitä mukaa kun heistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }
                } else if people.isEmpty {
                    // A search that found nobody is a different emptiness from
                    // a family nobody has spoken about yet, and it says so in
                    // its own words rather than in the invitation's.
                    ContentUnavailableView {
                        Label("Ei osumia", systemImage: "magnifyingglass")
                    } description: {
                        Text("Kukaan ei löytynyt haulla \"\(query)\". Haku etsii nimistä ja siitä mitä ihmisistä on kerrottu.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }
                } else {
                    List(people) { person in
                        NavigationLink(value: person) {
                            PersonRow(subject: person)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Ihmiset")
            // Out of the way until it is wanted: iOS keeps the field hidden
            // above the list until somebody pulls down, which is the right
            // bargain here. The grandchild looking for one name in forty finds
            // it; grandmother never meets it.
            // "Etsi" and nothing more. The field keeps its width while the text
            // in it grows, so a prompt of any length is a prompt that will be
            // cut in half at the largest size — and what the search actually
            // covers is spelled out where it matters, on the screen that comes
            // back with nothing.
            .searchable(text: $query, prompt: "Etsi")
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailScreen(subject: subject)
            }
            .navigationDestination(for: FamilyRoute.self) { _ in
                FamilyScreen()
            }
            .navigationDestination(for: SettingsRoute.self) { _ in
                SettingsScreen()
            }
            .navigationDestination(for: HelpRoute.self) { _ in
                HelpScreen()
            }
            .navigationDestination(for: SharingRoute.self) { _ in
                EnableSharingScreen()
            }
            .toolbar {
                // Settings belongs under People rather than as its own tab:
                // three tabs is already the limit of what an 80-year-old holds
                // in mind. It is shown without a backend too — a single-device
                // archive is exactly the one with no copy anywhere else, and it
                // used to have no way to reach the export at all.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: SettingsRoute()) {
                        Image(systemName: "gearshape")
                            .elderTapTarget()
                    }
                    .accessibilityLabel("Asetukset")
                }
            }
            #if DEBUG
            // Screenshot aid, alongside `-tab` and `-screen write`. These two
            // screens sit behind a tap, and a screenshot run has no hands:
            //
            //   -screen person     the first person's card, relationships and all
            //   -screen family     members, usage and the invite link
            //   -screen settings   export, leaving, emptying the device
            //   -screen sharing    opening a single-device archive to a family
            //
            // Checking a screen at the largest text size means opening it, and
            // this is how the two that were skipped stopped being skipped.
            .task {
                switch UserDefaults.standard.string(forKey: "screen") {
                case "person":
                    if let first = store.subjects(of: .person).first { path.append(first) }
                case "family":
                    path.append(FamilyRoute())
                case "settings", "export":
                    path.append(SettingsRoute())
                case "sharing":
                    // Both, so the screen has the back stack it really has.
                    path.append(SettingsRoute())
                    path.append(SharingRoute())
                default:
                    break
                }
            }
            #endif
        }
    }
}

private struct PersonRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            // The icon conveys state through its shape, not colour alone:
            // encoding meaning in colour only is an accessibility failure, and
            // this app's user is precisely the one who suffers from it.
            Image(systemName: subject.confirmed
                ? "person.crop.circle"
                : "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(subject.confirmed ? Elder.supporting : Elder.proposal)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))

                // Two different things, two different signals. Orange plus the
                // word "Ehdotus" = check this. Blue plus a microphone = do this.
                if !subject.confirmed {
                    Text("Ehdotus — vahvista henkilö")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Elder.proposal)
                } else if store.memories(for: subject.id).isEmpty {
                    // A gap is not hidden but shown as an invitation.
                    // Not tinted — the same call as the gallery's row and the
                    // guessing round's card: blue on this grey only nearly
                    // passes, and it fails outright inside the tab bar's fade.
                    // Weight invites; the microphone says what to do.
                    Label("Kerro hänestä", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                } else {
                    let count = store.memories(for: subject.id).count
                    Text(count == 1 ? "1 muisto" : "\(count) muistoa")
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// The view for a photo, a person and an event is the same: the subject and the
/// memories that have gathered on it. This is the concrete payoff of the
/// `subject` table — one view instead of three.
struct SubjectDetailScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    let subject: Subject

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isTelling = false
    @State private var isAsking = false
    @State private var isCorrectingName = false
    @State private var isDating = false
    @State private var isConfirmingRemoval = false

    /// The subject as the store has it now, rather than as it was when this
    /// screen was pushed. A name corrected here has to be visible here, and the
    /// screen is handed a value rather than an id.
    private var current: Subject { store.subject(id: subject.id) ?? subject }

    /// Names that came out of speech, and only those.
    ///
    /// A photo's or an event's title is written by the app out of a place and a
    /// year; a person's and a place's is a proper noun the recognition heard,
    /// and it is wrong about one time in three (`wrangler.jsonc`: 68 % on proper
    /// nouns, which is the measurement the whole name-correction step exists
    /// for). Those are the two that need a second chance.
    private var nameCameFromSpeech: Bool {
        current.kind == .person || current.kind == .place
    }

    /// Whether "when did this happen" is a question this subject can answer.
    private var datable: Bool {
        current.kind == .photo || current.kind == .event
    }

    /// Whether this card can be deleted: only while nothing has been told
    /// about it, nobody has asked about it and, for a person, nobody is
    /// related to them. A photograph is the wrong side of a print; a person
    /// or a place is the checkmark hit instead of the cross, or a name the
    /// recognition invented — confirmed by mistake, and rule 4 read backwards
    /// until 4 Sep 2026: a wrong person permanent as fact, with no way out.
    /// Anything that holds a story stays; the story is taken back first.
    private var removable: Bool {
        (current.kind == .photo || current.kind == .person || current.kind == .place)
            && store.memories(for: subject.id).isEmpty
            && !store.questions.contains { $0.subjectID == subject.id && !$0.answered }
            && !store.relations.contains {
                $0.deletedAt == nil && ($0.fromSubjectID == subject.id || $0.toSubjectID == subject.id)
            }
    }

    /// The words of the deletion, by what is being deleted. Three literal
    /// keys rather than one with the kind interpolated: each is read as a
    /// whole sentence by somebody who is 80, and the translation table holds
    /// sentences.
    private var removalButton: LocalizedStringKey {
        switch current.kind {
        case .person: "Poista henkilö"
        case .place: "Poista paikka"
        default: "Poista kuva"
        }
    }

    private var removalTitle: LocalizedStringKey {
        switch current.kind {
        case .person: "Poistetaanko tämä henkilö?"
        case .place: "Poistetaanko tämä paikka?"
        default: "Poistetaanko tämä kuva?"
        }
    }

    private var removalMessage: LocalizedStringKey {
        switch current.kind {
        case .person: "Henkilö poistuu perheen arkistosta, eikä sitä voi palauttaa."
        case .place: "Paikka poistuu perheen arkistosta, eikä sitä voi palauttaa."
        default: "Kuva poistuu perheen arkistosta, eikä sitä voi palauttaa."
        }
    }

    var body: some View {
        List {
            if subject.kind == .photo {
                Section {
                    photoView
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            // The date, and the way to put one there. It used to be a label that
            // appeared only when the extraction had heard a year — so a
            // photograph nobody had dated said nothing, and the granddaughter
            // who knows the summer was 1957 had nowhere to put it. Rule 5 stores
            // uncertainty; until now only the machine could write any.
            //
            // People and places are left out on purpose: `dateHint` means "when
            // this happened", and a person's date would have to mean birth or
            // death, which the column does not say and the app must not guess.
            // When it happened, and the way to say so. It used to be a label
            // that appeared only when the extraction had heard a year, so a
            // photograph nobody had dated said nothing at all.
            //
            // A `Text` and an `Image` rather than a `Label`, and that is not a
            // style preference: as a `Label` the audit reported this row's text
            // as clipped in every shape it was tried in — as a button's label,
            // as a plain row, with the tap target moved, with an explicit font —
            // and it pushed a second finding onto the memory underneath. Split
            // into two views the same row passes at both sizes. Four runs to
            // learn one fact, which is why it is written here.
            if datable {
                Section {
                    Button {
                        isDating = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                            Text(current.dateHint?.displayText ?? "Lisää ajankohta")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Elder.supporting)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }
                }
            }

            Section {
                Button {
                    isTelling = true
                } label: {
                    Label("Kerro tästä muisto", systemImage: "mic.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Relationships only for people: a photo or an event has none.
            if subject.kind == .person {
                RelationsSection(subject: subject)
            }

            let memories = store.memories(for: subject.id)
            if memories.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kukaan ei ole vielä kertonut mitään. Paina yllä olevaa nappia ja ala puhua.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)

                        // A photograph nobody has told about yet can go: the
                        // wrong side of a print, a blurred one, the same one
                        // twice — the batch camera guarantees a few, and until
                        // 4 Sep 2026 they stayed forever, each holding one of
                        // the free slots (the count is a total, and the server
                        // frees a tombstoned photo's place). Only while it
                        // holds nothing, which is why it lives in this empty
                        // state: once a story is filed under it, rule 3 applies
                        // to the story, and the story is taken back first, on
                        // its own row. The same tombstone as a rejected person,
                        // so it reaches the family.
                        //
                        // In this row and not a section of its own: alone in a
                        // section the audit reported the button's font as not
                        // following Dynamic Type in every shape it was tried
                        // in — plain, styled, as a Label — four runs; beside
                        // the text, in the shape the memory row's button has,
                        // it passes.
                        if removable {
                            Button(removalButton) { isConfirmingRemoval = true }
                                .buttonStyle(.borderless)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Elder.destructive)
                                .elderTapTarget()
                        }
                    }
                }
            } else {
                Section {
                    ForEach(memories) { memory in
                        MemoryRow(memory: memory)
                    }
                } header: {
                    // A List styles its own headers and footers below the
                    // contrast minimum. Saying the colour out loud is the only
                    // way to raise it.
                    Text(memories.count == 1 ? "1 muisto" : "\(memories.count) muistoa")
                        .foregroundStyle(Elder.supporting)
                }
            }

            let open = store.questions.filter { $0.subjectID == subject.id && !$0.answered }
            if !open.isEmpty {
                Section {
                    ForEach(open) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            // A person's name on a question turns a prompt into
                            // a request. AI questions stay unattributed — and
                            // so is your own here: with the default display
                            // name the line read "Minä kysyy", wrong in both
                            // conjugation and direction.
                            if let asker = question.authorName,
                               question.authorID != session.identity.memberID {
                                Text("\(asker) kysyy")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                            Label(question.text, systemImage: "questionmark.circle")
                                .elderBody()
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Avoimia kysymyksiä")
                        .foregroundStyle(Elder.supporting)
                }
            }

            Section {
                Button {
                    isAsking = true
                } label: {
                    Label("Kysy perheeltä", systemImage: "questionmark.bubble")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                }
                .buttonStyle(.bordered)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                // The person who knows is not the person who wonders: the
                // grandchild asks here, and the question waits on the family's
                // Tell screen where telling starts.
                Text("Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän.")
                    .foregroundStyle(Elder.supporting)
            }

        }
        .navigationTitle(current.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            removalTitle,
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Poista", role: .destructive) {
                store.remove(subjectID: subject.id)
                dismiss()
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
        .toolbar {
            if nameCameFromSpeech {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCorrectingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .elderTapTarget()
                    }
                    .accessibilityLabel("Korjaa nimi")
                }
            }
        }
        .task {
            guard image == nil else { return }
            guard let filename = await MediaLoader.imageFilename(
                for: subject, store: store, session: session
            ) else { return }
            image = await Task.detached(priority: .userInitiated) {
                MediaStore.loadImage(named: filename)
            }.value
        }
        .sheet(isPresented: $isTelling) {
            NavigationStack {
                TellScreen(target: subject, onClose: { isTelling = false })
            }
        }
        .sheet(isPresented: $isAsking) {
            AskQuestionSheet(subject: subject)
        }
        .sheet(isPresented: $isDating) {
            DateSheet(subject: current)
        }
        .sheet(isPresented: $isCorrectingName) {
            CorrectNameSheet(subject: current) { merged in
                // The correction turned out to name somebody the family already
                // had, so this card is now a tombstone pointing at theirs. There
                // is nothing left to look at here — the memories have moved.
                if merged { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var photoView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }
}

private struct MemoryRow: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoval = false
    @State private var isEditingText = false
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if memory.isAwaitingTranscription {
                // Two different truths, and the app must not tell the first one
                // after it has stopped trying. "Teksti valmistuu myöhemmin" was
                // a promise nothing kept for a while (§16); it must not become
                // one again on the recordings the catch-up has given up on.
                Label(
                    // The chosen local mode first: there the text is not late
                    // and not given up on — it is simply never coming, and
                    // "valmistuu myöhemmin" would be a promise nothing keeps
                    // (finding B4).
                    session.isLocalByChoice
                        ? "Ääni tallessa — voit kirjoittaa tekstin itse"
                        : TranscriptionAttempts.hasGivenUp(on: memory.id)
                            ? "Ääni tallessa — tekstiä ei saatu tästä nauhoituksesta"
                            : "Ääni tallessa — teksti valmistuu myöhemmin",
                    systemImage: "waveform"
                )
                .elderBody()
                .foregroundStyle(Elder.supporting)
            } else {
                Text(memory.body)
                    .elderBody()
            }

            HStack(spacing: 12) {
                // Subheadline, matching the "X kertoi" line on the Uutta
                // perheeltä row: who told this matters most exactly when
                // several members write on one subject, and it was the
                // smallest text in the whole reading loop.
                Text(memory.authorName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Elder.supporting)

                // The original audio is part of the product, not a step towards it.
                if memory.audioFilename != nil || memory.audioR2Key != nil {
                    MemoryPlaybackButton(memory: memory)
                }
            }

            // The teller's own, the day after. The result screen offers this
            // in the seconds after telling; a memory read back on its card
            // tomorrow is the same "I did not mean to say that", and until
            // 3 Sep 2026 the card had no answer to it. Quiet and last, as on
            // the result screen: the rarest thing done here, and the one that
            // must never be hit by mistake — so it asks first, in the same
            // words.
            //
            // Own means told on this phone or by this member. A memory told
            // here carries no author until the pull hands it back, and one
            // that never syncs (a phone kept to itself) never gets one; the
            // server refuses a tombstone from anybody but the author either way.
            if memory.authorID == nil || memory.authorID == session.identity.memberID {
                // The words the family reads, corrected by the one who said
                // them. The name step reaches a heard name; a wrong ordinary
                // word in the one sentence that mattered — "kuoli" for
                // "kasvoi" — it cannot, and at the measured error rate that
                // word is common. No model call and no minutes: the body is
                // rewritten by hand, and rule 3's recording and raw transcript
                // stay exactly as they were. Not while the text is still on
                // its way: there is nothing to correct yet.
                if !memory.isAwaitingTranscription {
                    Button("Muokkaa tekstiä") { isEditingText = true }
                        .buttonStyle(.borderless)
                        .font(.body.weight(.medium))
                        .elderTapTarget()
                }

                Button("Poista tämä muisto") { isConfirmingRemoval = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Elder.destructive)
                    .elderTapTarget()
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Poista", role: .destructive) {
                // A moment that held only this telling goes with it, and the
                // card being read is then that moment's: nothing to stay for.
                if store.takeBack(memoryID: memory.id) { dismiss() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Muisto poistuu perheen arkistosta äänityksineen, eikä sitä voi palauttaa.")
        }
        .sheet(isPresented: $isEditingText) {
            MemoryTextSheet(memory: memory)
        }
    }
}

/// The teller rewrites the words the family reads.
///
/// The recording and the raw transcript are rule 3's, and this never touches
/// them: only `body`, through the same `updateBody` the name correction uses,
/// so the server's author rule applies here exactly as it does there.
private struct MemoryTextSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let memory: Memory

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(memory: Memory) {
        self.memory = memory
        _text = State(initialValue: memory.body)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // The same field the question sheet uses, for the same reasons
                // (see AskQuestionSheet): it grows with what is in it and stays
                // under the audit. Capped so a long telling scrolls inside the
                // field rather than pushing the buttons under the keyboard.
                TextField("Muiston teksti", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.body)
                    .lineSpacing(Elder.lineSpacing)
                    .padding(12)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                    .focused($isFocused)
                    .accessibilityLabel("Muiston teksti")

                Text("Alkuperäinen äänitys ja sanatarkka puhe säilyvät ennallaan.")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    save()
                } label: {
                    Text("Tallenna")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .elderTapTarget()
                // An empty body is not a correction: the row would read as a
                // recording still waiting for its text, and the server keeps
                // the old words on an empty push anyway.
                .disabled(trimmed.isEmpty || trimmed == memory.body)

                Button("Peruuta") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
            }
            .padding(Elder.screenPadding)
            .navigationTitle("Muokkaa tekstiä")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { isFocused = true }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        store.updateBody(memoryID: memory.id, body: trimmed)
        dismiss()
    }
}

#Preview {
    RootView()
        .environment(MemoryStore(filename: "preview-store.json"))
}
