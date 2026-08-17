import PhotosUI
import SwiftUI

/// The family's photos and the events that have been told about.
///
/// Photos as a grid, events as a list — the same `subject` table, a different
/// presentation. A grid because an old photograph is recognised by looking at
/// it, not by reading a title.
struct GalleryScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(SyncEngine.self) private var sync: SyncEngine?

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var picked: [PhotosPickerItem] = []
    @State private var isImporting = false
    /// How many of the chosen photos did not make it, and whether that has been
    /// said out loud yet.
    @State private var skipped = 0
    @State private var isReportingSkipped = false
    /// What the last import brought in. Held so the date can be asked once for
    /// the whole pile rather than thirty times, or not at all.
    @State private var justImported: [Subject] = []
    #if DEBUG
    @State private var didSeedImport = false
    #endif

    /// Bigger tiles when the text is bigger. The memory-count badge scales with
    /// Dynamic Type, and at accessibility sizes it was clipped by a 110 pt tile —
    /// the count simply ran off the edge. Larger photographs are the right answer
    /// for this user anyway; the grid just holds fewer per row.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 170 : 110), spacing: 10)]
    }

    private var photos: [Subject] { store.subjects(of: .photo, matching: query) }
    private var events: [Subject] { store.subjects(of: .event, matching: query) }
    /// Places the family has spoken about.
    ///
    /// They arrive the same way people do — named inside a memory, created as a
    /// subject — and until this section existed nothing listed them, so a place
    /// card could not be opened at all. Its memories were invisible, its starter
    /// questions could never be asked, and "Kysy perheeltä" could not be used on
    /// it. A subject nobody can reach is not part of the archive.
    private var places: [Subject] { store.subjects(of: .place, matching: query) }

    /// What is typed in the search field.
    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nothingMatches: Bool {
        photos.isEmpty && events.isEmpty && places.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                // Three states, and the search has to be asked about first.
                if isSearching {
                    // An archive with nothing in it is an invitation; a search
                    // that found nothing is a dead end, and offering "lisää
                    // kuvia" there would answer a question nobody asked.
                    if nothingMatches { noResults } else { content }
                } else if nothingMatches {
                    // A phone that has just joined a family is empty in a
                    // different way from a family nobody has told anything:
                    // its content exists and is on its way. The invitation —
                    // "Lisää vanha valokuva…" — is a false sentence there, for
                    // exactly as long as the first pull takes.
                    if isAwaitingFamilyContent { arrivalState } else { emptyState }
                } else {
                    content
                }
            }
            .navigationTitle("Muistot")
            .searchable(text: $query, prompt: "Etsi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .elderTapTarget()
                    }
                    .accessibilityLabel("Lisää kuvia")
                }
            }
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailScreen(subject: subject)
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .overlay {
                if isImporting {
                    ProgressView("Tuodaan kuvia")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            // A photo that would not load used to be skipped in silence: you
            // chose ten, eight arrived, and nothing said which or why. Counting
            // your own photographs to find that out is not a thing to ask of
            // anybody, least of all of somebody who scanned them.
            // Offered, not imposed: the sheet can be swiped away and the photos
            // are already in the archive. Nothing here is a step in an import
            // that would otherwise be unfinished.
            .sheet(isPresented: Binding(
                get: { !justImported.isEmpty },
                set: { if !$0 { justImported = [] } }
            )) {
                DateSheet(subjects: justImported)
            }
            #if DEBUG
            // `-import 3`: the question an import asks, without the system photo
            // picker in front of it. A test run cannot drive that picker, so the
            // one screen the bulk path exists for was unreachable — the same
            // hole `-mic denied` and `-screen result` were written for.
            .task {
                // Once per launch. A `task` runs again when the view comes back
                // — returning from a photo's card is enough — and a second
                // helping would put three more photographs in the archive and
                // the sheet back over the grid.
                guard !didSeedImport,
                      let count = UserDefaults.standard.string(forKey: "import").flatMap(Int.init),
                      count > 1
                else { return }
                didSeedImport = true
                justImported = (0 ..< count).map { _ in
                    let subject = Subject(kind: .photo, title: "")
                    store.add(subject)
                    return subject
                }
            }
            #endif
            .alert("Kaikkia kuvia ei saatu tuotua", isPresented: $isReportingSkipped) {
                Button("Selvä") { isReportingSkipped = false }
            } message: {
                Text(skipped == 1
                    ? "Yksi kuva jäi tuomatta. Voit yrittää sitä uudelleen."
                    : "\(skipped) kuvaa jäi tuomatta. Voit yrittää niitä uudelleen.")
            }
        }
    }

    /// The first pull after joining is running and nothing has arrived yet.
    ///
    /// Only while it actually runs: a pull that failed leaves the ordinary
    /// invitation as the honest screen, and the sync note's philosophy holds —
    /// the queue looks after itself, so nothing here asks for anything. See
    /// docs/UX.md §4.3.
    private var isAwaitingFamilyContent: Bool {
        #if DEBUG
        // `-seed arrival` holds this state still for the audit. Nothing else
        // can: it exists only while a network request is in flight.
        if UserDefaults.standard.string(forKey: "seed") == "arrival" { return true }
        #endif
        guard let sync, sync.isEnabled, sync.state == .syncing else { return false }
        return store.syncSeq == 0
    }

    /// Shown in place of the empty state during that first pull. No button on
    /// purpose: the content is on its way, and the one wrong thing to offer a
    /// joiner is a way to start building a second archive beside it.
    private var arrivalState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                // The sentence carries the meaning; a spinner read aloud as
                // "in progress" beside it says less than nothing.
                .accessibilityHidden(true)
            Text("Haetaan perheen muistoja…")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Elder.screenPadding)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ei vielä kuvia", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Lisää vanha valokuva, niin koko perhe voi kertoa siitä omat muistonsa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
        } actions: {
            PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                Text("Valitse kuvia")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("Ei osumia", systemImage: "magnifyingglass")
        } description: {
            Text("Mikään ei löytynyt haulla \"\(query)\". Haku etsii kerrotusta tekstistä ja kohteiden nimistä.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Neither of these belongs in a search result: one says
                // something about the whole archive, the other is a question
                // waiting to be answered. Somebody looking for a memory is not
                // looking for either.
                if !isSearching {
                    // Whether what she told has actually reached the family. The
                    // engine has known this from the beginning and nothing asked it.
                    SyncNote()
                }

                if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Kuvat")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(photos) { photo in
                                NavigationLink(value: photo) {
                                    PhotoTile(subject: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !events.isEmpty {
                    listSection("Kerrotut hetket", of: events)
                }

                // Below the moments, because a place is usually a way into a
                // memory rather than the memory itself: most of these have
                // nothing on them yet, and an empty card here is an invitation
                // exactly as it is on the person list.
                if !places.isEmpty {
                    listSection("Paikat", of: places)
                }
            }
            .padding(Elder.screenPadding)
        }
    }

    /// One section, one row type, whatever kind of subject is in it.
    ///
    /// Moments and places are listed by exactly the same code, because they are
    /// the same row of the same table — the point the whole `subject` design
    /// rests on. A second row type for places would have been the beginning of
    /// the parallel implementations CLAUDE.md forbids.
    private func listSection(_ title: String, of subjects: [Subject]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title)
            ForEach(subjects) { subject in
                NavigationLink(value: subject) {
                    SubjectRow(subject: subject)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        skipped = 0
        defer {
            isImporting = false
            picked = []
            // Only when something actually went missing. An import that worked
            // needs no announcement — the photographs are on the screen.
            isReportingSkipped = skipped > 0
        }

        var arrived: [Subject] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let filename = MediaStore.save(imageData: data)
            else {
                skipped += 1
                continue
            }

            // The title is left empty on purpose: nobody will name thirty
            // scanned photographs. The name arrives when someone talks about
            // the photo, and it is not needed before that.
            //
            // The *date* is a different matter, and it is the one thing thirty
            // photographs usually share. It is asked once below.
            let subject = Subject(kind: .photo, title: "", imageFilename: filename)
            store.add(subject)
            arrived.append(subject)
        }

        // Asked for two or more, and never for one: a single photograph is
        // opened and looked at, and its own card already carries the row. A
        // pile is the case with no such moment — thirty cards nobody will open
        // thirty times.
        justImported = arrived.count > 1 ? arrived : []
    }
}

