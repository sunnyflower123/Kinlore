import SwiftUI

/// Kolme välilehteä, koska neljä on jo liikaa muistettavaksi.
/// Kertominen on keskellä ja se on oletusvalinta — sovellus avautuu siihen
/// mitä varten se on olemassa, ei listaan.
struct RootView: View {
    private enum Tab: Hashable {
        case memories, tell, people

        /// Kertominen on oletus: sovellus avautuu siihen mitä varten se on
        /// olemassa, ei listaan.
        ///
        /// Kehitys- ja kuvausapu: `-tab muistot` tai `-tab ihmiset`
        /// käynnistysargumenttina avaa suoraan halutun välilehden, jotta
        /// kuvakaappauksia saa ilman napautuksia. Vain DEBUG-buildissa.
        static var initial: Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "tab") {
            case "muistot": return .memories
            case "ihmiset": return .people
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

/// Suvun henkilöt. Sama `subject`-taulu kuin kuvilla, sama muistonäkymä —
/// vain listaus poikkeaa.
struct PeopleScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
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
            .toolbar {
                // Perhe kuuluu Ihmisten yhteyteen eikä omaksi välilehdekseen:
                // kolme välilehteä on jo raja sille mitä 80-vuotias muistaa.
                if session.mode != .local {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            FamilyScreen()
                        } label: {
                            Image(systemName: "person.2.badge.gearshape")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Perheen asetukset")
                    }
                }
            }
        }
    }
}

private struct PersonRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            // Kuvake kertoo tilan muodollaan, ei pelkällä värillä: merkityksen
            // koodaaminen väriin yksin on saavutettavuusvirhe, ja tämän
            // sovelluksen käyttäjä on juuri se joka siitä kärsii.
            Image(systemName: subject.confirmed
                ? "person.crop.circle"
                : "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(subject.confirmed ? Color.secondary : Color.orange)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))

                // Kaksi eri asiaa, kaksi eri signaalia. Oranssi ja sana
                // "Ehdotus" = tarkista tämä. Sininen ja mikrofoni = tee tämä.
                if !subject.confirmed {
                    Text("Ehdotus — vahvista henkilö")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                } else if store.memories(for: subject.id).isEmpty {
                    // Aukkoa ei piiloteta vaan näytetään kutsuna.
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

/// Kuvan, henkilön ja tapahtuman näkymä on sama: kohde ja siihen kertyneet
/// muistot. Tämä on `subject`-taulun konkreettinen hyöty — yksi näkymä kolmen
/// sijaan.
struct SubjectDetailScreen: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    @State private var image: UIImage?
    @State private var isTelling = false

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
                        Label(question.text, systemImage: "questionmark.circle")
                            .elderBody()
                    }
                }
            }
        }
        .navigationTitle(subject.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard image == nil, let filename = subject.imageFilename else { return }
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
            Text(memory.body)
                .elderBody()

            HStack(spacing: 10) {
                Text(memory.authorName)
                    .font(.caption.weight(.medium))
                if memory.source == .voice, let duration = memory.audioDuration {
                    // Alkuperäinen ääni on osa lopputuotetta, ei välivaihe.
                    Label("\(Int(duration)) s", systemImage: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    RootView()
        .environment(MemoryStore(filename: "preview-store.json"))
}
