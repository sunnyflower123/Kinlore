import SwiftUI

/// Three tabs, because four is already too many to remember.
/// Telling is in the middle and is the default — the app opens on what it exists
/// for, not on a list.
struct RootView: View {
    private enum Tab: Hashable {
        case memories, tell, people

        /// Telling is the default: the app opens on what it exists for, not on
        /// a list.
        ///
        /// Development and screenshot aid: `-tab memories` or `-tab people` as
        /// a launch argument opens the given tab directly, so screenshots can be
        /// taken without any tapping. DEBUG builds only.
        static var initial: Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "tab") {
            case "memories": return .memories
            case "people": return .people
            default: break
            }
            #endif
            return .tell
        }
    }

    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var selection: Tab = Tab.initial

    /// Rounds waiting to be guessed. The app opens on Kerro, so without this the
    /// only way to find out that somebody is waiting for an answer is to go
    /// looking — and nobody goes looking in a photo gallery. The badge appears
    /// only when there is something to do and disappears when it is done.
    private var waitingRounds: Int {
        GuessRoundBuilder.roundsWaiting(store: store, memberID: session.identity.memberID)
    }

    var body: some View {
        TabView(selection: $selection) {
            GalleryScreen()
                .tabItem { Label("Muistot", systemImage: "photo.on.rectangle.angled") }
                .badge(waitingRounds)
                .tag(Tab.memories)

            TellScreen()
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

/// The people in the family. The same `subject` table as the photos and the same
/// memory view — only the listing differs.
struct PeopleScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.subjects(of: .person).isEmpty {
                    ContentUnavailableView {
                        Label("Ei vielä ihmisiä", systemImage: "person.2")
                    } description: {
                        Text("Suvun henkilöt kertyvät tähän sitä mukaa kun heistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }
                } else {
                    List(store.subjects(of: .person)) { person in
                        NavigationLink(value: person) {
                            PersonRow(subject: person)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Ihmiset")
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
                    Label("Kerro hänestä", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
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

    var body: some View {
        List {
            if subject.kind == .photo {
                Section {
                    photoView
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if let hint = subject.dateHint, hint.precision != .unknown {
                Section {
                    Label(hint.displayText, systemImage: "calendar")
                        .foregroundStyle(Elder.supporting)
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
                    Text("Kukaan ei ole vielä kertonut mitään. Paina yllä olevaa nappia ja ala puhua.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
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
                            // a request. AI questions stay unattributed.
                            if let asker = question.authorName {
                                Text("\(asker) kysyy")
                                    .font(.caption.weight(.medium))
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
                TellScreen(target: subject)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Sulje") { isTelling = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isAsking) {
            AskQuestionSheet(subject: subject)
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
    let memory: Memory

    /// Who recognised the person from this story. The teller's half of the
    /// guessing round: not a score, but the news that the family still knows who
    /// she meant.
    private var recognitionText: String? {
        let names = store.recognisers(of: memory, excluding: session.identity.memberID)
        guard let first = names.first else { return nil }
        return names.count == 1
            ? "\(first) tunnisti hänet"
            : "\(names.count) perheenjäsentä tunnisti hänet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if memory.isAwaitingTranscription {
                // Two different truths, and the app must not tell the first one
                // after it has stopped trying. "Teksti valmistuu myöhemmin" was
                // a promise nothing kept for a while (§16); it must not become
                // one again on the recordings the catch-up has given up on.
                Label(
                    TranscriptionAttempts.hasGivenUp(on: memory.id)
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
                Text(memory.authorName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Elder.supporting)

                // The original audio is part of the product, not a step towards it.
                if memory.audioFilename != nil || memory.audioR2Key != nil {
                    MemoryPlaybackButton(memory: memory)
                }
            }

            if let recognitionText {
                Label(recognitionText, systemImage: "checkmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    RootView()
        .environment(MemoryStore(filename: "preview-store.json"))
}
