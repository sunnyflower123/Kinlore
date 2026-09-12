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
    /// The two ways a photograph gets in. The camera is the one the archive was
    /// waiting for — an 80-year-old's photographs are in an album on a shelf,
    /// not in this phone's library — and the picker stays because a grandchild
    /// scanning at a computer already has files.
    @State private var isPhotographing = false
    @State private var isPickingFromLibrary = false
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
    private var events: [Subject] { Self.byDate(store.subjects(of: .event, matching: query)) }

    /// The photographs by decade — the one order a family thinks in, and the
    /// one nothing here used. `dateHint` is asked for by a sheet of its own
    /// and, until 6 Sep 2026, sorted nothing: the grid was in the order the
    /// album happened to be scanned (founder's-eye review, finding #10), and
    /// "show me the fifties" had no answer on a screen whose whole point is
    /// finding. Dated photographs come first, oldest decade first and oldest
    /// first within it; the ones nobody has dated follow under a heading of
    /// their own, newest scanned first as before. When nothing is dated the
    /// grid is exactly as it was — a heading over the whole archive saying
    /// nobody has dated it would be a reproach, not a section.
    private struct PhotoGroup: Identifiable {
        enum Heading: Equatable {
            case decade(Int)
            case undated
        }

        let heading: Heading?
        let photos: [Subject]

        var id: String {
            switch heading {
            case .decade(let decade): "decade-\(decade)"
            case .undated: "undated"
            case nil: "all"
            }
        }
    }

    private var photoGroups: [PhotoGroup] {
        let dated = photos.compactMap { photo -> (photo: Subject, start: Date)? in
            guard let hint = photo.dateHint, hint.precision != .unknown, let start = hint.start else {
                return nil
            }
            return (photo, start)
        }
        guard !dated.isEmpty else { return [PhotoGroup(heading: nil, photos: photos)] }
        let calendar = Calendar.current
        let byDecade = Dictionary(grouping: dated) { calendar.component(.year, from: $0.start) / 10 * 10 }
        var groups = byDecade.keys.sorted().map { decade in
            PhotoGroup(
                heading: .decade(decade),
                photos: (byDecade[decade] ?? []).sorted { $0.start < $1.start }.map(\.photo)
            )
        }
        let datedIDs = Set(dated.map(\.photo.id))
        let undated = photos.filter { !datedIDs.contains($0.id) }
        if !undated.isEmpty {
            groups.append(PhotoGroup(heading: .undated, photos: undated))
        }
        return groups
    }

    /// The dated moments in the order they happened, oldest first; the
    /// undated after them, newest told first as before. Same finding as the
    /// grid above, on the list under it.
    private static func byDate(_ subjects: [Subject]) -> [Subject] {
        let dated = subjects.compactMap { subject -> (subject: Subject, start: Date)? in
            guard let hint = subject.dateHint, hint.precision != .unknown, let start = hint.start else {
                return nil
            }
            return (subject, start)
        }
        .sorted { $0.start < $1.start }
        let datedIDs = Set(dated.map(\.subject.id))
        return dated.map(\.subject) + subjects.filter { !datedIDs.contains($0.id) }
    }
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

    /// Tellings by other members this phone had not seen when this tab was
    /// opened. Captured on appearance *before* they are marked seen, so the
    /// section survives its own visit: what was new stays on screen until the
    /// next arrival at this tab, and the next arrival starts clean.
    @State private var newFromFamily: [Memory] = []
    /// The blind card for a grandparent's phone, fetched once per appearance
    /// like the Kerro tab's, and gone once answered.
    @State private var blind: BlindConfirmation.Card?
    @AppStorage(Elder.largerTextKey) private var largerText = false
    /// The cards pushed on top of this tab. Owned here so a pop-back can be
    /// told apart from an arrival — see `isReturningFromCard`.
    @State private var path: [Subject] = []
    /// Whether the next appearance of this root is a return from a pushed
    /// card rather than an arrival at the tab. Set when a push covers the
    /// root (the path is non-empty at that moment), consumed by `onAppear`.
    /// Without it, reading ONE of three new tellings erased the other two:
    /// the pop-back re-ran the capture after everything was already marked
    /// seen, so the section supported exactly one read per visit and the
    /// rest left no trace anywhere.
    @State private var isReturningFromCard = false

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nothingMatches: Bool {
        photos.isEmpty && events.isEmpty && places.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                    //
                    // The refused note above either, because an empty archive
                    // is exactly where a reader's phone the server has
                    // forgotten stands: nothing arrived, nothing will, and the
                    // invitation to photograph an album is the wrong sentence.
                    VStack(spacing: 0) {
                        RefusedNote()
                            .padding([.horizontal, .top], Elder.screenPadding)
                        if isAwaitingFamilyContent {
                            arrivalState
                        } else if isMissingFamilyContent {
                            notArrivedState
                        } else {
                            emptyState
                        }
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Muistot")
            .onAppear {
                // A pop-back from a card is a visit already in progress, not
                // a new arrival: the captured section stays, the seen-marking
                // has already happened. A tab switch leaves the flag false,
                // so returning to the tab still starts clean — the half
                // `testNewFromFamilyClearsOnceSeen` pins.
                if isReturningFromCard {
                    isReturningFromCard = false
                    return
                }
                newFromFamily = NewFromFamily.unseen(in: store, me: session.identity.memberID)
                if largerText, blind == nil,
                   store.openQuestions(limit: 1, excludingAuthor: session.identity.memberID).isEmpty {
                    blind = BlindConfirmation.next(in: store)
                }
                // The baseline is not written while the first pull is still
                // owed. A joiner's arrival used to mark an EMPTY store as
                // seen, and the pull then landed the whole family archive on
                // the wrong side of that baseline — every telling "new" at
                // once, burying the photographs under the exact dump the
                // first-visit rule exists to prevent. Until the cursor has
                // moved, being here does not count as having seen anything.
                guard !(sync?.isEnabled == true && store.syncSeq == 0) else { return }
                NewFromFamily.markAllSeen(in: store)
            }
            .onDisappear {
                isReturningFromCard = !path.isEmpty
            }
            .searchable(text: $query, prompt: Text("Etsi"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // A menu rather than two buttons: the bar has room for one
                    // control at the largest text size, and the second way in
                    // would be the one to fall off it.
                    //
                    // The camera is first because it is the case this app is
                    // for. `PhotosPicker` does not survive being a menu row, so
                    // both rows are plain buttons and the picker is presented
                    // from the flag one of them sets.
                    Menu {
                        Button {
                            isPhotographing = true
                        } label: {
                            Label("Kuvaa vanha valokuva", systemImage: "camera")
                        }
                        Button {
                            isPickingFromLibrary = true
                        } label: {
                            Label("Valitse kuvista", systemImage: "photo.on.rectangle.angled")
                        }
                    } label: {
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
            // Full screen rather than a sheet: a camera under a card that can
            // be dragged away is a camera that gets dragged away mid-album.
            .fullScreenCover(isPresented: $isPhotographing) {
                CameraScreen(pickFromLibraryInstead: { isPickingFromLibrary = true })
            }
            #if DEBUG
            // `-screen camera`, alongside the other screenshot aids: the camera
            // sits behind a menu row, and a screenshot run has no hands. It
            // pairs with `-camera stub|denied|unavailable`, which choose which
            // of its three states is drawn — on a simulator, where there is no
            // camera at all, only one of them is otherwise reachable.
            .task {
                if UserDefaults.standard.string(forKey: "screen") == "camera" {
                    isPhotographing = true
                }
            }
            #endif
            .photosPicker(
                isPresented: $isPickingFromLibrary,
                selection: $picked,
                matching: .images,
                photoLibrary: .shared()
            )
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
                    ? String(localized: "Yksi kuva jäi tuomatta. Voit yrittää sitä uudelleen.")
                    : String(localized: "\(skipped) kuvaa jäi tuomatta. Voit yrittää niitä uudelleen."))
            }
            .elderSurface()
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

    /// The first pull after joining failed, and nothing has arrived.
    ///
    /// The case between the two around it, and until 6 Sep 2026 it fell
    /// through to the invitation: the state after a failed round is
    /// `waitingForNetwork`, not `syncing`, so a joiner whose kitchen Wi-Fi
    /// dropped under the first pull was told the archive was empty and asked
    /// to photograph an album — the second archive beside the family's that
    /// the arrival state exists to prevent (founder's-eye review, finding
    /// #63). The cursor at zero is what says no reply has ever been applied;
    /// a family that genuinely has nothing answers the pull, the engine goes
    /// idle, and the invitation is the true screen again.
    private var isMissingFamilyContent: Bool {
        guard let sync, sync.isEnabled, sync.state == .waitingForNetwork else { return false }
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

    /// Shown in place of the invitation when that first pull failed. The words
    /// say what happened and that it fixes itself — the engine watches the
    /// network come back — and the button is for the person standing in the
    /// kitchen: the same round, a tap sooner. Same shape as the invitation
    /// below it, for the same audit reasons.
    private var notArrivedState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Perheen muistoja ei saatu haettua")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Yhteyttä ei nyt saatu. Mikään ei ole kadonnut: haetaan uudelleen itsestään, kun verkko palaa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Button {
                Task { await sync?.sync() }
            } label: {
                Text("Hae nyt uudelleen")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .padding(Elder.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The invitation, and no longer a `ContentUnavailableView`.
    ///
    /// It was one, and the framework caps how far its title, description and
    /// actions grow with Dynamic Type — which is why `AccessibilityPolicy`
    /// exempts its labels by name. That exemption comes with an instruction:
    /// *"if the system view ever stops being good enough, the answer is to stop
    /// using it, not to widen this list."*
    ///
    /// It stopped. This screen now needs two ways in, with the camera first,
    /// and a `Button` in that view's action slot fails the audit as "Dynamic
    /// Type font sizes are partially unsupported" in every shape it can be
    /// written in — measured five ways, and a `PhotosPicker` in the same slot
    /// passes only because its label is on the exemption list. Capped text on
    /// the one screen an empty archive shows is the wrong trade in an app whose
    /// first rule is the text size.
    ///
    /// So the words are ours now, and they grow. The three strings this screen
    /// owns came off the exemption list with it.
    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Ei vielä kuvia")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The sentence changed with the screen. It used to say "lisää",
            // which quietly assumed the photographs were already on the phone;
            // they are in an album on a shelf, and somebody has to photograph
            // them.
            Text("Kuvaa vanha valokuva albumista, niin koko perhe voi kertoa siitä omat muistonsa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            Button {
                isPhotographing = true
            } label: {
                Text("Kuvaa vanha valokuva")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Second, and quieter. A grandchild who has already scanned at a
            // computer has files; everybody else has an album.
            Button {
                isPickingFromLibrary = true
            } label: {
                Text("Valitse kuvista")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .padding(Elder.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    // What the family told while this phone was away — the
                    // reading half of the promise, facing the other way from
                    // the note below it. It exists when there is something and
                    // not when there is not, and being on this screen is what
                    // marks it seen: no badge, no count, no debt. docs/UX.md
                    // §6, and the hole PLAN §4.1 left open when the guessing
                    // round was cut.
                    // The blind card, on a grandparent's phone: the recognising
                    // is reading, and this is where she reads. Her Kerro tab
                    // keeps the button (see TellScreen.blindCard).
                    if let card = blind {
                        BlindCardView(card: card) { blind = nil }
                            .padding(.vertical, 8)
                    }

                    if !newFromFamily.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading("Uutta perheeltä")
                            ForEach(newFromFamily) { memory in
                                // A telling whose subject is gone — rejected,
                                // or taken back — has nowhere to lead.
                                if let subject = store.subject(id: memory.subjectID) {
                                    NavigationLink(value: subject) {
                                        NewTellingRow(memory: memory, subject: subject)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Whether what she told has actually reached the family. The
                    // engine has known this from the beginning and nothing asked it.
                    SyncNote()

                    // And the device the server has stopped knowing — a 401,
                    // not weather. It showed only inside SyncNote, and only
                    // while something waited to be sent: a reader's phone with
                    // an empty outbox fell silent for good (founder's-eye
                    // review, finding #57).
                    RefusedNote()

                    // And the one refusal that is not a waiting-for-network
                    // state: the free tier's photo ceiling, which used to be
                    // swallowed whole — the refused photograph looked normal
                    // in the grid and silently never reached the family.
                    PhotoQuotaNote()

                    // The same for the month's minutes, which had no note at
                    // all: a dozen tellings stranded on the quota were the
                    // one refusal shown as a delay.
                    MinutesQuotaNote()
                }

                if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Kuvat")
                        ForEach(photoGroups) { group in
                            if let heading = group.heading {
                                groupHeading(heading)
                            }
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.photos) { photo in
                                    NavigationLink(value: photo) {
                                        PhotoTile(subject: photo)
                                    }
                                    .buttonStyle(.plain)
                                }
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

    /// A decade, or the basket for what nobody has dated. A header for
    /// VoiceOver too, so the decades can be walked by heading.
    private func groupHeading(_ heading: PhotoGroup.Heading) -> some View {
        Group {
            switch heading {
            // A String, not the Int: an integer interpolated into a
            // `Text` is formatted for the locale, and Finnish groups
            // thousands — the heading read "1 950-luku" and the test
            // looking for "1950-luku" found nothing.
            case .decade(let decade): Text("\(String(decade))-luku")
            case .undated: Text("Ilman ajankohtaa")
            }
        }
        .font(.headline)
        .foregroundStyle(Elder.supporting)
        .accessibilityAddTraits(.isHeader)
    }

    /// One section, one row type, whatever kind of subject is in it.
    ///
    /// Moments and places are listed by exactly the same code, because they are
    /// the same row of the same table — the point the whole `subject` design
    /// rests on. A second row type for places would have been the beginning of
    /// the parallel implementations CLAUDE.md forbids.
    private func listSection(_ title: LocalizedStringKey, of subjects: [Subject]) -> some View {
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
                .elderCard()
        }
    }

    private func text(waiting: Int, state: SyncEngine.State) -> String {
        if state == .syncing { return String(localized: "Lähetetään perheelle…") }
        // A refused identity does not get the network's promise: "lähtee
        // itsestään kun verkko palaa" was said for a 401 too, indefinitely,
        // while no push could ever succeed. The full account is on the Perhe
        // screen; this line stays true and points there.
        if state == .refused {
            return waiting == 1
                ? String(localized: "Yksi muisto on vielä vain tässä puhelimessa. Lähetys ei nyt onnistu — katso Perhe-näkymä.")
                : String(localized: "\(waiting) muistoa on vielä vain tässä puhelimessa. Lähetys ei nyt onnistu — katso Perhe-näkymä.")
        }
        return waiting == 1
            ? String(localized: "Yksi muisto on vielä vain tässä puhelimessa. Se lähtee perheelle itsestään kun verkko palaa.")
            : String(localized: "\(waiting) muistoa on vielä vain tässä puhelimessa. Ne lähtevät perheelle itsestään kun verkko palaa.")
    }

    /// The shape carries the same meaning as the words, as everywhere else in
    /// this app: a phone on its own, or something on its way up.
    private func symbol(_ state: SyncEngine.State) -> String {
        state == .syncing ? "arrow.up.circle" : "iphone"
    }
}

/// "The server no longer knows this phone."
///
/// Not a waiting state, so it gets no waiting sentence: nothing fixes it by
/// itself. The words say what happened and what it costs, and the button is
/// the way back — a new invitation, joined without losing anything on this
/// phone (`Session.rejoin`). Until 5 Sep 2026 the only mention was a row on
/// the Perhe screen with no action, four taps away, and the documented way
/// back ran through "Poistu perheestä", which the same server refuses.
private struct RefusedNote: View {
    @Environment(SyncEngine.self) private var sync: SyncEngine?

    var body: some View {
        if let sync, sync.state == .refused {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "Perheen palvelin ei enää tunnista tätä puhelinta. Uudet muistot eivät saavu, eivätkä omat lähde. Pyydä perheeltä uusi kutsu ja liity sillä uudelleen: mikään tässä puhelimessa ei katoa.",
                    systemImage: "iphone.slash"
                )
                .elderBody()
                .foregroundStyle(Elder.supporting)

                Button {
                    sync.askToRejoin()
                } label: {
                    Label("Liity uudella kutsulla", systemImage: "person.badge.plus")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                // The 60 pt minimum on the control and not on the label inside
                // it: on the label it fights the button style over the box the
                // text goes in, and the audit reported the label as clipped on
                // the empty archive — `InviteShare` records the same lesson.
                .buttonStyle(.bordered)
                .elderTapTarget()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .elderCard()
        }
    }
}

/// "This photograph did not fit the free archive."
///
/// The other quiet note, and a different kind from `SyncNote` above it: that
/// one is a waiting state the queue fixes by itself, this one is an answer
/// about the family's ceiling that fixes itself only when there is room —
/// somebody pays, or a photograph is deleted elsewhere. So the words promise
/// the photo is safe and say when it travels, and nothing here is a modal or
/// a badge. The count comes from the engine's last round; going paid re-syncs
/// at once (`KinloreApp`), which is what clears it.
///
/// **One of those two acts is now offered.** The note kept the `SyncNote`
/// register for three weeks after `MinutesQuotaNote` below it left it: the
/// same ceiling shape, the same words about being safe, and — alone of the
/// two — no way up. The comment above had named the act since 17 Aug 2026
/// and the screen did not carry it, which is a worse silence than the one
/// that note was written to end, because a family that would have paid for
/// the room reads only that there is none.
private struct PhotoQuotaNote: View {
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var isShowingPaywall = false

    private var refused: Int {
        #if DEBUG
        // `-photos-refused <n>`: holds this state still for the audit. The
        // real one needs a running Worker and a family over its ceiling.
        if let forced = UserDefaults.standard.string(forKey: "photos-refused").flatMap(Int.init) {
            return forced
        }
        #endif
        return sync?.photosOverQuota ?? 0
    }

    /// Whether this note is the one that carries the way up.
    ///
    /// The two ceilings are independent — twenty photographs is a total, ten
    /// minutes is a month — so a family can sit under both at once, and both
    /// notes stand in the same column. Two identical buttons a finger apart
    /// is a worse screen than the one this fix started from, at the text size
    /// rule 1 asks for most of all.
    ///
    /// So the offer belongs to `MinutesQuotaNote` whenever it shows. Its claim
    /// is the stronger one: paying is the *only* act that brings the month's
    /// text sooner, while a photograph can also be made room for by deleting
    /// another. This note carries the button in the case that had none.
    private var carriesTheOffer: Bool {
        guard !session.isPaid, RevenueCatPurchases.configuredKey != nil else { return false }
        return !(session.isOutOfMinutes && tellingsAwaitingText(store) > 0)
    }

    var body: some View {
        if refused > 0 {
            VStack(alignment: .leading, spacing: 12) {
                // Two labels rather than a ternary, for the reason TellScreen
                // already carries beside "Selvä": a ternary of literals is a
                // String, and a String is not looked up. Neither table had
                // ever seen these two sentences, so an English phone read the
                // Finnish — found by launching `-photos-refused 1` in English
                // and looking, which is the only thing that finds this class.
                // `localisation-check.mjs` passes either way; it counts keys.
                Group {
                    if refused == 1 {
                        Label(
                            "Yksi kuva ei mahtunut ilmaiseen arkistoon. Se on tallessa tässä puhelimessa ja lähtee perheelle kun tilaa on.",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    } else {
                        Label(
                            "\(refused) kuvaa ei mahtunut ilmaiseen arkistoon. Ne ovat tallessa tässä puhelimessa ja lähtevät perheelle kun tilaa on.",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                }
                .elderBody()
                .foregroundStyle(Elder.supporting)

                if carriesTheOffer {
                    Button("Avaa koko arkisto") { isShowingPaywall = true }
                        .buttonStyle(.borderless)
                        .font(.body.weight(.semibold))
                        .elderTapTarget()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .elderCard()
            .paywallSheet(isPresented: $isShowingPaywall)
        }
    }
}

/// Recordings still without their text — the month's ceiling, counted.
///
/// Shared because `PhotoQuotaNote` above has to know whether the note below
/// it is showing before it offers the same purchase twice. Two copies of
/// this filter would drift, and the one that drifted would be the copy that
/// only decides whether a button appears — which no test looks at directly.
@MainActor
private func tellingsAwaitingText(_ store: MemoryStore) -> Int {
    #if DEBUG
    // `-minutes-out <n>`: holds this state still for the audit, with
    // `Session.isOutOfMinutes` forced by the same argument.
    if let forced = UserDefaults.standard.string(forKey: "minutes-out").flatMap(Int.init) {
        return forced
    }
    #endif
    return store.told.filter {
        $0.isAwaitingTranscription && !TranscriptionAttempts.hasGivenUp(on: $0.id)
    }.count
}

/// "These are waiting on the month's telling, and this is when it comes back."
///
/// The third quiet note, of `PhotoQuotaNote`'s kind: an answer about the
/// family's ceiling, not a waiting state that fixes itself. It differs in
/// one thing — the fix has a date. The server's window is the calendar
/// month, so the row can say when the text comes instead of "myöhemmin",
/// and beside it the one act that brings it sooner, when there is such an
/// act. The count is every recording in the archive still without its text,
/// whoever told it: the meter is the family's, and so is the wait. Rule 2 is
/// kept — nothing here stops anyone telling; what is offered is the writing
/// down (findings #104, #105, #107).
private struct MinutesQuotaNote: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var isShowingPaywall = false

    private var waiting: Int { tellingsAwaitingText(store) }

    var body: some View {
        if session.isOutOfMinutes, waiting > 0 {
            let date = Session.nextFreeMinutes().formatted(.dateTime.day().month(.wide))
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if waiting == 1 {
                        Label(
                            "Yksi kertomus odottaa tekstiä — kuukauden ilmainen kertominen on täynnä. Lisää kertomista \(date).",
                            systemImage: "waveform"
                        )
                    } else {
                        Label(
                            "\(waiting) kertomusta odottaa tekstiä — kuukauden ilmainen kertominen on täynnä. Lisää kertomista \(date).",
                            systemImage: "waveform"
                        )
                    }
                }
                .elderBody()
                .foregroundStyle(Elder.supporting)

                // Only when there is something to open: without a RevenueCat
                // key the sheet would be a dead button, and a paid family is
                // not out of minutes.
                if !session.isPaid, RevenueCatPurchases.configuredKey != nil {
                    Button("Avaa koko arkisto") { isShowingPaywall = true }
                        .buttonStyle(.borderless)
                        .font(.body.weight(.semibold))
                        .elderTapTarget()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .elderCard()
            .paywallSheet(isPresented: $isShowingPaywall)
        }
    }
}

/// A section's title.
///
/// `LocalizedStringKey` and not `String`, which is the whole of it: `Text`
/// looks up a literal and shows a variable verbatim, so a heading that
/// passed through a `String` parameter on its way here was never looked up.
/// Three of the four read Finnish on an English phone until 9 Sep 2026 —
/// and *"Paikat"* did it while sitting in `en.lproj` as "Places", translated
/// and never asked for, which is why neither table being short could have
/// caught this. `localisation-check.mjs` counts keys, not lookups.
private struct SectionHeading: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

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
            // Opaque, not a material. The capsule sits on a photograph, and a
            // frosted one takes its colour from whatever is under it: the
            // first sweep to put untold photographs with real pictures on
            // this grid (6 Sep 2026, the decades) read "Kerro" as failing
            // contrast on all three. The system background under the primary
            // text is the one pair whose contrast does not depend on the
            // picture, in either appearance.
            .background(Elder.card, in: Capsule())
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
        // The photograph's own name first, when it has one. A telling that
        // named a place or a time gives its photograph a title
        // (`Extraction.suggestedTitle`, since 15 Aug 2026), and the tile
        // never read it out: thirty tiles were thirty "Valokuva" to VoiceOver
        // (founder's-eye review, finding #12). An untitled one still is.
        .accessibilityLabel(tileLabel)
    }

    private var tileLabel: LocalizedStringKey {
        let count = store.memories(for: subject.id).count
        return count == 0
            ? "\(subject.displayTitle), ei vielä muistoja"
            : "\(subject.displayTitle), \(count) muistoa"
    }
}

/// A telling by another member that this phone has not seen yet. It leads to
/// the subject's card, where the memory itself is — the same place every other
/// row on this screen leads, so reading it teaches nothing new.
private struct NewTellingRow: View {
    let memory: Memory
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            // A person gets their initial; a place and an event keep their
            // symbol, because a pin and a calendar say what kind of thing the
            // row is where a letter in a circle would not.
            if subject.kind == .person {
                SubjectAvatar(subject: subject)
            } else {
                // The badge belongs on the symbol too. It lives inside
                // `SubjectAvatar`, and the split above is a decision about
                // AVATARS — an initial tells two people apart where a pin
                // says what kind of row this is — so until 12 Sep 2026 an
                // unconfirmed place carried no mark at all while an
                // unconfirmed person carried one here and three on the people
                // list. Nobody decided that; it fell out of the avatar.
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: subject.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(Elder.supporting)
                        .frame(width: 34)

                    if !subject.confirmed {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Elder.proposal)
                            // Its own plate, so the badge does not sit half on
                            // the symbol and half on the paper and read as
                            // neither.
                            .background(Circle().fill(Elder.paper).padding(-1))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                // "Kertoi" — the act this whole app is named after, in the
                // past tense; the author's name is the reason to tap (§11's
                // argument, read in the other direction).
                Text("\(memory.authorName) kertoi")
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Elder.supporting)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .elderCard()
        .accessibilityElement(children: .combine)
    }
}

/// A moment or a place, listed. The icon is the only difference between them,
/// and it comes from the kind rather than from a row written per kind.
private struct SubjectRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            // A person gets their initial; a place and an event keep their
            // symbol, because a pin and a calendar say what kind of thing the
            // row is where a letter in a circle would not.
            if subject.kind == .person {
                SubjectAvatar(subject: subject)
            } else {
                // The badge belongs on the symbol too. It lives inside
                // `SubjectAvatar`, and the split above is a decision about
                // AVATARS — an initial tells two people apart where a pin
                // says what kind of row this is — so until 12 Sep 2026 an
                // unconfirmed place carried no mark at all while an
                // unconfirmed person carried one here and three on the people
                // list. Nobody decided that; it fell out of the avatar.
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: subject.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(Elder.supporting)
                        .frame(width: 34)

                    if !subject.confirmed {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Elder.proposal)
                            // Its own plate, so the badge does not sit half on
                            // the symbol and half on the paper and read as
                            // neither.
                            .background(Circle().fill(Elder.paper).padding(-1))
                    }
                }
            }

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
        .elderCard()
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
        // Ahead of the count, the way `PersonRow` orders the same two things:
        // shape and colour carry it in the badge, this carries it in words,
        // which is rule 1 and the contract `SubjectAvatar` states. Only a
        // place reaches it — `extract.ts` proposes `person` and `place` and
        // nothing else, so an event on this row was made by a human.
        if !subject.confirmed {
            Text("Ehdotus — vahvista paikka")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Elder.proposal)
        } else if count == 0 {
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
            // A ternary hides the literal from SwiftUI's key lookup and from
            // scripts/localisation-check.mjs alike; as its own Text it is a key.
            Group {
                if count == 1 {
                    Text("1 muisto")
                } else {
                    Text("\(count) muistoa")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Elder.supporting)
        }
    }
}

#Preview {
    GalleryScreen()
        .environment(MemoryStore(filename: "preview-store.json"))
}
