import SwiftUI

/// Three tabs, because four is already too many to remember.
/// Telling is in the middle and is the default — the app opens on what it exists
/// for, not on a list.
struct RootView: View {
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    private enum Tab: Hashable {
        case memories, tell, people

        /// Telling is the default: the app opens on what it exists for, not on
        /// a list. Two states outrank it, both about arrival rather than
        /// preference — joining, and tellings from others waiting unseen.
        ///
        /// Development and screenshot aid: `-tab memories` or `-tab people` as
        /// a launch argument opens the given tab directly, so screenshots can be
        /// taken without any tapping. `-screen` does the same by itself — it
        /// opens the tab its destination lives in, because a TabView does not
        /// build a tab nobody has looked at. DEBUG builds only.
        static func initial(newFromFamily: Bool) -> Tab {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "tab") {
            case "memories": return .memories
            case "people": return .people
            // Kerro by name, for a test that needs the result screen over an
            // archive with tellings from others waiting — which otherwise wins
            // the first tab.
            case "tell": return .tell
            default: break
            }
            // `-screen` names a destination that lives inside ONE tab, and a
            // TabView builds a tab's content only once that tab is shown. The
            // task that reads it sits in PeopleScreen, so on a launch that
            // opens Kerro — the default — it never runs at all, and
            // `-screen person` quietly does nothing. The Kerro values
            // (`starter`, `write`, `interview`, `interviewed`, `result`) have
            // always worked, and only because Kerro is the default; every
            // value behind another tab needed `-tab` beside it, which the
            // comment above this function never said. So the aid opens the
            // tab that owns the screen. An explicit `-tab` still wins, because
            // a caller naming both means it (FilmDriver names both).
            switch UserDefaults.standard.string(forKey: "screen") {
            case "person", "family", "settings", "export", "help", "sharing", "tree":
                return .people
            case "camera":
                return .memories
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
            // The readers' phones open on what the family told; the teller's
            // opens on her button. "Kenen puhelin tämä on" is the signal the
            // app already has (the text floor), and until 5 Sep 2026 the flip
            // ignored it: on her phone the home screen was a grid one day and
            // a button the next, and the one thing the screen exists for was
            // a tab away (founder's-eye review, 3 Sep 2026, findings #76,
            // #81). The blind card moves the same way — see GalleryScreen.
            if newFromFamily, !UserDefaults.standard.bool(forKey: Elder.largerTextKey) {
                return .memories
            }
            return .tell
        }
    }

    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @State private var selection: Tab

    /// Whose phone this is, so the first minute is asked only of whoever set
    /// the archive up, and whether it is being asked now.
    @AppStorage(Elder.largerTextKey) private var largerText = false
    @State private var isShowingFirstMinute = false

    /// The other two inputs to the third tab's name. Neither is in the store:
    /// VoiceOver is an environment value, and which of the two views this
    /// phone was last left on is device state.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage(PeopleTab.prefersListKey) private var prefersList = false

    private var peopleTabIsTree: Bool {
        PeopleTab.showsTree(
            largerText: largerText,
            voiceOver: voiceOverEnabled,
            prefersList: prefersList,
            hasConfirmedPerson: store.subjects(of: .person).contains(where: \.confirmed)
        )
    }

    /// The caller decides whether unseen tellings are waiting, because it has
    /// the store and a `@State`'s initial value cannot ask the environment.
    /// Evaluated once per root-view identity, so a person's own tab choice is
    /// never overridden mid-session.
    init(opensOnNewFromFamily: Bool = false) {
        _selection = State(initialValue: Tab.initial(newFromFamily: opensOnNewFromFamily))
    }