/// "Is this still only on my phone?"
///
/// The one question the app could not answer. A memory told at a cottage with no
/// signal looked exactly like one the whole family had already read, and the
/// difference is the entire promise of the app — `SyncEngine` has carried the
/// state since it was written and no view ever read it.
///
/// It says nothing at all when everything is through, which is nearly always:
/// this is a waiting state and not a permanent piece of furniture. It asks for
/// nothing either. The queue drains by itself, so telling somebody to do
/// something about the network would be inventing a job for them — the words say
/// what is true and that it fixes itself.
private struct SyncNote: View {
    @Environment(MemoryStore.self) private var store
    @Environment(SyncEngine.self) private var sync: SyncEngine?

    var body: some View {
        // Nothing without a family and a backend: a single-device archive has
        // nowhere to send anything, and "odottaa lähetystä" would be a worry
        // about a thing that is not going to happen.
        if let sync, sync.isEnabled, store.waitingToBeSent > 0 {
            Label(text(waiting: store.waitingToBeSent, state: sync.state), systemImage: symbol(sync.state))
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func text(waiting: Int, state: SyncEngine.State) -> String {
        if state == .syncing { return "Lähetetään perheelle…" }
        return waiting == 1
            ? "Yksi muisto on vielä vain tässä puhelimessa. Se lähtee perheelle itsestään kun verkko palaa."
            : "\(waiting) muistoa on vielä vain tässä puhelimessa. Ne lähtevät perheelle itsestään kun verkko palaa."
    }

    /// The shape carries the same meaning as the words, as everywhere else in
    /// this app: a phone on its own, or something on its way up.
    private func symbol(_ state: SyncEngine.State) -> String {
        state == .syncing ? "arrow.up.circle" : "iphone"
    }
}

private struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
    }
}

