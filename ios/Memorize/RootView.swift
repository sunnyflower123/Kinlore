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

    @State private var selection: Tab = Tab.initial

    var body: some View {
        TabView(selection: $selection) {
            GalleryScreen()
                .tabItem { Label("Muistot", systemImage: "photo.on.rectangle.angled") }
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
private struct FamilyRoute: Hashable {}

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
            .toolbar {
                // The family belongs under People rather than as its own tab:
                // three tabs is already the limit of what an 80-year-old holds
                // in mind.
                if session.mode != .local {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: FamilyRoute()) {
                            Image(systemName: "person.2.badge.gearshape")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Perheen asetukset")
                    }
                }
            }
            #if DEBUG
            // Screenshot aid, alongside `-tab` and `-screen write`. These two
            // screens sit behind a tap, and a screenshot run has no hands:
            //
            //   -screen person   the first person's card, relationships and all
            //   -screen family   members, usage and the invite link
            //
            // Checking a screen at the largest text size means opening it, and
            // this is how the two that were skipped stopped being skipped.
            .task {
                switch UserDefaults.standard.string(forKey: "screen") {
                case "person":
                    if let first = store.subjects(of: .person).first { path.append(first) }
                case "family":
                    path.append(FamilyRoute())
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
                .foregroundStyle(subject.confirmed ? Color.secondary : Color.orange)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))

                // Two different things, two different signals. Orange plus the
                // word "Ehdotus" = check this. Blue plus a microphone = do this.
                if !subject.confirmed {
                    Text("Ehdotus — vahvista henkilö")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                } else if store.memories(for: subject.id).isEmpty {
                    // A gap is not hidden but shown as an invitation.
                    Label("Kerro hänestä", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                } else {
                    let count = store.memories(for: subject.id).count
                    Text(count == 1 ? "1 muisto" : "\(count) muistoa")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    @State private var image: UIImage?
    @State private var isTelling = false
    @State private var isAsking = false

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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(memories.count == 1 ? "1 muisto" : "\(memories.count) muistoa") {
                    ForEach(memories) { memory in
                        MemoryRow(memory: memory)
                    }
                }
            }

            let open = store.questions.filter { $0.subjectID == subject.id && !$0.answered }
            if !open.isEmpty {
                Section("Avoimia kysymyksiä") {
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
            }
        }
        .navigationTitle(subject.displayTitle)
        .navigationBarTitleDisplayMode(.large)
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
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if memory.isAwaitingTranscription {
                Label("Ääni tallessa — teksti valmistuu myöhemmin", systemImage: "waveform")
                    .elderBody()
                    .foregroundStyle(.secondary)
            } else {
                Text(memory.body)
                    .elderBody()
            }

            HStack(spacing: 12) {
                Text(memory.authorName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                // The original audio is part of the product, not a step towards it.
                if memory.audioFilename != nil || memory.audioR2Key != nil {
                    MemoryPlaybackButton(memory: memory)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    RootView()
        .environment(MemoryStore(filename: "preview-store.json"))
}