    var body: some View {
        TabView(selection: $selection) {
            // "Albumi", not "Muistot", since 13 Sep 2026. Beside "Kerro" both
            // names read as the place where the memories are, and only one of
            // the two is where they are looked at. See ARCHITECTURE §21.
            GalleryScreen()
                .tabItem { Label("Albumi", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.memories)

            // The one Tell screen that is nobody's destination, and so the one
            // that has to find its own subject. Every other use of this screen
            // was navigated to from a photo, a person or a question and already
            // knows what it is about.
            TellScreen(usesDeck: true)
                .tabItem { Label("Kerro", systemImage: "mic.circle.fill") }
                .tag(Tab.tell)

            // The tab is named for what it opens, and that is two different
            // screens on two phones: a family member's opens the drawn tree,
            // a grandparent's and VoiceOver's the list. Until 19 Sep 2026 the
            // tab said "Ihmiset" over a screen whose own title said
            // "Sukupuu", so the one place the app names itself before it is
            // touched hid the part of it that took the most work — the same
            // fault Muistot → Albumi answered, the other way round
            // (ARCHITECTURE §21). `PeopleTab.showsTree` is that one decision,
            // read here and by the screen, so the two words cannot part again.
            // The icon is the toolbar switch's `tree`, filled for a tab bar,
            // rather than a second drawing of the same destination.
            PeopleScreen()
                .tabItem {
                    peopleTabIsTree
                        ? Label("Sukupuu", systemImage: "tree.fill")
                        : Label("Ihmiset", systemImage: "person.2.fill")
                }
                .tag(Tab.people)
        }
        // Rule 10, said out loud. Once per launch that moved a file aside,
        // and never silently: the archive on screen is empty, and the person
        // holding the phone must know that is not the same as gone.
        .alert(
            "Tallennettua arkistoa ei saatu luettua",
            isPresented: Binding(
                get: { store.unreadableArchive != nil },
                set: { if !$0 { store.acknowledgeUnreadableArchive() } }
            )
        ) {
            Button("Selvä") { store.acknowledgeUnreadableArchive() }
        } message: {
            Text("Se on yhä tallessa tiedostona tällä puhelimella, mutta tämä sovellusversio ei saa sitä auki. Älä tyhjennä laitetta: päivitetty sovellus voi vielä lukea sen.")
        }
        // The way back for a device the server has stopped knowing: the join
        // form over the archive, with nothing on this phone at stake. Asked
        // for by the note on Muistot or by a tapped link; see
        // `SyncEngine.askToRejoin` and `Session.rejoin`. Here and not on the
        // App, because a View's body is where a change on the engine is
        // certain to be seen.
        .sheet(isPresented: Binding(
            get: { sync?.isRejoining ?? false },
            set: { if !$0 { sync?.isRejoining = false } }
        )) {
            if let sync {
                OnboardingScreen(
                    prefilledCode: Binding(
                        get: { sync.rejoinCode },
                        set: { sync.rejoinCode = $0 }
                    ),
                    rejoining: true
                )
            }
        }
        // The first minute after "Luo arkisto", once, on the phone of whoever
        // set the archive up: whose memories it is for, their card, and how
        // they will tell — an invitation, or this phone. The archive was bought for somebody
        // else's memories, and the Kerro tab behind this asks for the buyer's
        // own. A grandparent's phone skips it and keeps her button.
        .sheet(isPresented: $isShowingFirstMinute) {
            FirstMinuteSheet()
        }
        // A tapped notification: asked something → Kerro, where the question
        // is offered first; an answer → Albumi, where it is new from the
        // family. Read once and cleared, so the tab is hers again at once.
        .onChange(of: PushNotifications.shared.route, initial: true) { _, route in
            guard let route else { return }
            selection = route == .tell ? .tell : .memories
            PushNotifications.shared.route = nil
        }
        .task {
            guard UserDefaults.standard.bool(forKey: Session.firstMinutePendingKey) else { return }
            UserDefaults.standard.removeObject(forKey: Session.firstMinutePendingKey)
            if !largerText { isShowingFirstMinute = true }
        }
        .elderSurface()
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

/// Whether this phone's third tab is the family tree or the list of people.
///
/// One decision with two readers: the tab bar, which names what is behind it,
/// and the screen, which draws it. They disagreed from 13 Sep 2026, when the
/// tree became what the tab opens and the tab kept the older word.
///
/// A search is deliberately no part of it. Search is always answered as a
/// list, and a tab that renamed itself under a typing finger would be a worse
/// fault than a title one word behind — so the screen adds that condition to
/// what it draws, and the tab does not.
enum PeopleTab {
    /// Which of the two views this phone was last left on. Written only by the
    /// switch in the toolbar.
    static let prefersListKey = "people.showsList"

    /// The drawn tree is offered on neither a grandparent's phone nor under
    /// VoiceOver: both keep the relationships as lists on each card, where
    /// they can be read at any size and aloud.
    static func offersTree(largerText: Bool, voiceOver: Bool) -> Bool {
        !largerText && !voiceOver
    }

    static func showsTree(
        largerText: Bool,
        voiceOver: Bool,
        prefersList: Bool,
        hasConfirmedPerson: Bool
    ) -> Bool {
        // Nobody confirmed is nothing to draw — which is the first minute on a
        // new phone, and the one moment the tab must not promise a tree.
        guard offersTree(largerText: largerText, voiceOver: voiceOver), hasConfirmedPerson
        else { return false }
        #if DEBUG
        // `-screen tree` for a screenshot or a film take, and `-people list`
        // or `-people tree` for a test. Either holds for the whole launch, so
        // the switch in the toolbar does nothing under it. The suite's launch
        // helper passes `list` unless a test says otherwise, so the tests
        // written about the list keep testing the list — and keep finding the
        // tab under the word the list is called by.
        if UserDefaults.standard.string(forKey: "screen") == "tree" { return true }
        switch UserDefaults.standard.string(forKey: "people") {
        case "list": return false
        case "tree": return true
        default: break
        }
        #endif
        return !prefersList
    }
}

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
    /// The sheet a person is typed into, and the card to open once it closes.
    @State private var isAddingPerson = false
    @State private var addedPerson: Subject?

    /// Whose phone this is, and whether it is being listened to rather than
    /// looked at. The drawn tree is offered on neither a grandparent's phone
    /// nor under VoiceOver: both keep the relationships as lists on each card,
    /// where they can be read at any size and aloud.
    @AppStorage(Elder.largerTextKey) private var largerText = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The tree first on a family member's phone, and the list one tap away
    /// (13 Sep 2026: the founder wanted the family's picture to be what this
    /// tab opens on). Remembered per phone.
    @AppStorage(PeopleTab.prefersListKey) private var prefersList = false

    private var hasConfirmedPerson: Bool {
        store.subjects(of: .person).contains(where: \.confirmed)
    }

    /// A family member's phone, nobody searching, and somebody confirmed to
    /// draw. This is what puts the switch in the toolbar, so it is asked
    /// whether or not the tree is the view that is up.
    private var canDrawTree: Bool {
        PeopleTab.offersTree(largerText: largerText, voiceOver: voiceOverEnabled)
            && query.isEmpty
            && hasConfirmedPerson
    }

    /// The tab's decision, plus the one condition that belongs to the screen
    /// alone: a search is always answered as a list.
    private var showsTree: Bool {
        query.isEmpty && PeopleTab.showsTree(
            largerText: largerText,
            voiceOver: voiceOverEnabled,
            prefersList: prefersList,
            hasConfirmedPerson: hasConfirmedPerson
        )
    }

    /// Confirmed people only, since 12 Sep 2026. A name the extraction heard
    /// and nobody has vouched for is not on this list: it waits behind one
    /// quiet row at the bottom (`HeardNamesScreen`), with the sentence it was
    /// heard in. The orange "Ehdotus" row used to stand among the family,
    /// which put a guess beside the people it was a guess about.
    private var people: [Subject] {
        store.subjects(of: .person, matching: query).filter(\.confirmed)
    }

    /// The names waiting behind the door.
    private var heard: [Subject] {
        store.subjects(of: .person).filter { !$0.confirmed }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.subjects(of: .person).filter(\.confirmed).isEmpty, heard.isEmpty {
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
                        // The last sentence points at the toolbar, because
                        // the toolbar is the only place the button is. It sat
                        // beneath this empty state as well until 16 Sep 2026,
                        // and adding the first person took it away: whoever
                        // had just used it went looking for it where they had
                        // used it, and it had moved to the top of the screen.
                        // One place that never moves beats two that trade off.
                        Text("Ihmiset kertyvät tähän sitä mukaa kun heistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli. Voit myös lisätä ihmisen itse yläreunan painikkeesta.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }
                } else if people.isEmpty, !query.isEmpty {
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
                } else if showsTree {
                    // The doors the tree's menu opens belong to this stack,
                    // so the tree asks for them rather than pushing them.
                    FamilyTreeView(
                        heardCount: heard.count,
                        onOpen: { path.append($0) },
                        onHeard: { path.append(HeardNamesRoute()) },
                        onSettings: { path.append(SettingsRoute()) },
                        onList: { prefersList = true },
                        onAddPerson: { isAddingPerson = true }
                    )
                } else {
                    List {
                        ForEach(people) { person in
                        NavigationLink(value: person) {
                            PersonRow(subject: person)
                        }
                        // On the ROW, not on the list. Hung on the list it
                        // does nothing at all, which is how a white stripe
                        // survived three attempts at painting it: the
                        // screen around it went parchment and the rows
                        // stayed the system's own white.
                        //
                        // Paper and not `Elder.card`: a plain list's rows run
                        // from margin to margin, and a card that touches both
                        // edges is a band rather than a card.
                        .listRowBackground(Elder.paper)
                        }

                        if !heard.isEmpty {
                            heardRow
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            // The list is named for what it shows, and the tab below says the
            // same word, from the same decision. They differ in one case
            // only: a search is answered as a list under a tab still called
            // Sukupuu, because a tab that renames itself under a typing
            // finger is the worse of the two faults. The tree has no title
            // at all since 19 Sep 2026: it is a map, drawn under the bar,
            // and the tab is the one word that names it.
            .navigationTitle(showsTree ? LocalizedStringKey("") : LocalizedStringKey("Ihmiset"))
            // Out of the way until it is wanted: iOS keeps the field hidden
            // above the list until somebody pulls down, which is the right
            // bargain here. The grandchild looking for one name in forty finds
            // it; grandmother never meets it.
            // "Etsi" and nothing more. The field keeps its width while the text
            // in it grows, so a prompt of any length is a prompt that will be
            // cut in half at the largest size — and what the search actually
            // covers is spelled out where it matters, on the screen that comes
            // back with nothing.
            // And on the list alone (19 Sep 2026): over the tree the field
            // surfaced whenever the picture was scrolled to its top, one
            // more thing on a screen meant to hold the drawing and nothing
            // else. A search is answered as a list in any case.
            .searchable(!showsTree, text: $query, prompt: Text("Etsi"))
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailScreen(subject: subject)
            }
            .navigationDestination(for: HeardNamesRoute.self) { _ in
                HeardNamesScreen()
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
            // A place card opens on this stack too, through the memories on a
            // person's card, and the small map on it opens the family's map.
            .placesMapDestinations()
            .toolbar {
                // Settings belongs under People rather than as its own tab:
                // three tabs is already the limit of what an 80-year-old holds
                // in mind. It is shown without a backend too — a single-device
                // archive is exactly the one with no copy anywhere else, and it
                // used to have no way to reach the export at all.
                // A corner of its own, on the leading side, and that is the
                // whole point of it: it is the one control here whose position
                // nothing else can move. Beside the gear it moved 90 pt to the
                // left the moment the family got its first person — measured
                // 16 Sep 2026, x 218 → x 128 — because the switch below joins
                // the group then and the group grows leftwards. Which is the
                // same complaint as the button that used to sit under the empty
                // state: whoever had just used it went looking where they had
                // used it. Album's "+" can sit beside nothing and stay put;
                // this bar has a conditional item in it, so this one cannot.
                //
                // Not a row in the list either, and that is measured: as a row
                // above the door to the heard names it moved the audit's
                // Dynamic Type finding onto that unchanged door (13 Sep 2026),
                // and with the row gone the door passed again.
                //
                // None of these three over the tree (19 Sep 2026). The tree's
                // bar has one button, the menu, and the same three doors are
                // behind it — the drawing is the screen there, and a bar of
                // controls over a map is the thing a map does without.
                if !showsTree {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isAddingPerson = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Lisää henkilö")
                    }
                }
                // The way back to the tree from the list, on the phones that
                // have the tree. The other direction is in the tree's menu.
                if canDrawTree && !showsTree {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            prefersList = false
                        } label: {
                            Image(systemName: "tree")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Sukupuu")
                    }
                }
                if !showsTree {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: SettingsRoute()) {
                            Image(systemName: "gearshape")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Asetukset")
                    }
                }
            }
            // The card is opened once the sheet has gone, so it is pushed onto
            // the screen rather than under a sheet still on its way down.
            .sheet(isPresented: $isAddingPerson, onDismiss: {
                if let addedPerson {
                    path.append(addedPerson)
                    self.addedPerson = nil
                }
            }) {
                NameSheet(title: "Lisää henkilö", initial: "") { name in
                    guard let person = store.addPerson(named: name) else { return false }
                    addedPerson = person
                    return true
                }
            }
            #if DEBUG
            // Screenshot aid, alongside `-tab` and `-screen write`. These two
            // screens sit behind a tap, and a screenshot run has no hands:
            //
            //   -screen person     the first person's card, relationships and all
            //   -screen family     members, usage and the invite link
            //   -screen settings   export, leaving, emptying the device
            //   -screen help       the "Näin tämä toimii" page
            //   -screen sharing    opening a single-device archive to a family
            //
            // Checking a screen at the largest text size means opening it, and
            // this is how the two that were skipped stopped being skipped.
            .task {
                switch UserDefaults.standard.string(forKey: "screen") {
                case "person":
                    // `-person <card id>` picks the card; without it, the
                    // first person's. The clan fixture's cards differ in what
                    // they carry, and a sweep has to name the one it means.
                    let named = UserDefaults.standard.string(forKey: "person").flatMap { store.subject(id: $0) }
                    if let card = named ?? store.subjects(of: .person).first { path.append(card) }
                case "family":
                    path.append(FamilyRoute())
                case "settings", "export":
                    path.append(SettingsRoute())
                case "help":
                    // Both, so the page has the back stack it really has —
                    // and so it can be photographed on an English phone,
                    // which is how it was found to be Finnish (4 Sep 2026).
                    path.append(SettingsRoute())
                    path.append(HelpRoute())
                case "sharing":
                    // Both, so the screen has the back stack it really has.
                    path.append(SettingsRoute())
                    path.append(SharingRoute())
                default:
                    break
                }
            }
            #endif
            .elderSurface()
        }
    }

    /// One quiet row for the names the extraction heard and nobody has
    /// checked. A count and a chevron, nothing orange: the list above is the
    /// family, and this is the door to what is not yet.
    private var heardRow: some View {
        NavigationLink(value: HeardNamesRoute()) {
            HeardNamesDoorLabel(count: heard.count)
                .padding(.vertical, 6)
        }
        .listRowBackground(Elder.paper)
    }
}

private extension View {
    /// `searchable` that can be left off: there is no way to take the field
    /// away from a view once the modifier is on it, and the tree wants none.
    @ViewBuilder
    func searchable(_ wanted: Bool, text: Binding<String>, prompt: Text) -> some View {
        if wanted {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}

/// The words on the door to the names heard: under the list, and since
/// 13 Sep 2026 under the tree as well, in one place so the two cannot come to
/// say it differently.
struct HeardNamesDoorLabel: View {
    let count: Int

    var body: some View {
        // An HStack rather than a Label, and fixedSize on the Text
        // itself: as a Label's title the sentence was measured clipped
        // at the default size — one line, cut with an ellipsis — on the
        // audit's first run.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "ear")
                .foregroundStyle(Elder.supporting)
            Group {
                if count == 1 {
                    Text("1 nimi odottaa tarkistusta")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(count) nimeä odottaa tarkistusta")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
        }
    }
}

private struct PersonRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            // Their initial rather than the same grey head five times over.
            // The state still travels by shape and not by colour alone —
            // `SubjectAvatar` carries the badge the symbol here used to, and
            // the row says it in words underneath either way.
            SubjectAvatar(subject: subject)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.displayTitle)
                    .font(.body.weight(.medium))

                // Only confirmed people reach this row since 12 Sep 2026; the
                // orange "Ehdotus" line that stood here first is behind the
                // door at the bottom of the list (`HeardNamesScreen`).
                if store.memories(for: subject.id).isEmpty {
                    // A gap is not hidden but shown as an invitation.
                    // Not tinted — the same call as the gallery's row and the
                    // guessing round's card: blue on this grey only nearly
                    // passes, and it fails outright inside the tab bar's fade.
                    // Weight invites; the microphone says what to do.
                    Label("Kerro hänestä", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                } else {
                    let count = store.memories(for: subject.id).count
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
        .padding(.vertical, 6)
    }
}

/// The view for a photo, a person and an event is the same: the subject and the
/// memories that have gathered on it. This is the concrete payoff of the
/// `subject` table — one view instead of three.
struct SubjectDetailScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    /// Optional for the same reason `SyncEngine` is read that way: a screen
    /// hosted without the app around it has nothing to ask, and no coordinate
    /// is the answer this card already knows how to draw.
    @Environment(PlaceResolver.self) private var places: PlaceResolver?
    let subject: Subject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var image: UIImage?
    /// The last load of the photograph ended with nothing to draw — no
    /// network, a server that did not answer, a file that would not open.
    @State private var photoFailed = false
    /// Every "Yritä uudelleen" is one more, which is what runs the load again.
    @State private var photoTries = 0
    /// The family's confirmed colouring, drawn beside the photograph and never
    /// in its place.
    @State private var colourImage: UIImage?
    @State private var isColouring = false
    /// "Ei, kerron lisää" on the colour sheet: the telling opens once that
    /// sheet has gone, because a sheet cannot be presented over a leaving one.
    @State private var tellsAfterColouring = false
    @AppStorage(Elder.largerTextKey) private var largerText = false
    @State private var isTelling = false
    @State private var isAsking = false
    @State private var isCorrectingName = false
    @State private var isDating = false
    @State private var isRenaming = false
    /// The picker for the face on a person's card (§25).
    @State private var isChoosingFace = false
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

    private var nameRowText: LocalizedStringKey {
        if current.kind == .photo {
            return current.title.isEmpty ? "Anna kuvalle nimi" : "Vaihda kuvan nimi"
        }
        return "Vaihda nimi"
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

    /// Whether this photograph can be coloured by what was told about it: it is
    /// on screen, something has been said about it, this is not the
    /// grandparent's phone, and this phone was not told to keep its archive to
    /// itself.
    ///
    /// Something told, because the Worker refuses a colouring with nothing to
    /// go by — a guess in the shape of a photograph is rule 4's failure — and a
    /// button that can only ever be refused is a broken button. Not on her phone
    /// (the text-floor signal), because there the question has to come before
    /// the colours, and the card that asks it first is not built. And not on a
    /// phone kept to itself, whose onboarding promised "Muistot jäävät tähän
    /// puhelimeen": colouring sends the photograph and those memories to the
    /// Worker, and even a refusal there arrives after the bytes have left. It
    /// is the gate that keeps transcription off that phone (`TellScreen`).
    private var colourable: Bool {
        current.kind == .photo && image != nil && !largerText && !session.isLocalByChoice
            && store.memories(for: subject.id).contains {
                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            // The colours the family said yes to, under the photograph and never
            // over it: the picture as it was taken stays the first thing on the
            // card, and this one carries its mark in its own pixels.
            if subject.kind == .photo, let colourImage {
                Section {
                    Image(uiImage: colourImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan.")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Värit kerronnan mukaan")
                        .foregroundStyle(Elder.supporting)
                } footer: {
                    if let name = current.colourConfirmedByName {
                        Text("Vahvisti \(name)")
                            .foregroundStyle(Elder.supporting)
                    }
                }
            }

            // Where it is, for a confirmed place the lookup found. Under the
            // name and above everything told about it, because the map
            // answers "where" and the memories answer "what happened there".
            //
            // Withdrawn for one day, 12 Sep 2026, with the rest of "yksi
            // kerronta, yksi muisto", and back on 13 Sep for the reason the
            // rule allows it: the lookup now waits for a person's confirmation
            // (`placesAwaitingCoordinates`), so a map here draws nothing the
            // family has not vouched for. The film's take of this card was
            // already final, which is what made the day's cost visible.
            //
            // `current` and not `subject`: correcting a place's name clears
            // its coordinate (`PlaceResolver`), and this screen has to show
            // the archive as it is now rather than as it was when it opened.
            //
            // The span and not merely the point, since 19 Sep 2026: a name the
            // gazetteer placed without recognising it — `GeoPrecision.unknown`
            // — is stored as a coordinate and drawn as nothing, which is rule 5
            // and stays. `place != nil` opened a Section for it all the same,
            // so such a place carried a band of empty paper between its name
            // and its date. The condition now says what the card says.
            if current.kind == .place, current.place?.precision.mapSpanMetres != nil {
                Section {
                    // Tapping it opens the family's map on this place, where
                    // it can be looked at among the others and moved only on
                    // request ("Muuta sijaintia"). §18 measures how coarse the
                    // lookup's answer usually is — a farm name comes back as
                    // its municipality — so the circle here is nearly always
                    // the best a gazetteer can do and nearly never the best
                    // anybody in the family can do.
                    PlaceMapCard(subject: current)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } else if current.kind == .place, current.confirmed {
                // And the way to put it there, for a place with nowhere to be
                // drawn: a farm the gazetteer did not know, which is most of
                // them (§18), or a point somebody took off the map. It opens
                // the family's map already placing this place, and "Peruuta"
                // there comes straight back here. Confirmed only, like the
                // lookup: a point under a name nobody has vouched for is the
                // guess drawn (rule 4). The shape of the date row below, for
                // the date row's reason.
                Section {
                    NavigationLink(value: PlacesMapRoute(focus: current.id, editing: true)) {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Merkitse kartalle")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Elder.supporting)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }
                    .accessibilityHint("Avaa kartan, jolla paikan voi merkitä napauttamalla.")
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
                            Text(current.dateHint?.displayText ?? String(localized: "Lisää ajankohta"))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Elder.supporting)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }

                    // And the name, the same way. The card could date the
                    // picture and not name it: the title was whatever the
                    // first telling left, and the tile on Muistot reads the
                    // title aloud, so thirty untitled photographs were thirty
                    // "Valokuva" (finding #12). A row and not the toolbar
                    // pencil the person card has, for the reason the date row
                    // gives: a toolbar button's text barely grows.
                    Button {
                        isRenaming = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil")
                            // The identifier is for
                            // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                            // and nothing else: the default-size simulation
                            // reports this text whenever words stand in the
                            // picture's place above it, and it has three wordings.
                            Text(nameRowText)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("subject.rename")
                        }
                        .foregroundStyle(Elder.supporting)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .elderTapTarget()
                    }
                }
            }

            // The face on the card, and the way to give it one (§25). People
            // only: a place has no face and a photograph is its own picture.
            // The disc is the same `SubjectAvatar` the list and the tree
            // draw, so what is chosen here is what is drawn everywhere — and
            // the row says in words what the disc, hidden from VoiceOver like
            // every avatar, cannot.
            if subject.kind == .person {
                Section {
                    Button {
                        isChoosingFace = true
                    } label: {
                        HStack(spacing: 14) {
                            SubjectAvatar(subject: current, size: 56)
                            Text(current.portraitSubjectID == nil ? "Valitse kasvot" : "Vaihda kasvot")
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
            // The tellings that *named* this rather than being about it, and
            // the half of the same web this screen never read. A place is named
            // inside somebody's memory of a photograph, and a proposed person's
            // name was heard in one — so both answered *"nobody has told
            // anything yet"* over the very telling a person has to read before
            // rule 4's confirmation can mean anything.
            //
            // Measured on the demo video's own take of 12 Sep 2026: Puumala's
            // card said it ten seconds after the telling that named Puumala, on
            // camera, with the map of the place above the sentence (the video
            // project's SCRIPT-v21.md §1.5, which is where it was written down
            // as the app's defect rather than the film's).
            //
            // Only when nothing is filed under it: a subject with a telling of
            // its own gets the section below, and listing the same memory twice
            // under two headings would be the screen answering something nobody
            // asked.
            let mentions = memories.isEmpty ? store.memories(mentioning: subject.id) : []
            if !mentions.isEmpty {
                Section {
                    ForEach(mentions) { memory in
                        MemoryRow(memory: memory)
                            // The one row on this screen whose surface was the
                            // system's rather than this repo's, and it did not
                            // draw the white the sibling section below gets: it
                            // came up `systemGray4`, rgb(209, 209, 214), a
                            // colour named nowhere in this app. The accent on it
                            // measures **4.20:1** against rule 1's 4.5 minimum,
                            // which is how the audit found it — "Contrast nearly
                            // passed" on the listen button, in 3 runs of 10.
                            //
                            // It reads as a tap highlight and is not one: it
                            // survives a scroll up and back down and a change of
                            // Dynamic Type size, measured 19 Sep 2026 from the
                            // audit's own screenshot at both text sizes. On
                            // `Elder.card` the same button measures 6.14:1.
                            .listRowBackground(Elder.card)
                    }
                } header: {
                    // Two whole sentences rather than one with a number in it:
                    // the count's own header below says why, and Finnish would
                    // want "yhdessä" here in any case.
                    Group {
                        if mentions.count == 1 {
                            Text("Mainittu yhdessä muistossa")
                        } else {
                            Text("Mainittu \(mentions.count) muistossa")
                        }
                    }
                    .foregroundStyle(Elder.supporting)
                }
            }
            if memories.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Nothing at all, or nothing of its own.
                        if mentions.isEmpty {
                            Text("Kukaan ei ole vielä kertonut mitään. Paina yllä olevaa nappia ja ala puhua.")
                                .elderBody()
                                .foregroundStyle(Elder.supporting)
                        } else {
                            Text("Tästä ei ole vielä omaa muistoa. Paina yllä olevaa nappia ja ala puhua.")
                                // The identifier is for
                                // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                                // and nothing else (26 Sep 2026).
                                .accessibilityIdentifier("card.emptyState")
                                .elderBody()
                                .foregroundStyle(Elder.supporting)
                        }

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
                        //
                        // A mention above it does not close this door, and that
                        // is deliberate: a person the recognition invented is
                        // *always* named in some telling, which is where the
                        // name came from, so a rule that kept the button for
                        // subjects nothing mentions would take it away from
                        // exactly the case it was added for.
                        if removable {
                            Button(removalButton) { isConfirmingRemoval = true }
                                // The identifier is for
                                // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                                // and nothing else (26 Sep 2026).
                                .accessibilityIdentifier("card.removal")
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
                    Group {
                        if memories.count == 1 {
                            Text("1 muisto")
                        } else {
                            Text("\(memories.count) muistoa")
                        }
                    }
                    .foregroundStyle(Elder.supporting)
                }
            }

            if colourable {
                Section {
                    Button {
                        isColouring = true
                    } label: {
                        Label("Väritä kerronnan mukaan", systemImage: "paintpalette")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    // Said at the button, before anything leaves: this is the
                    // one place in the app a photograph leaves the phone without
                    // being sealed first, and the words told about it go with it.
                    Text("Kuva ja siitä kerrotut muistot lähetetään palveluumme väritettäväksi. Mitään ei tallenneta ennen kuin vastaat.")
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
                                Group {
                                    if question.targetMemberID == session.identity.memberID {
                                        Text("\(asker) kysyy sinulta")
                                    } else {
                                        Text("\(asker) kysyy")
                                    }
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.tint)
                            }
                            Label(question.text, systemImage: "questionmark.circle")
                                .elderBody()
                            // Asked of somebody else by name. Everyone sees it
                            // here and anyone who knows may answer — only the
                            // Kerro tab and the notification are theirs alone —
                            // so the family is told whose question it is.
                            if let target = question.targetName, !target.isEmpty,
                               question.targetMemberID != session.identity.memberID {
                                Text("Kenelle: \(target)")
                                    .font(.subheadline)
                                    .foregroundStyle(Elder.supporting)
                            }
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
        .alert(
            removalTitle,
            isPresented: $isConfirmingRemoval
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
        // The coordinate this card's map needs, asked for at the moment the
        // map is wanted. The sweeps in `KinloreApp` run at launch and on the
        // return to the foreground; a place confirmed in the telling that
        // named it therefore had a card and no map until the app had been
        // closed and opened. `PlaceResolver.resolve` says the rest.
        .task {
            await places?.resolve(current, in: store)
        }
        // Keyed like the colours below, and for the same reason: a photograph
        // another member added arrives as a card, then as a key, then as a
        // file, and this screen may be open through all three. It used to run
        // once, on the card as it was when the screen opened, so a key that
        // came later was never fetched and a fetch that failed was never
        // tried again — and the placeholder spun for as long as anybody looked.
        .task(id: [current.r2Key, current.imageFilename, String(photoTries)]) {
            guard subject.kind == .photo, image == nil, !MediaLoader.hasNotArrived(current) else { return }
            photoFailed = false
            guard let filename = await MediaLoader.imageFilename(
                for: current, store: store, session: session
            ) else {
                if !Task.isCancelled { photoFailed = true }
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) {
                MediaStore.loadImage(named: filename)
            }.value
            if let loaded {
                image = loaded
            } else if !Task.isCancelled {
                photoFailed = true
            }
        }
        .sheet(isPresented: $isTelling) {
            NavigationStack {
                TellScreen(target: subject, onClose: { isTelling = false })
            }
        }
        .sheet(isPresented: $isAsking) {
            AskQuestionSheet(subject: subject)
        }
        .sheet(isPresented: $isColouring, onDismiss: {
            if tellsAfterColouring {
                tellsAfterColouring = false
                isTelling = true
            }
        }) {
            if let image {
                ColourSheet(subject: current, photograph: image) { tellsAfterColouring = true }
            }
        }
        // Keyed on the object as well as the file: a yes confirmed on another
        // phone arrives as a key with no file here yet, and is fetched.
        .task(id: [current.colourR2Key, current.colourImageFilename]) {
            guard current.colourR2Key != nil || current.colourImageFilename != nil,
                  let filename = await MediaLoader.colourFilename(for: current, store: store, session: session)
            else {
                colourImage = nil
                return
            }
            colourImage = await Task.detached(priority: .userInitiated) {
                MediaStore.loadImage(named: filename)
            }.value
        }
        .sheet(isPresented: $isDating) {
            DateSheet(subject: current)
        }
        .sheet(isPresented: $isChoosingFace) {
            FacePickerSheet(subject: current)
        }
        .sheet(isPresented: $isRenaming) {
            NameSheet(
                title: current.kind == .photo ? "Nimeä kuva" : "Nimeä hetki",
                initial: current.title
            ) { name in
                store.setTitle(subjectID: current.id, title: name)
                return true
            }
        }
        .sheet(isPresented: $isCorrectingName) {
            CorrectNameSheet(subject: current) { merged in
                // The correction turned out to name somebody the family already
                // had, so this card is now a tombstone pointing at theirs. There
                // is nothing left to look at here — the memories have moved.
                if merged { dismiss() }
            }
        }
        .elderSurface()
    }

    /// The photograph, or where it is in words — and a spinner only while a
    /// fetch is actually running.
    ///
    /// Past the free ceiling the server keeps a photograph's card and refuses
    /// its file, so every phone but the one that added it holds a card with
    /// nothing to fetch. Until 26 Sep 2026 each of them spun here for ever,
    /// while only that one phone said anything (`PhotoQuotaNote`). What the
    /// card now says is the same promise that note makes, from this side.
    @ViewBuilder
    private var photoView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if MediaLoader.hasNotArrived(current) {
            photoSlot {
                photoAbsence {
                    if session.isOutOfPhotos {
                        Text("Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun perheen ilmaisessa arkistossa on tilaa.")
                    } else {
                        Text("Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun se lähetetään sieltä.")
                    }
                }
            }
        } else if photoFailed {
            photoSlot {
                VStack(alignment: .leading, spacing: 12) {
                    photoAbsence {
                        Text("Kuvaa ei saatu haettua.")
                    }
                    Button("Yritä uudelleen") { photoTries += 1 }
                        .buttonStyle(.borderless)
                        .font(.body.weight(.semibold))
                        .elderTapTarget()
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { ProgressView() }
        }
    }

    /// The picture's place, holding words instead: at least the shape the
    /// spinner had, so everything under it sits where it sat and nothing moves
    /// when the picture does come, and taller whenever the words need it — at
    /// the largest sizes they do, and a sentence cut to fit a frame would be
    /// the one thing worse than a spinner.
    ///
    /// Measured at the default size on 26 Sep 2026. As a card no taller than
    /// its words, it lifted the memories' heading off the tab bar, and the
    /// audit reported that heading there — a `List` header, whose growth the
    /// framework caps. At this shape the heading sits where it sat. The rename
    /// row under the words is reported at either shape and not under the
    /// spinner: the simulation grows the words until the row cannot be
    /// measured whole (`AccessibilityPolicy.isDefaultSizeSimulationArtefact`).
    private func photoSlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .elderCard(radius: 16)
    }

    /// A sign and the sentence beside it, or above it once the sentence needs
    /// the whole width. Not a `Label`: one in the place search was the audit's
    /// "Text clipped" at both sizes (`PlaceSearchSheet.failure`).
    private func photoAbsence<Words: View>(@ViewBuilder _ words: () -> Words) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Image(systemName: "photo.on.rectangle.angled")
                .accessibilityHidden(true)
            words()
                .elderBody()
        }
        .foregroundStyle(Elder.supporting)
    }
}

private struct MemoryRow: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoval = false
    @State private var isEditingText = false
    @State private var isMoving = false
    let memory: Memory

    /// Four truths for one row, in the order they are decided.
    ///
    /// The chosen local mode first: there the text is not late and not given
    /// up on — it is simply never coming, and "valmistuu myöhemmin" would be
    /// a promise nothing keeps (finding B4). Then the recordings refused three
    /// times, which the catch-up asks about only now and then
    /// (`TranscriptionAttempts.isDue`). Then the month's minutes, which used to fall
    /// through to "myöhemmin" — a word that read as a delay while the truth
    /// was "not until next month, unless somebody pays", on every phone in
    /// the family (findings #103, #107). A `LocalizedStringKey` property
    /// rather than the nested ternary that sat in the `Label` until 4 Sep
    /// 2026, whose three sentences had no key: a ternary's branches are
    /// nowhere `localisation-check.mjs` looks, so nothing said so.
    private var awaitingText: LocalizedStringKey {
        if session.isLocalByChoice { return "Ääni tallessa — voit kirjoittaa tekstin itse" }
        if TranscriptionAttempts.hasFailedRepeatedly(on: memory.id) {
            return "Ääni tallessa — tekstiä ei saatu tästä nauhoituksesta"
        }
        if session.isOutOfMinutes { return "Ääni tallessa — kuukauden kertominen täynnä" }
        return "Ääni tallessa — teksti valmistuu myöhemmin"
    }

    private static func told(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
    }

    /// The names this telling heard that nobody has checked. Answered here,
    /// on the telling itself, since 12 Sep 2026 — where the sentence they came
    /// from is. They used to be answered nowhere but the result screen, and
    /// then sat as orange rows among the family's people for good.
    private var heardHere: [Subject] {
        memory.mentionedSubjectIDs
            .compactMap { store.subject(id: $0) }
            .filter { !$0.confirmed && $0.deletedAt == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if memory.isAwaitingTranscription {
                // Two different truths, and the app must not tell the first one
                // after it has stopped trying. "Teksti valmistuu myöhemmin" was
                // a promise nothing kept for a while (§16); it must not become
                // one again on the recordings the catch-up has given up on.
                Label(awaitingText, systemImage: "waveform")
                .elderBody()
                .foregroundStyle(Elder.supporting)
            } else {
                // The identifiers on this text and on the byline below are
                // for `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                // and nothing else: the audit's default-size simulation
                // reports these two the moment a row is added above the
                // memories, and a story's words cannot be listed by label.
                Text(memory.body)
                    .elderBody()
                    .accessibilityIdentifier("memory.body")
            }

            if !heardHere.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kuulin nämä")
                        // The identifier is for
                        // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                        // like the story's above (26 Sep 2026).
                        .accessibilityIdentifier("memory.heard")
                        .font(.subheadline.weight(.semibold))
                    // No sentence here: the whole telling stands right above,
                    // and quoting a line of it back doubled the row — the
                    // photo card grew a page and the ask button fell out of a
                    // sweep's reach. The door and the result, where the text
                    // is not beside the name, keep the sentence.
                    ForEach(heardHere) { subject in
                        HeardNameRow(
                            subject: subject,
                            sentence: nil,
                            onConfirm: { store.confirm(subjectID: subject.id) },
                            onReject: { store.remove(subjectID: subject.id) }
                        )
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                // Subheadline, matching the "X kertoi" line on the Uutta
                // perheeltä row: who told this matters most exactly when
                // several members write on one subject, and it was the
                // smallest text in the whole reading loop.
                // And when. The export has printed the day beside every
                // telling since the first one, and the row a family actually
                // reads never did (founder's-eye review, finding #9): a
                // grandchild on a card in year three could not tell the story
                // told last week from the one told first. The device's own
                // short form, so an English phone is not handed a Finnish
                // date; the family screen's member row still is.
                // The teller and not the author since 19 Sep 2026, through
                // the one place that answers it (`MemoryStore.byline(for:)`):
                // one phone round a table files every voice under whoever owns
                // the phone until somebody says otherwise, and a teller who
                // asked not to be named leaves the day standing alone. The
                // date is already the device's own short form, so it needs no
                // key of its own when it is the whole line.
                if let teller = store.byline(for: memory) {
                    Text("\(teller) · \(Self.told(memory.createdAt))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("memory.byline")
                } else {
                    Text(verbatim: Self.told(memory.createdAt))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("memory.byline")
                }

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

                // Where the telling is filed, corrected the day after. The
                // AI's placement could be corrected nowhere until 5 Sep 2026
                // (finding #27); the same sheet the result screen opens.
                Button("Siirrä toiselle kortille") { isMoving = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .elderTapTarget()

                Button("Poista tämä muisto") { isConfirmingRemoval = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Elder.destructive)
                    .elderTapTarget()
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $isMoving) {
            MoveMemorySheet(current: memory.subjectID) { subject in
                // A moment that held only this telling goes with it, and the
                // card being read is then that moment's: nothing to stay for.
                if store.move(memoryID: memory.id, to: subject.id) { dismiss() }
            }
        }
        .alert(
            "Poistetaanko tämä muisto?",
            isPresented: $isConfirmingRemoval
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
                    .elderCard(radius: 16)
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