private struct PhotoTile: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    let subject: Subject

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // The memory count says what has already been talked about and what
            // has not. An empty photo is not an error but an invitation — which
            // is why the badge is always visible.
            let count = store.memories(for: subject.id).count
            Label(
                count == 0 ? "Kerro" : "\(count)",
                systemImage: count == 0 ? "mic.fill" : "text.bubble.fill"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            // Bounded growth: the badge sits on top of a photograph, so past a
            // point it stops being a label and starts being the tile. The count
            // is also in the tile's accessibility label and on the detail screen,
            // so nothing is only available here.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .task {
            guard thumbnail == nil else { return }
            // A photo added by another family member is at first only a key: it
            // is fetched when the screen actually needs it.
            guard let filename = await MediaLoader.imageFilename(
                for: subject, store: store, session: session
            ) else { return }
            thumbnail = await Task.detached(priority: .userInitiated) {
                MediaStore.loadThumbnail(named: filename)
            }.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.memories(for: subject.id).isEmpty
                ? "Valokuva, ei vielä muistoja"
                : "Valokuva, \(store.memories(for: subject.id).count) muistoa"
        )
    }
}

/// A moment or a place, listed. The icon is the only difference between them,
/// and it comes from the kind rather than from a row written per kind.
private struct SubjectRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: subject.kind.symbolName)
                .font(.title2)
                .foregroundStyle(Elder.supporting)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                // An event whose memory is still waiting for its text has no
                // title yet, and a blank row would look like a broken one.
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                subtitle
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Elder.supporting)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    /// A subject nobody has said anything about yet is shown as an invitation
    /// rather than as a zero — the same way an empty person is on the people
    /// list, and worded the same. For a place that is the common case, because a
    /// place is usually named inside a memory rather than being the memory.
    /// PLAN.md §6.5: gaps are shown.
    @ViewBuilder
    private var subtitle: some View {
        let count = store.memories(for: subject.id).count
        if count == 0 {
            // The microphone says what to do, so the meaning does not rest on
            // the colour alone.
            // Not tinted, for the third time in this app and for the reason
            // the guessing round's card recorded once already (§13): blue on
            // this grey passes the contrast check only *nearly*, and nearly is
            // not a pass for an 80-year-old's eyes. It failed outright at 24.4
            // points above the tab bar — inside the fade, just outside the
            // forgiveness band, which makes it a coin toss rather than a
            // colour. Weight carries the invitation now, and the microphone
            // carries the meaning as it always did.
            Label("Kerro tästä", systemImage: "mic.fill")
                .font(.subheadline.weight(.semibold))
        } else {
            Text(count == 1 ? "1 muisto" : "\(count) muistoa")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
        }
    }
}

#Preview {
    GalleryScreen()
        .environment(MemoryStore(filename: "preview-store.json"))
}
