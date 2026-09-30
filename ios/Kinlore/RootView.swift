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
            // opens on her button. The setup forms' "Tekstin koko" ("Kenen
            // puhelin tämä on" until 30 Sep 2026) is the signal the app
            // already has (the text floor), and until 5 Sep 2026 the flip
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
            //
            // On a stack of its own since 30 Sep 2026: the gear (`SettingsGear`)
            // pushes Settings here (`TellScreen.showsSettings`), and a name
            // confirmed on the result opens its card here
            // (`ConfirmedNameNote`).
            CardOpeningStack {
                TellScreen(usesDeck: true)
                    .settingsDestinations()
            }
            .tabItem { Label("Kerro", systemImage: "mic.circle.fill") }
            .tag(Tab.tell)

            // Sukupuu on every phone, whichever of its two views is behind it
            // (30 Sep 2026). From 19 Sep the tab was named for what it opened:
            // Sukupuu over a family member's drawn tree, Ihmiset over the list
            // a grandparent's phone and VoiceOver keep. A word that changes
            // with the phone was the worse fault: the README's screenshots
            // called one tab two things, and a family cannot tell each other
            // "tap Sukupuu" when half of them are looking at another word. The
            // list is the family tree read aloud or at a large size, so it is
            // titled with the same word, and the switches between the two
            // views are named for what they do (ARCHITECTURE §21). The icon is
            // the toolbar switch's `tree`, filled for a tab bar.
            PeopleScreen()
                .tabItem { Label("Sukupuu", systemImage: "tree.fill") }
                .tag(Tab.people)
        }
        // Paper under the tab bar at the accessibility sizes, and on a
        // grandparent's phone from its floor up, where iOS 26 would show the
        // page through it. The bar is a glass capsule that
        // lenses whatever scrolls beneath it, and the default soft edge only
        // dims that: at the largest size "Paina ja ala puhua" stood behind
        // the three tab names as a second line of text, and the person
        // card's red "Kerro tästä muisto" turned the whole capsule red. The
        // hard edge lays a nearly opaque band of the page's own paper from
        // the bar's top down, and the capsule floats on it clean. Measured
        // 27 Sep 2026 on a 17 Pro at the largest size, against the same
        // screen with the hard edge: 28 per cent of the capsule's pixels on
        // Kerro, and nearly all of them on the person card, were the page
        // showing through. At a grandparent's floor it was one word, the
        // person card's memory count bent into the capsule's end: smaller,
        // and hers first. A `toolbarBackground` of the same paper changed
        // not one pixel — the bar is glass whatever it is given.
        .modifier(PaperUnderTheTabBar())
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
        // A join that made this phone a member who is not the person who
        // joined: another phone on the same Apple ID, whose identity the
        // Keychain shares (`Session.joinedAsSomebodyElse`). Said once, until
        // read, and as a fact rather than an error — the memories are saved
        // either way. What it costs, and the one thing that changes it.
        .alert(
            Text("Tällä puhelimella olet Kinloressa \(session.sharedIdentityName ?? "")"),
            isPresented: Binding(
                get: { session.sharedIdentityName != nil },
                set: { if !$0 { session.acknowledgeSharedIdentity() } }
            )
        ) {
            Button("Selvä") { session.acknowledgeSharedIdentity() }
        } message: {
            Text("Tämä puhelin käyttää samaa Apple ID:tä kuin \(session.sharedIdentityName ?? ""), joten Kinlore pitää teitä samana ihmisenä. Muistot tallentuvat silti, mutta kaikki tällä puhelimella kerrottu näkyy hänen nimellään, eivätkä puhelimet näytä toistensa muistoja uusina. Jos haluatte kumpikin oman nimen, kummallakin puhelimella pitää olla oma Apple ID.")
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

/// `RootView`'s paper under the tab bar. A modifier because the style exists
/// from iOS 26 and the app still runs on 17, where the bar is not glass; and
/// one modifier whose style is `.hard` or `nil` rather than a modifier left
/// off, because an `if` here would rebuild every tab, and their navigation
/// with them, whenever the text size crossed into the accessibility sizes.
/// `nil` sets no style, so below those sizes the bar is whatever iOS and the
/// screen beneath it choose. The modifier is not quite invisible there, and
/// that is the price of the sentence above: measured 27 Sep 2026, a
/// telling's result at the default size draws 0.2 per cent of the capsule's
/// strip differently, in the lensed reflection of the words beneath it — the
/// same with `nil` as with `.automatic`, and nothing without the modifier.
private struct PaperUnderTheTabBar: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(Elder.largerTextKey) private var largerText = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(
                (dynamicTypeSize.isAccessibilitySize || largerText) ? .hard : nil,
                for: .bottom
            )
        } else {
            content
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

/// And for the language the app is shown in, one step below Settings. See
/// `LanguageScreen`.
struct LanguageRoute: Hashable {}

/// The way to Settings, in the trailing corner of the bar since 30 Sep 2026:
/// Sukupuu in both of its views, and Kerro on the idle screen of a reader's
/// phone (`TellScreen.showsSettings`). Not on Albumi, whose bar it squeezed
/// (`GalleryScreen` says how). Until then it
/// stood on the people list alone, and over the tree it was a row in the
/// menu, so somebody who wanted a setting from the album had to know which
/// tab kept it.
///
/// The identifier tells this one from the tree menu's row of the same name.
struct SettingsGear: View {
    var body: some View {
        NavigationLink(value: SettingsRoute()) {
            Image(systemName: "gearshape")
                .elderTapTarget()
        }
        .accessibilityLabel("Asetukset")
        .accessibilityIdentifier("settings")
    }
}

extension View {
    /// Settings and the four screens it opens, on whichever tab's stack the
    /// gear was pressed. A stack that pushes a value it has no destination
    /// for does nothing at all, so a row in Settings would have gone dead on
    /// every tab but the one that registered these.
    func settingsDestinations() -> some View {
        navigationDestination(for: SettingsRoute.self) { _ in SettingsScreen() }
            .navigationDestination(for: FamilyRoute.self) { _ in FamilyScreen() }
            .navigationDestination(for: HelpRoute.self) { _ in HelpScreen() }
            .navigationDestination(for: SharingRoute.self) { _ in EnableSharingScreen() }
            .navigationDestination(for: LanguageRoute.self) { _ in LanguageScreen() }
    }
}

/// Whether this phone's third tab shows the drawn family tree or the list of
/// people. The tab's name is no part of it: the tab says Sukupuu over both
/// views since 30 Sep 2026, and from 19 Sep until then it read this decision
/// and said Ihmiset over the list.
///
/// A search is deliberately no part of it either. Search is always answered as
/// a list, so the screen adds that condition to what it draws.
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
        // written about the list keep testing the list.
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
    ///
    /// By name since 27 Sep 2026 (`Subject.byName`). Newest first is the
    /// order the store keeps, and nobody looks for an aunt by when her card
    /// was made.
    private var people: [Subject] {
        store.subjects(of: .person, matching: query).filter(\.confirmed).sorted(by: Subject.byName)
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
                        // "Sukupuu" first: the tab is called Sukupuu and so
                        // is this screen (30 Sep 2026), and a person who has
                        // just tapped one word should not be answered in
                        // another. Until then both said Ihmiset on the phones
                        // that open on the list, and so did this sentence.
                        // See docs/ARCHITECTURE.md §21.
                        // The last sentence points at the toolbar, because
                        // the toolbar is the only place the button is. It sat
                        // beneath this empty state as well until 16 Sep 2026,
                        // and adding the first person took it away: whoever
                        // had just used it went looking for it where they had
                        // used it, and it had moved to the top of the screen.
                        // One place that never moves beats two that trade off.
                        Text("Sukupuu kasvaa sitä mukaa kun ihmisistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli. Voit myös lisätä ihmisen itse yläreunan painikkeesta.")
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
            // The list says the tab's word, Sukupuu, on every phone since
            // 30 Sep 2026: on a grandparent's phone and under VoiceOver it is
            // the family tree, read at a large size or aloud, and a title
            // that differed from the tab above it would part the two words
            // again. Until then it said Ihmiset, and so did the tab over it.
            // The tree has no title at all since 19 Sep 2026: it is a map,
            // drawn under the bar, and the tab is the one word that names it.
            .navigationTitle(showsTree ? LocalizedStringKey("") : LocalizedStringKey("Sukupuu"))
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
            .settingsDestinations()
            // A place card opens on this stack too, through the memories on a
            // person's card, and the small map on it opens the family's map.
            .placesMapDestinations()
            .toolbar {
                // Settings is a gear on the tabs rather than a tab of its own:
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
                // used it. Album's "+" sits beside nothing that comes and goes
                // and stays put; this bar has a conditional item in it, so
                // this one cannot.
                //
                // Not a row in the list either, and that is measured: as a row
                // above the door to the heard names it moved the audit's
                // Dynamic Type finding onto that unchanged door (13 Sep 2026),
                // and with the row gone the door passed again.
                //
                // The first two not over the tree (19 Sep 2026). The tree's
                // bar has the menu, and the same doors are behind it — the
                // drawing is the screen there, and a bar of controls over a
                // map is the thing a map does without. The gear stands over
                // it too since 30 Sep 2026, as over the list (`SettingsGear`):
                // the way to Settings had been a row in that menu, and so on
                // the one phone that opens on the tree it was nowhere to be
                // seen.
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
                // have the tree. The other direction is in the tree's menu,
                // "Näytä listana". Named for what it does, and not "Sukupuu"
                // as it was until 30 Sep 2026: the tab says that word on
                // every phone now, and two buttons of one name leave Voice
                // Control, and a test, to guess which one was meant.
                if canDrawTree && !showsTree {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            prefersList = false
                        } label: {
                            Image(systemName: "tree")
                                .elderTapTarget()
                        }
                        .accessibilityLabel("Näytä puuna")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsGear()
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
        .environment(\.openCard, { path.append($0) })
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
    @AppStorage(Elder.largerTextKey) private var largerText = false
    @State private var isTelling = false
    /// The open question pressed on this card: the Tell screen answering it.
    @State private var answering: FollowUpQuestion?
    @State private var isAsking = false
    @State private var isCorrectingName = false
    @State private var isDating = false
    @State private var isRenaming = false
    /// The picker for the face on a person's card (§25).
    @State private var isChoosingFace = false
    @State private var isConfirmingRemoval = false
    /// "Tämä olen minä" and its undoing (26 Sep 2026): the two questions, the
    /// request in flight, and the sentence under the row when the server
    /// could not be reached.
    @State private var isConfirmingMe = false
    @State private var isConfirmingNotMe = false
    @State private var isLinkingMe = false
    @State private var linkNote: LocalizedStringKey?
    /// The card's story (ARCHITECTURE §27): a composition in flight, the
    /// plans that failed — so that a failure is not retried on every redraw;
    /// a new telling changes the key, and so does *"Yritä uudelleen"* — and
    /// the sheet that corrects it.
    @State private var isComposing = false
    @State private var composeFailedFor: Set<StoryKey> = []
    @State private var composeAttempt = 0
    @State private var isEditingStory = false
    /// This card met a family server with no `/story`
    /// (`AppServices.storyNotOffered`, which the next card reads).
    @State private var storyNotOffered = false
    /// Whether the tellings under a story are unfolded. Nil until the card
    /// first appears, and then what the card had: folded under a story it
    /// opened with, unfolded on one that had none — so a story composed
    /// while somebody reads the tellings does not fold them away.
    @State private var logIsOpen: Bool?

    /// The subject as the store has it now, rather than as it was when this
    /// screen was pushed. A name corrected here has to be visible here, and the
    /// screen is handed a value rather than an id.
    private var current: Subject { store.subject(id: subject.id) ?? subject }

    /// Names that came out of speech, and only those.
    ///
    /// A photo's or an event's title is written by the app out of a place and a
    /// year; a person's and a place's is a proper noun the recognition heard,
    /// and it is wrong about one time in three (`wrangler.jsonc`: 65 % on Finnish
    /// proper nouns, which is the measurement the whole name-correction step
    /// exists for). Those are the two that need a second chance.
    private var nameCameFromSpeech: Bool {
        current.kind == .person || current.kind == .place
    }

    /// Whether "when did this happen" is a question this subject can answer.
    private var datable: Bool {
        current.kind == .photo || current.kind == .event
    }

    /// What the caption's pencil says to VoiceOver: a photograph is given a
    /// name, a moment's is changed, and a person's or a place's — heard, and
    /// wrong about one time in three — is corrected.
    private var renameLabel: LocalizedStringKey {
        if current.kind == .photo {
            return current.title.isEmpty ? "Anna kuvalle nimi" : "Vaihda kuvan nimi"
        }
        if nameCameFromSpeech { return "Korjaa nimi" }
        return "Vaihda nimi"
    }

    /// The photograph's corner: the card's, with the hairline every card has
    /// (`elderCard`), since 27 Sep 2026; 16 points and no edge until then.
    private static var picture: RoundedRectangle {
        RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous)
    }

    /// Whether a loaded photograph runs to the screen's edges, as the story
    /// card's caption wants it (ARCHITECTURE §27). iOS 26 only, where a list
    /// section's margins can be taken away (`listSectionMargins`); before it
    /// the picture keeps the card's corner inside the margins, as it did.
    private static var photographRunsToTheEdges: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
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
            && story == nil
            && !store.questions.contains { $0.subjectID == subject.id && !$0.answered }
            && !store.relations.contains {
                $0.deletedAt == nil && ($0.fromSubjectID == subject.id || $0.toSubjectID == subject.id)
            }
    }

    /// Whether this photograph can be coloured by what was told about it: it is
    /// on screen, this is not the grandparent's phone, and this phone was not
    /// told to keep its archive to itself.
    ///
    /// Nothing needs to have been told yet, since 28 Sep 2026: the colour
    /// sheet asks for the colours first (`ColourSheet`), so the Worker, which
    /// refuses a colouring with nothing to go by, is never asked without a
    /// telling. Not on her phone (the text-floor signal), whose switch promises
    /// that photographs are not coloured there (*"eikä kuvien väritystä
    /// tarjota"*, `HelpScreen`). And not on a phone kept to itself, whose
    /// onboarding promised "Perheen palvelimelle ne eivät lähde": colouring
    /// sends the photograph and those memories to the Worker, and even a
    /// refusal there arrives after the bytes have left. It is the gate that
    /// keeps transcription off that phone (`TellScreen`).
    private var colourable: Bool {
        current.kind == .photo && image != nil && !largerText && !session.isLocalByChoice
    }

    /// Whether this card is the one this phone's member is in the tree, as
    /// the family's server has it (`Session.Family.You.personSubjectID`).
    private var isMeOnServer: Bool {
        session.family?.you.personSubjectID == subject.id
    }

    /// Whether this card is waiting for the round that links it: the
    /// founder's own before the first sync, the card an invitation named
    /// before the inviter's phone had synced it, or the one "Tämä olen minä"
    /// chose while the server could not be reached (`SyncEngine.linkOwnCard`).
    /// A waiting card counts as one's own: offering the others meanwhile
    /// would let a tap overtake the link that is on its way. Only inside a
    /// family, like the offer: leaving one clears the key, and a phone kept
    /// to itself has no round on its way.
    private var isMeWaiting: Bool {
        guard let family = session.family, family.you.personSubjectID == nil else { return false }
        return session.pendingPersonLink == subject.id
    }

    private var isMe: Bool { isMeOnServer || isMeWaiting }

    /// Whether "Tämä olen minä" is offered here, since 26 Sep 2026: a family
    /// with a server behind it — a phone kept to itself has nobody to tell,
    /// and `Session.linkMe` there is always false — this member linked to no
    /// card and waiting for none, a confirmed person (rule 4: a name the
    /// recognition heard and nobody checked is nobody's to be yet), and a
    /// card no other member already is. The founder's card is made and
    /// linked as the family is created and a joiner's by the invitation made
    /// for her; an invitation made for nobody in particular left its joiner
    /// with no word in the tree and no way to get one.
    private var canBeMe: Bool {
        guard let family = session.family, family.you.personSubjectID == nil,
              session.pendingPersonLink == nil,
              current.kind == .person, current.confirmed
        else { return false }
        return !family.members.contains { $0.id != family.you.id && $0.personSubjectID == subject.id }
    }

    /// "Merkitse" on the question: the link, made now or left waiting for
    /// the round that can make it — the row and its footer say which.
    private func markMe() {
        isLinkingMe = true
        linkNote = nil
        Task {
            await session.linkMeOrLater(personSubjectID: subject.id)
            isLinkingMe = false
        }
    }

    /// "Poista merkintä" on the question: the link undone on the server, or
    /// the waiting card no longer waiting. Nothing changes on a phone that
    /// could not reach the server, and the footer says so.
    private func unmarkMe() {
        isLinkingMe = true
        linkNote = nil
        Task {
            if !(await session.unlinkMe()) {
                linkNote = "Merkintää ei voitu poistaa. Yritä uudelleen, kun yhteys on."
            }
            isLinkingMe = false
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

    // MARK: The story (ARCHITECTURE §27)

    /// The story with words in it. A cleared story travels as one with none
    /// (`MemoryStore.setStory`), and the card reads that as no story.
    private var story: Story? {
        current.story.flatMap { $0.text.isEmpty ? nil : $0 }
    }

    /// The tellings a person's story was made of that are no longer on the
    /// card — taken back here or on another phone. The plan leaves an edited
    /// story alone, so this is the card's to say (`StoryTakenBack`); under
    /// an unedited story the plan composes again or clears by itself.
    private var takenBack: [String] {
        story.map { $0.takenBack(live: StoryPlan.live(store.memories(for: subject.id))) } ?? []
    }

    /// What the plan is read from. The task on the list reruns when it
    /// changes: a telling added or taken back, the story saved, a retry.
    private struct StoryKey: Hashable {
        let live: [String]
        let story: Story?
        let attempt: Int
    }

    private var storyKey: StoryKey {
        StoryKey(
            live: StoryPlan.live(store.memories(for: subject.id)).map(\.id),
            story: current.story,
            attempt: composeAttempt
        )
    }

    /// Who composes, and nobody without a family server
    /// (`AppServices.storyComposer`).
    private var composer: StoryComposer? {
        AppServices.storyComposer { [session] in session.identity.token }
    }

    /// Whether this phone composes a story at all. Not on a phone kept to
    /// itself, which promised that nothing leaves it; not with no server to
    /// ask; and not against a server that has no `/story`, where the card is
    /// the card it was, its tellings and nothing said about a story.
    private var composes: Bool {
        composer != nil && !session.isLocalByChoice && !storyNotOffered && !AppServices.storyNotOffered
    }

    private var logOpen: Bool { logIsOpen ?? (story == nil) }

    /// The place the card's own tellings name most, for the caption: a
    /// confirmed place before any other, then the one named in the most
    /// tellings, then the one named most recently, then by name so that the
    /// choice does not move between two redraws. A place heard and not yet
    /// confirmed is shown only where no confirmed one is named, and never as
    /// a point (rule 4). None on a place's own card, which is the place.
    private var captionPlace: Subject? {
        guard current.kind != .place else { return nil }
        var named: [String: (place: Subject, tellings: Int, latest: Date)] = [:]
        for memory in store.memories(for: subject.id) {
            var seen = Set<String>()
            for id in memory.mentionedSubjectIDs {
                guard let place = store.subject(id: id), place.kind == .place,
                      place.deletedAt == nil, place.mergedInto == nil,
                      seen.insert(place.id).inserted
                else { continue }
                let before = named[place.id]
                named[place.id] = (
                    place: place,
                    tellings: (before?.tellings ?? 0) + 1,
                    latest: max(before?.latest ?? .distantPast, memory.createdAt)
                )
            }
        }
        return named.values.min { a, b in
            if a.place.confirmed != b.place.confirmed { return a.place.confirmed }
            if a.tellings != b.tellings { return a.tellings > b.tellings }
            if a.latest != b.latest { return a.latest > b.latest }
            return a.place.displayTitle < b.place.displayTitle
        }?.place
    }

    /// The plan, carried out. Clearing a story and dropping a proposal are
    /// the phone's own and happen wherever the card is read; only `compose`
    /// and `propose` leave the phone, and only when the plan still holds
    /// once the answer is back: the task is cancelled when its key changes,
    /// and a telling taken back while the model was writing must not come
    /// back as part of the story.
    private func composeIfNeeded() async {
        let key = storyKey
        let plan = StoryPlan.plan(story: current.story, memories: store.memories(for: subject.id))
        switch plan {
        case .nothing:
            return
        case .clear:
            store.setStory(subjectID: subject.id, nil)
        case .dropProposal:
            if let story = current.story { store.setStory(subjectID: subject.id, story.dismissing()) }
        case let .compose(tellings), let .propose(tellings, _):
            guard composes, let composer, !composeFailedFor.contains(key) else { return }
            isComposing = true
            defer { isComposing = false }
            var soFar: String?
            if case let .propose(_, text) = plan { soFar = text }
            let request = StoryRequest(
                subject: current,
                memories: tellings,
                tellerNames: Dictionary(uniqueKeysWithValues: tellings.compactMap { memory in
                    store.byline(for: memory).map { (memory.id, $0) }
                }),
                mentions: mentionedSubjects(in: tellings),
                lang: SpokenLanguage.current,
                soFar: soFar
            )
            do {
                let text = try await composer.compose(request)
                guard !Task.isCancelled,
                      StoryPlan.plan(story: current.story, memories: store.memories(for: subject.id)) == plan
                else { return }
                let next: Story
                if case .propose = plan, let story = current.story {
                    next = story.proposing(text, from: tellings)
                } else {
                    next = Story.composed(text, from: tellings)
                }
                // A story too long to travel is not saved: the card would
                // show one the family never receives.
                guard next.fits else {
                    composeFailedFor.insert(key)
                    return
                }
                store.setStory(subjectID: subject.id, next)
            } catch StoryComposeFailure.notOffered {
                AppServices.storyNotOffered = true
                storyNotOffered = true
            } catch {
                guard !Task.isCancelled else { return }
                composeFailedFor.insert(key)
            }
        }
    }

    /// The cards the tellings name, live ones only. `StoryRequest` keeps the
    /// confirmed among them as the names the story may use as they are; an
    /// unconfirmed one is not sent at all, and the prompt's rule 3 has the
    /// model say every other name through its teller (rule 4).
    private func mentionedSubjects(in tellings: [Memory]) -> [Subject] {
        var seen = Set<String>()
        return tellings.flatMap(\.mentionedSubjectIDs)
            .filter { seen.insert($0).inserted }
            .compactMap { store.subject(id: $0) }
            .filter { $0.deletedAt == nil && $0.mergedInto == nil }
    }

    /// Everything on the card under its photograph, in one place so that it
    /// can follow the photograph in when the card is stepped into from the
    /// album (`StepIn`). A `Group` in a `List` is no container: each section
    /// here is a section of the list as it was, and the modifier on the group
    /// reaches every one. On a card with no photograph it is the whole card.
    private var underThePhotograph: some View {
        Group {
            // The caption, right under the photograph and first on a moment's
            // card (ARCHITECTURE §27): the name, the pencil, and the chips.
            if subject.kind == .photo || subject.kind == .event {
                Section { caption }
            }

            // The colours the family said yes to, under the photograph and never
            // over it: the picture as it was taken stays the first thing on the
            // card, and this one carries its mark in its own pixels.
            if subject.kind == .photo, let colourImage {
                Section {
                    Image(uiImage: colourImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Self.picture)
                        .overlay(Self.picture.strokeBorder(Elder.rule, lineWidth: 1))
                        // Opened like the photograph above it, and under the
                        // words it is described by here.
                        .opensToTheWholeScreen(
                            colourImage,
                            label: String(localized: "Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan.")
                        )
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

            // Where it is, for a confirmed place the lookup found. Above the
            // name, as a photograph is, and above everything told about it,
            // because the map answers "where" and the memories answer "what
            // happened there".
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
                // guess drawn (rule 4). A `Text` and an `Image` rather than a
                // `Label`, for the reason the caption's date chip gives.
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

            // A place's caption, under its map as a photograph's is under
            // the picture. No place chip: the card is the place.
            if subject.kind == .place {
                Section { caption }
            }

            // The face on the card, and the way to give it one (§25). People
            // only: a place has no face and a photograph is its own picture.
            // The disc is the same `SubjectAvatar` the list and the tree
            // draw, so what is chosen here is what is drawn everywhere — and
            // the row says in words what the disc, hidden from VoiceOver like
            // every avatar, cannot.
            if subject.kind == .person {
                Section {
                    // The portrait the card opens with, since 27 Sep 2026:
                    // the disc at 136 points, centred, and the words under
                    // it on a line of their own. They stood beside a disc of
                    // 56 until then, in one row, and at the largest text
                    // size the disc was 175 points across and *Choose a
                    // face* three lines of broken words down its side
                    // (`LayoutAtSizeTests`). The disc grows with the large
                    // title rather than the body, which would take it past
                    // the phone's width.
                    //
                    // A row each, not one row with a stack in it. A row of a
                    // `List` is the frame VoiceOver draws and a test
                    // measures round the button in it, and with the disc in
                    // the same row that frame was 330 points tall round
                    // words that take 63 — the very shape the broken words
                    // had, from a row that broke nothing.
                    SubjectAvatar(subject: current, size: 136, letter: .largeTitle, scaledWith: .largeTitle)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    // The caption under the portrait, as under a photograph.
                    caption

                    Button {
                        isChoosingFace = true
                    } label: {
                        Text(current.portraitSubjectID == nil ? "Valitse kasvot" : "Vaihda kasvot")
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .buttonStyle(.borderless)
                    // Ink, like every text button since the accent
                    // became the red of removal (`Elder.wax`).
                    .foregroundStyle(Color.primary)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    // Which card this phone's member is (26 Sep 2026): "Tämä
                    // olen minä" on a phone that is nobody yet, "Tämä olet
                    // sinä" on one's own card — linked, or waiting for the
                    // round that links it — and nothing on anybody else's.
                    // Both ask first, because nothing else changes the link:
                    // `family.ts` keeps a member's card through leaving and
                    // joining again, so a link made by a slip stayed for
                    // good. `canBeMe` says where the offer is made.
                    if isMe || canBeMe {
                        Button {
                            if isMe { isConfirmingNotMe = true } else { isConfirmingMe = true }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isMe ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                                    .accessibilityHidden(true)
                                if isMe {
                                    Text("Tämä olet sinä")
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("Tämä olen minä")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .font(.body.weight(.medium))
                        }
                        .buttonStyle(.elderSecondary)
                        .disabled(isLinkingMe)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } footer: {
                    // The mark that could not be unmade now, in words — and
                    // while a card waits for the round that links it, that it
                    // is waiting rather than done.
                    if let linkNote {
                        Text(linkNote)
                            .foregroundStyle(Elder.supporting)
                    } else if isMeWaiting {
                        Text("Merkintä lähtee itsestään, kun yhteys palaa.")
                            .foregroundStyle(Elder.supporting)
                    }
                }
            }

            // What the family knows about this person in words (§26): where
            // and when she was born, what she was called, what she did. Under
            // the face and the name and above everything told, because it is
            // what a card says first — and written by a person, never by the
            // extraction (rule 4). The section, its rows and its sheets are
            // `PersonFacts.swift`'s; this screen only says where it goes.
            //
            // Above them since 30 Sep 2026, the way to add a relative: the
            // first thing under the name and the face, where the card of a
            // name just confirmed is opened to do exactly that. Its own
            // section, on the paper; the relatives it adds are listed under
            // the story (`RelationsSection`).
            if subject.kind == .person {
                Section {
                    AddRelativeButton(subject: subject)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                PersonFactsSection(subject: current)
            }

            Section {
                Button {
                    isTelling = true
                } label: {
                    // Words alone since 27 Sep 2026. The `mic.fill` icon
                    // this label carried was drawn by the prominent style on
                    // neither `main` nor this branch, at either text size
                    // (screenshots of both), while its slot kept the first
                    // line right of centre and its image element stood in
                    // the accessibility tree inside the words' frame — and
                    // the audit reported the words clipped on every card
                    // sweep that reached this button, at the default size
                    // and, once the button was on screen, at the largest:
                    // 370 by 139.33 points on the own-telling card, alone
                    // twice, frames identical to the decimal. With the icon
                    // gone the same sweeps are clean at both sizes and the
                    // words sit centred. Why the identical label audits
                    // clean on `main` was not found.
                    Text("Kerro tästä muisto")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                        // For the audit's default-size simulation, which
                        // reports the button as partially unsupported once
                        // it sits low enough on the card — y 635 on the card
                        // offered as you, clean at 563 and 345 with the code
                        // untouched (27 Sep 2026): `AccessibilityPolicy`
                        // keys the artefact on this and on nothing else.
                        .accessibilityIdentifier("card.tell")
                }
                // The card's one wax button (§22). Everything else on it is
                // ink since 27 Sep 2026 — on honey, on a tile, or on the
                // paper — so that the one thing to do here is the one thing
                // in the accent.
                .elderPrimary(true)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // The story, under the button that adds to it and above the
            // tellings it is read from (ARCHITECTURE §27).
            storySection

            let memories = store.memories(for: subject.id)
            // This phone's own tellings taken back from this card within the
            // window, offered back where the memories end (§19). Read beside
            // `memories` because both branches below show it: a card whose
            // only telling was taken back is empty and still has a way back.
            let restorable = store.restorable(for: subject.id, author: session.identity.memberID)
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
            // All of them, beside whatever is the card's own: above it while
            // there is none, below it once there is. Until 27 Sep 2026 they
            // were listed only while nothing was filed under the card, so that
            // no telling was listed twice — and one telling a grandmother had
            // of her own hid every photograph's that named her. Leaving out
            // the twice is `memories(mentioningElsewhere:)`'s job.
            let mentions = store.memories(mentioningElsewhere: subject.id)
            if memories.isEmpty, story == nil {
                namedElsewhere(mentions)
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
                    ForEach(restorable) { RestorableMemoryRow(memory: $0) }
                }
            } else if memories.isEmpty {
                // A person's story whose every telling has been taken back,
                // which the plan leaves for a person to decide about: the
                // note under the story says so, in place of the sentence that
                // nothing has been told. What this phone took back is still
                // offered back here, as on any card.
                if !restorable.isEmpty {
                    Section {
                        ForEach(restorable) { RestorableMemoryRow(memory: $0) }
                    }
                }
                namedElsewhere(mentions)
            } else if story != nil {
                // The tellings under a story, behind one button (version 1's
                // log, ARCHITECTURE §27): folded when the card opens with a
                // story, because the story is what they say, and each still
                // the row it is on every card — the teller's own with its
                // button (`MemoryRow`). Newest first, as ever: the telling
                // just told is the first under the story it changed.
                Section {
                    logFold(count: memories.count)
                    if logOpen {
                        ForEach(memories) { memory in
                            MemoryRow(memory: memory, cardID: current.id)
                        }
                    }
                    restorableRows(restorable)
                }
                namedElsewhere(mentions)
            } else {
                Section {
                    ForEach(memories) { memory in
                        MemoryRow(memory: memory, cardID: current.id)
                    }
                    restorableRows(restorable)
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
                    // The identifier is for
                    // `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                    // and nothing else (26 Sep 2026).
                    .accessibilityIdentifier("card.memoriesHeading")
                }
                namedElsewhere(mentions)
            }

            // Relationships only for people: a photo or an event has none.
            // Under the story and its tellings since 28 Sep 2026, which are
            // the top of the card; above them until then. The way to add one
            // is not here but at the top, since 30 Sep 2026.
            if subject.kind == .person {
                RelationsSection(subject: subject)
            }

            if colourable {
                Section {
                    Button {
                        isColouring = true
                    } label: {
                        Label {
                            Text("Väritä kerronnan mukaan")
                                // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                                // and nothing else (29 Sep 2026). On the words
                                // rather than the button, as `card.ask`'s: the
                                // audit reports the label.
                                .accessibilityIdentifier("card.colour")
                        } icon: {
                            Image(systemName: "paintpalette")
                        }
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .elderTapTarget()
                    }
                    .buttonStyle(.elderSecondary)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    // Said at the button, before anything leaves: the
                    // photograph goes to the model unsealed, and the words told
                    // about it go with it. Until 26 Sep 2026 this called
                    // colouring the one place a photograph left unsealed, which
                    // stopped being true on 19 Sep, when a telling about a
                    // photograph began sending it too — `WhereMemoriesGo` says
                    // that one. The last sentence is about the archive and says
                    // so, because right after a named service it would read as
                    // a promise made on that service's behalf. It names the
                    // colours since 28 Sep 2026, when the sheet began with a
                    // telling that is saved like any other.
                    Text("Kuva ja siitä kerrotut muistot lähetetään OpenRouter-palvelun kautta tekoälylle väritettäväksi. Niillä ei opeteta tekoälyä. Värejä ei tallenneta arkistoon ennen kuin vastaat.")
                        .foregroundStyle(Elder.supporting)
                        // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                        // and nothing else (27 Sep 2026).
                        .accessibilityIdentifier("card.colourNote")
                }
            }

            let open = store.questions.filter { $0.subjectID == subject.id && !$0.answered }
            if !open.isEmpty {
                Section {
                    ForEach(open) { question in
                        // The row is the way to answer it (26 Sep 2026): the
                        // Tell screen on this card, with the question as its
                        // title. Every row, the ones asked of somebody else by
                        // name included — the aim narrows whose Kerro tab
                        // offers a question, never who may answer it, and on
                        // every other phone this card is where it is read.
                        // Until then the rows were text, and answering one
                        // meant finding it again under "Kerro tästä muisto".
                        Button {
                            answering = question
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    // A person's name on a question turns a
                                    // prompt into a request. AI questions stay
                                    // unattributed — and so is your own here:
                                    // with the default display name the line
                                    // read "Minä kysyy", wrong in both
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
                                    // Asked of somebody else by name. Everyone
                                    // sees it here and anyone who knows may
                                    // answer — only the Kerro tab and the
                                    // notification are theirs alone — so the
                                    // family is told whose question it is.
                                    if let target = question.targetName, !target.isEmpty,
                                       question.targetMemberID != session.identity.memberID {
                                        Text("Kenelle: \(target)")
                                            .font(.subheadline)
                                            .foregroundStyle(Elder.supporting)
                                    }
                                }
                                Spacer(minLength: 0)
                                // What pressing does, for the eye; the hint
                                // says it to VoiceOver.
                                Image(systemName: "mic.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .elderTapTarget()
                        }
                        // Plain, so the row keeps its own colours: a List tints
                        // every word of a default-styled button.
                        .buttonStyle(.plain)
                        .accessibilityHint("Vastaa kertomalla")
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
                    Label {
                        Text("Kysy perheeltä")
                            // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                            // and nothing else (27 Sep 2026). On the words
                            // rather than the button: the audit reports the
                            // label.
                            .accessibilityIdentifier("card.ask")
                    } icon: {
                        Image(systemName: "questionmark.bubble")
                    }
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .elderTapTarget()
                }
                .buttonStyle(.elderSecondary)
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
    }

    var body: some View {
        List {
            if subject.kind == .photo {
                Section {
                    photoView
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                // To the screen's edges, once there is a picture to run
                // there (ARCHITECTURE §27): the caption under it is the
                // card's name.
                .photographToTheEdges(image != nil)
            }
            underThePhotograph
                .stepInFollows()
        }
        // The name small in the bar and large in the caption, which is where
        // it is read and changed; the bar keeps it while the card scrolls.
        .navigationTitle(current.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("Merkitäänkö tämä sinuksi?", isPresented: $isConfirmingMe) {
            Button("Merkitse") { markMe() }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Sukupuu kertoo sukulaisuudet sinun kannaltasi. Voit poistaa merkinnän myöhemmin tältä kortilta.")
        }
        .alert("Poistetaanko merkintä?", isPresented: $isConfirmingNotMe) {
            Button("Poista merkintä", role: .destructive) { unmarkMe() }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Kortti jää perheen arkistoon. Vain merkintä siitä, että tämä olet sinä, poistuu.")
        }
        // The coordinate this card's map needs, asked for at the moment the
        // map is wanted. The sweeps in `KinloreApp` run at launch and on the
        // return to the foreground; a place confirmed in the telling that
        // named it therefore had a card and no map until the app had been
        // closed and opened. `PlaceResolver.resolve` says the rest.
        .task {
            await places?.resolve(current, in: store)
        }
        // The story, composed when the plan says the tellings have changed
        // (`StoryPlan`), and on the list rather than on a row: a lazy row
        // that scrolls away cancels its task, and a composition with it.
        .task(id: storyKey) {
            await composeIfNeeded()
        }
        .onAppear {
            if logIsOpen == nil { logIsOpen = story == nil }
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
            CardOpeningStack {
                TellScreen(target: subject, onClose: { isTelling = false })
            }
        }
        .sheet(item: $answering) { question in
            CardOpeningStack {
                TellScreen(target: subject, question: question, onClose: { answering = nil })
            }
        }
        .sheet(isPresented: $isAsking) {
            AskQuestionSheet(subject: subject)
        }
        .sheet(isPresented: $isColouring) {
            if let image {
                ColourSheet(subject: current, photograph: image)
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
        .sheet(isPresented: $isEditingStory) {
            StoryEditSheet(initial: story?.text ?? "") { text in
                let live = StoryPlan.live(store.memories(for: subject.id))
                let next = current.story?.edited(to: text, live: live)
                    ?? Story(text: text, composedFrom: live.map(\.id), editedAt: .now)
                store.setStory(subjectID: subject.id, next)
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
                // Before the fit and the clip: the approach draws the picture
                // larger inside the frame the fit gives it, and the clip keeps
                // it there (`StepIn`).
                .stepInApproach()
                .scaledToFit()
                .pictureEdge(runsToTheEdges: Self.photographRunsToTheEdges)
                // A tap opens it to the whole screen, where it can be brought
                // closer: a face in a group photograph is a few points wide
                // here, and until 28 Sep 2026 a tap did nothing at all.
                //
                // The card's main content had no description until 26 Sep
                // 2026: the audit said "Element has no description", and
                // VoiceOver passed over the photograph as if it were not
                // there. Its name is the card's title, or the "Valokuva" an
                // untitled one is shown under — a `String` already looked up
                // by `displayTitle`, so it is read as it stands rather than
                // looked up a second time as a key. The blind card draws its
                // photograph in `BlindCardView`, where no label may name the
                // proposal; this is not that picture.
                .opensToTheWholeScreen(image, label: current.displayTitle)
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
                        .foregroundStyle(Color.primary)
                        .elderTapTarget()
                }
            }
        } else {
            Self.picture
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
        .elderCard()
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

    /// The caption (ARCHITECTURE §27, version 3 of the story card): the name
    /// in the display face with the pencil that changes it, and under them
    /// the chips — when it happened, for a photograph or a moment, and where,
    /// for any card but a place's. Rows of the section it is put in, on the
    /// paper, so the same caption sits under a photograph, a portrait and a
    /// map.
    ///
    /// The pencil was a honey chip on a photograph's card ("Anna kuvalle
    /// nimi") and a toolbar button on a person's until 28 Sep 2026. Beside
    /// the name it says what it changes, and VoiceOver hears which of the
    /// three it is (`renameLabel`).
    @ViewBuilder
    private var caption: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(current.displayTitle)
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Down to the pencil's middle while the name is one line.
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Button {
                if nameCameFromSpeech { isCorrectingName = true } else { isRenaming = true }
            } label: {
                Image(systemName: "pencil")
                    .font(.title3.weight(.semibold))
                    .elderTapTarget()
            }
            .buttonStyle(.borderless)
            // Ink, like every text button since the accent became the red of
            // removal (`Elder.wax`).
            .foregroundStyle(Color.primary)
            .accessibilityLabel(renameLabel)
            .accessibilityIdentifier("subject.rename")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        let place = captionPlace
        if datable || place != nil {
            ChipRow {
                if datable {
                    // The date chip as it was on its own row until 28 Sep
                    // 2026: a `Text` and an `Image` rather than a `Label`,
                    // which the audit reported as clipped in every shape.
                    // Not on a person's or a place's card, on purpose:
                    // `dateHint` means when this happened, and a person's
                    // date would have to mean a birth or a death, which the
                    // column does not say and the app must not guess.
                    Button {
                        isDating = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                            Text(current.dateHint?.displayText ?? String(localized: "Lisää ajankohta"))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("caption.date")
                        }
                        .font(.body.weight(.medium))
                    }
                }
                if let place {
                    placeChip(place)
                }
            }
        }
    }

    /// Where the card's tellings happened, one tap from the family's map
    /// (ARCHITECTURE §27): the map centred on a place with a point, the map
    /// already placing one without — what "Merkitse kartalle" on the place's
    /// own card opens — and the place's card for a place nobody has
    /// confirmed, which is never drawn as a point (rule 4). Nothing to fill
    /// in: telling is still how a place gets onto a card.
    @ViewBuilder
    private func placeChip(_ place: Subject) -> some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
            Text(verbatim: place.displayTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("caption.place")
            if !place.confirmed {
                // Heard, and not yet checked: said in the glyph here and in
                // words to VoiceOver, never as a point on the map.
                Image(systemName: "questionmark.circle")
            }
        }
        .font(.body.weight(.medium))
        // The date chip's honey, drawn on the words: a link in a list row
        // takes no button style from `ChipRow`, and without this the place
        // stood beside the date chip as bare words a line above its middle.
        .elderSecondarySurface()
        Group {
            if !place.confirmed {
                NavigationLink(value: place) { label }
                    .accessibilityLabel(Text("Paikka, odottaa tarkistusta: \(place.displayTitle)"))
                    .accessibilityHint("Avaa paikan kortin.")
            } else if place.place?.precision.mapSpanMetres != nil {
                NavigationLink(value: PlacesMapRoute(focus: place.id)) { label }
                    .accessibilityLabel(Text("Paikka: \(place.displayTitle)"))
                    .accessibilityHint("Avaa perheen kartan tämän paikan kohdalta.")
            } else {
                NavigationLink(value: PlacesMapRoute(focus: place.id, editing: true)) { label }
                    .accessibilityLabel(Text("Paikka: \(place.displayTitle)"))
                    .accessibilityHint("Avaa kartan, jolla paikan voi merkitä napauttamalla.")
            }
        }
        // Plain, as `PlaceMapCard`'s link is: with only the style `ChipRow`
        // hands its row, the list drew the link its own way, and the chip's
        // shape above is what a tap on it is meant to land on.
        .buttonStyle(.plain)
        // A link in a list row gets a chevron, and one beside a chip reads
        // as a second control (`PlaceMapCard`).
        .navigationLinkIndicatorVisibility(.hidden)
        .accessibilityIdentifier("card.place")
    }

    /// The story (ARCHITECTURE §27): the text in a card on the paper with
    /// where it came from and the way to correct it; under it what a person
    /// has to decide about it; and while it is being composed, or could not
    /// be, a line that says so. Nothing at all on a card with no story and
    /// nothing under way — the tellings under the button are the card, as
    /// they always were.
    @ViewBuilder
    private var storySection: some View {
        let failed = composeFailedFor.contains(storyKey)
        if story != nil || isComposing || failed {
            Section {
                if let story {
                    VStack(alignment: .leading, spacing: 14) {
                        StoryBody(text: story.text)
                        StoryProvenance(memoryCount: story.composedFrom.count, edited: story.isEdited) {
                            isEditingStory = true
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .elderCard()
                    .onThePaper()
                    if story.isEdited, !takenBack.isEmpty {
                        let live = StoryPlan.live(store.memories(for: subject.id))
                        StoryTakenBack(
                            gone: takenBack.count,
                            of: story.composedFrom.count,
                            canCompose: composes && !live.isEmpty,
                            onKeep: { store.setStory(subjectID: subject.id, story.keeping(live: live)) },
                            onLetGo: { store.setStory(subjectID: subject.id, nil) }
                        )
                        .onThePaper()
                    }
                    if let proposal = story.proposal {
                        StoryProposalCard(
                            proposal: proposal,
                            onAccept: { store.setStory(subjectID: subject.id, story.accepting()) },
                            onDismiss: { store.setStory(subjectID: subject.id, story.dismissing()) }
                        )
                        .onThePaper()
                    }
                }
                if isComposing {
                    StoryComposing()
                        .padding(.horizontal, 4)
                        .onThePaper()
                }
                if failed {
                    StoryComposeFailed { composeAttempt += 1 }
                        .padding(.horizontal, 4)
                        .onThePaper()
                }
                // Said where the story is, on every phone that composes one:
                // the tellings leave the phone for it. A row and not the
                // section's footer, whose text a list stops growing.
                if composes {
                    StoryConsent()
                        .padding(.horizontal, 4)
                        .onThePaper()
                }
            }
        }
    }

    /// The one button over the tellings under a story.
    private func logFold(count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { logIsOpen = !logOpen }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: logOpen ? "chevron.down" : "chevron.right")
                    .accessibilityHidden(true)
                Group {
                    if logOpen {
                        Text("Piilota muistot")
                    } else if count == 1 {
                        Text("Näytä muisto")
                    } else {
                        Text("Näytä \(count) muistoa")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.elderSecondary)
        .accessibilityIdentifier("storyCard.logs")
        .onThePaper()
    }

    /// This phone's own tellings taken back from this card within the window
    /// (§19), on the paper under the last bubble, as `MemoryRow`'s own
    /// buttons are: a row of the list's own white here would be the one card
    /// in a section of bubbles. On a card with no telling left they stay on
    /// the white, in one section with the sentence that says so.
    private func restorableRows(_ restorable: [Memory]) -> some View {
        ForEach(restorable) {
            RestorableMemoryRow(memory: $0)
                .onThePaper()
        }
    }

    /// The tellings filed under something else that name this card, each
    /// under the way to where it is filed.
    ///
    /// On a person's card only the way, once for each card, since 30 Sep 2026.
    /// Each telling that named them was listed whole under its way, so a
    /// person named in several was a long scroll with the relatives far below
    /// it (the user's phone, 29 Sep 2026). In the user's words: only the
    /// picture and the name, and a tap opens the whole memory. The header
    /// still counts the tellings. A place's card keeps them whole, because a
    /// place is only ever named, and the tellings that name it are all it has
    /// to show. A telling whose card is gone has no way to lead to, and is
    /// listed whole on either.
    @ViewBuilder
    private func namedElsewhere(_ mentions: [Memory]) -> some View {
        if !mentions.isEmpty {
            Section {
                if subject.kind == .person {
                    let homes = mentions.compactMap(home(of:)).reduce(into: [Subject]()) { homes, home in
                        if !homes.contains(where: { $0.id == home.id }) { homes.append(home) }
                    }
                    ForEach(homes) { home in
                        // On the paper, as above a telling: a way on, not a
                        // card of its own.
                        NamedElsewhereLink(home: home, tellingBelow: false)
                            .onThePaper()
                    }
                    ForEach(mentions.filter { home(of: $0) == nil }) { memory in
                        MemoryRow(memory: memory, cardID: current.id)
                    }
                } else {
                    ForEach(mentions) { memory in
                        // A row of its own above the telling's, because a link
                        // anywhere in a row takes the whole row over, and the
                        // telling's row has buttons of its own.
                        if let home = home(of: memory) {
                            NamedElsewhereLink(home: home)
                                // On the paper like the telling under it: the
                                // bubble below is the surface, and this row is
                                // the way to where it is filed. No white of its
                                // own, which above the honey would be a card
                                // over a card.
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        // On the paper, in the honey bubble every telling is
                        // read in since 27 Sep 2026 (`MemoryRow`). The row
                        // itself drew `systemGray4` here until 19 Sep 2026
                        // and `Elder.card` after; the bubble is the surface
                        // now, and the row says so for itself.
                        MemoryRow(memory: memory, cardID: current.id)
                    }
                }
            } header: {
                // Two whole sentences rather than one with a number in it:
                // the count's own header says why, and Finnish would want
                // "yhdessä" here in any case. *Muualla*, because on a card
                // with tellings of its own the heading is what tells the two
                // lists apart.
                Group {
                    if mentions.count == 1 {
                        Text("Mainittu muualla yhdessä muistossa")
                    } else {
                        Text("Mainittu muualla \(mentions.count) muistossa")
                    }
                }
                .foregroundStyle(Elder.supporting)
                // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                // and nothing else (30 Sep 2026).
                .accessibilityIdentifier("namedElsewhere.heading")
            }
        }
    }

    /// The card a telling that names this one is filed under, while there is
    /// one to open: not this card (a card merged into it), and not a card
    /// taken away.
    private func home(of memory: Memory) -> Subject? {
        guard let home = store.subject(id: memory.subjectID),
              home.id != subject.id, home.deletedAt == nil
        else { return nil }
        return home
    }
}

private extension View {
    /// A row of the card that lies on the paper rather than on the list's
    /// white: the room above and below that a bubble has, no inset at the
    /// sides, and no separator.
    func onThePaper() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The photograph's section without its side margins, where a list can
    /// be told so (iOS 26): the picture runs to the screen's edges.
    @ViewBuilder
    func photographToTheEdges(_ runs: Bool) -> some View {
        if runs {
            if #available(iOS 26.0, *) {
                listSectionMargins(.horizontal, 0)
            } else {
                self
            }
        } else {
            self
        }
    }

    /// The photograph's edge, in one place (§27): square to the screen's
    /// edges where it runs to them — clipped, so that the step-in's four per
    /// cent stays inside its frame — and the card's corner with its hairline
    /// where it cannot. Whatever bounds the picture's size goes here too.
    @ViewBuilder
    func pictureEdge(runsToTheEdges: Bool) -> some View {
        if runsToTheEdges {
            clipped()
        } else {
            let shape = RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous)
            clipShape(shape)
                .overlay(shape.strokeBorder(Elder.rule, lineWidth: 1))
        }
    }
}

extension EnvironmentValues {
    /// Pushes a card onto the stack the view is on — the people tab's, the
    /// album's, or since 30 Sep 2026 a Tell screen's (`CardOpeningStack`),
    /// the stacks that open cards. For a way to a card inside a
    /// list row, which a `NavigationLink` cannot be without taking the whole
    /// row (`MemoryRow.namedHereLinks`, `HeardNameRow.open`). Set on the
    /// stack itself, so the cards it pushes have it too; nil anywhere else.
    @Entry var openCard: ((Subject) -> Void)? = nil
}

/// A stack that opens cards the way the album's and the people tab's do. It
/// carries the card and map destinations, and `openCard` for the rows on a
/// card that cannot be links.
///
/// The Tell screens stand on one since 30 Sep 2026, when a name confirmed on
/// the result got its way to its card (`ConfirmedNameNote`). Without
/// `openCard`, a telling read on a card pushed there would fall back to name
/// links that take its whole row (`HeardNameRow.open`).
struct CardOpeningStack<Content: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Subject.self) { subject in
                    SubjectDetailScreen(subject: subject)
                        // The Tell tab hides its bar once a telling is under
                        // way, and a card pushed over it needs its own back.
                        .toolbar(.visible, for: .navigationBar)
                }
                .placesMapDestinations()
        }
        .environment(\.openCard, { path.append($0) })
    }
}

private struct MemoryRow: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openCard) private var openCard
    @State private var isConfirmingRemoval = false
    @State private var isEditingText = false
    @State private var isMoving = false
    @State private var isChoosing = false
    @State private var chosen: MemoryChoice?
    let memory: Memory
    /// The card the row is read on, which its names do not link back to.
    var cardID: String?

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
        if session.isOutOfMinutes { return "Ääni tallessa — kuukauden litterointiaika käytetty" }
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

    /// The names this telling says that the family has already checked.
    ///
    /// Somebody who read "Hilda" where it should say Hilma had no way from
    /// the story to the name until 28 Sep 2026: a name nobody had checked
    /// was a link (`heardHere`), and a checked one was a word in the text and
    /// nothing more. People and places, whose names were heard rather than
    /// written by the app; only those the words say (`NameInText`), which is
    /// what a reader can notice is wrong; and not the card being read, which
    /// a chip would only open again.
    private var namedHere: [Subject] {
        var seen: Set<String> = []
        return memory.mentionedSubjectIDs
            .compactMap { store.subject(id: $0) }
            .filter { named in
                named.confirmed && named.deletedAt == nil
                    && (named.kind == .person || named.kind == .place)
                    && named.id != cardID
                    && NameInText.carries(named.title, in: memory.body)
                    && seen.insert(named.id).inserted
            }
    }

    /// Honey chips, as the card's other small ways on are, and buttons
    /// rather than links. A `NavigationLink` in a list row takes the whole
    /// row whatever its style: in the first build it drew as the list's own
    /// link and not as a chip, and a tap on the story's words opened the
    /// card (28 Sep 2026). A button keeps to its own frame, and the stack
    /// it pushes onto comes from the screen around it (`openCard`).
    ///
    /// The icon and the name side by side rather than a `Label` since
    /// 30 Sep 2026, the shape of the caption's date and place chips (the
    /// note on the date chip says why), laid out where they are used by
    /// `ChipFlow`, which takes each chip at its own width.
    private func namedHereLinks(_ open: @escaping (Subject) -> Void) -> some View {
        ForEach(namedHere) { named in
            Button {
                open(named)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: named.kind.symbolName)
                        .accessibilityHidden(true)
                    Text(verbatim: named.displayTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.elderSecondary)
            .accessibilityIdentifier("memory.named")
            .accessibilityHint("Avaa kortin. Siellä nimen voi myös korjata.")
        }
    }

    /// The teller's disc and the line under the telling. The disc is her
    /// own — her face, when her card has one — or the initial of the name
    /// the telling arrived under, and none for a teller who asked not to be
    /// named; the line is `MemoryStore.byline(for:)`'s answer, which makes
    /// the same three choices.
    private var byline: some View {
        HStack(spacing: 10) {
            // Scaled with the large title and not the body: grown with the
            // body, the disc is 100 points at the largest text size and left
            // the date beside it a column narrower than itself — *9/27/202*
            // and *6* on the next line (`LayoutAtSizeTests`). With the
            // title's growth it is 56, and the widest word of the line has
            // room.
            if let id = memory.tellerSubjectID, let teller = store.subject(id: id), !teller.title.isEmpty {
                SubjectAvatar(subject: teller, size: 32, scaledWith: .largeTitle)
            } else if memory.tellerHidden != true {
                SubjectAvatar(initial: memory.authorName, size: 32, scaledWith: .largeTitle)
            }

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
        }
    }

    /// The original audio is part of the product, not a step towards it.
    @ViewBuilder
    private var playback: some View {
        if memory.audioFilename != nil || memory.audioR2Key != nil {
            MemoryPlaybackButton(memory: memory)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The honey bubble (27 Sep 2026): what somebody said, on the
            // warm surface `Elder.honey` is for. The edge is the `rule`
            // hairline and nothing else — honey on paper is 1.10:1, and a
            // shadow would make a button of a surface that is not one. Ink
            // on it measures 13.74:1 and `supporting` 6.73:1, so the words,
            // the byline and the listen button sit inside; the names heard
            // and the teller's own button stay out on the paper, where
            // *Poista* keeps the red it was measured in.
            VStack(alignment: .leading, spacing: 10) {
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

                // Who told it and when, and the recording. On one line while
                // both fit on it whole, and the button under the byline
                // otherwise — always under it at the accessibility sizes.
                // They shared a line at every size until 27 Sep 2026, and
                // at the largest the button was a column five characters
                // wide and 465 points tall beside the name
                // (`LayoutAtSizeTests`, H49 L6).
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        byline
                        playback
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            byline
                            Spacer(minLength: 0)
                            playback
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            byline
                            playback
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderBubble()

            // The checked names in the words above, each the way to its card,
            // where a wrong one is corrected (§17) — and the correction there
            // offers to put the right name back into these words. None where
            // no stack around the row opens cards.
            //
            // Each chip its own width and the row wrapping whole chips, one
            // to a row at the accessibility sizes, since 30 Sep 2026. Until
            // then a `ViewThatFits` chose between a line of `Label`s and a
            // column of them, and it took the line where the line did not
            // fit: at the grandmother's text floor the film drew *Pu-/uma/la*,
            // *Hel/mi* and *Toi/vo* side by side, each broken inside the word
            // (`LayoutAtSizeTests.testTheNamesUnderATellingBreakNoWord`, red
            // on that row). From the leading edge, where the column stood.
            if let openCard, !namedHere.isEmpty {
                ChipFlow(spacing: 10, stacked: typeSize.isAccessibilitySize, centred: false) {
                    namedHereLinks(openCard)
                }
                .padding(.horizontal, 4)
            }

            // Under the bubble and not in it, since the bubble came: the
            // rows carry *Poista* in `destructive`, which is measured on the
            // paper and not on honey, where a coloured word is never a
            // sentence (`Elder.honey`).
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
                            onReject: { store.remove(subjectID: subject.id) },
                            open: openCard
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            // The teller's own, the day after: correct the words, move the
            // telling, take it back (`MemoryChoiceSheet`). The result screen
            // offers these in the seconds after telling; a memory read back
            // on its card tomorrow is the same "I did not mean to say that",
            // and until 3 Sep 2026 the card had no answer to it.
            //
            // One button and not the three it opens, since 28 Sep 2026. The
            // three stood under every telling of one's own, and a card of a
            // few tellings was mostly buttons, a page longer than its words.
            // Ink, because the accent is the red of removal (`Elder.wax`).
            //
            // Own means told on this phone or by this member. A memory told
            // here carries no author until the pull hands it back, and one
            // that never syncs (a phone kept to itself) never gets one; the
            // server refuses a tombstone from anybody but the author either way.
            if memory.authorID == nil || memory.authorID == session.identity.memberID {
                Button("Muokkaa tai poista") { isChoosing = true }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .elderTapTarget()
            }
        }
        // On the paper: the bubble is the surface, and the row's own white
        // under it would have been a card under a card.
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .sheet(isPresented: $isChoosing, onDismiss: afterChoosing) {
            MemoryChoiceSheet(
                opening: memory.isAwaitingTranscription ? nil : MemoryChoiceSheet.opening(of: memory.body),
                canEditText: !memory.isAwaitingTranscription
            ) { choice in
                chosen = choice
                isChoosing = false
            }
        }
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
            // Two sentences, both true. Until 26 Sep 2026 this said the
            // recording went with the memory and nothing could bring it
            // back; rule 3 keeps the recording, and the card now offers the
            // telling back for thirty days (§19) — unless the card itself
            // goes with it, a moment that held nothing else, and then there
            // is no card to come back to. An if rather than a ternary, so
            // that `localisation-check.mjs` sees both keys.
            if store.cardGoesWith(memoryID: memory.id) {
                Text("Muisto poistuu perheen näkyvistä kaikilta puhelimilta ja tämä kortti sen mukana, eikä sitä voi palauttaa.")
            } else {
                Text("Muisto poistuu perheen näkyvistä kaikilta puhelimilta. Voit palauttaa sen tältä kortilta 30 päivän ajan.")
            }
        }
        .sheet(isPresented: $isEditingText) {
            MemoryTextSheet(memory: memory)
        }
    }

    /// What was chosen on the sheet, done once the sheet is gone: nothing
    /// can be presented over a sheet that is leaving, and the removal asks
    /// its question on the card, over the telling it is about.
    private func afterChoosing() {
        guard let choice = chosen else { return }
        chosen = nil
        switch choice {
        case .text: isEditingText = true
        case .move: isMoving = true
        case .removal: isConfirmingRemoval = true
        }
    }
}

private enum MemoryChoice {
    case text, move, removal
}

/// What the teller can do to her own telling on its card, behind the row's
/// one button.
///
/// A sheet of plain buttons rather than a menu or a confirmation dialog: a
/// menu's rows barely grow with the text size and no UI test here has been
/// able to open one, and on iOS 26 a confirmation dialog in a list comes up
/// as a popover that draws no cancel action (`SettingsScreen`). The window's
/// full height and no medium detent, for `TreePersonSheet`'s measured
/// reason: a half-height sheet draws its content 4 % smaller than it lays it
/// out, and the audit calls every line clipped.
private struct MemoryChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The telling's first words, because the sheet covers the card and the
    /// teller may have several there. Nil while the text is on its way.
    let opening: String?
    /// Not while the text is still on its way: there is nothing to correct.
    let canEditText: Bool
    let choose: (MemoryChoice) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tämä muisto")
                            .font(Elder.display(.title2))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let opening {
                            Text(verbatim: opening)
                                .elderBody()
                                .foregroundStyle(Elder.supporting)
                        }
                    }
                    .padding(.bottom, 8)

                    // The words the family reads, corrected by the one who
                    // said them. The name step reaches a heard name; a wrong
                    // ordinary word in the one sentence that mattered —
                    // "kuoli" for "kasvoi" — it cannot, and at the measured
                    // error rate that word is common. No model call and no
                    // minutes: the body is rewritten by hand, and rule 3's
                    // recording and raw transcript stay exactly as they were.
                    if canEditText {
                        action("Muokkaa tekstiä") { choose(.text) }
                    }
                    // Where the telling is filed. The AI's placement could be
                    // corrected nowhere until 5 Sep 2026 (finding #27); the
                    // same sheet the result screen opens.
                    action("Siirrä toiselle kortille") { choose(.move) }
                    // The rarest thing done here, and the one that must never
                    // be hit by mistake: apart from the others, in the red it
                    // was measured in on the paper, and it asks first.
                    action("Poista tämä muisto", in: Elder.destructive) { choose(.removal) }
                        .padding(.top, 12)

                    Button {
                        dismiss()
                    } label: {
                        Text("Sulje")
                            .frame(maxWidth: .infinity)
                            .elderTapTarget()
                    }
                    .padding(.top, 16)
                }
                .padding(Elder.screenPadding)
                // Ink, for the tree menu's reason (`TreeMenuSheet`).
                .tint(Color.primary)
            }
            .elderSurface()
        }
    }

    /// A title and nothing else, the width inside the label so that the
    /// whole row takes the tap — the tree's sheets' rows.
    private func action(
        _ title: LocalizedStringKey,
        in colour: Color = .primary,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(colour)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderTapTarget()
        }
        .buttonStyle(.borderless)
    }

    /// Whole words up to about sixty characters, and an ellipsis if the
    /// telling goes on: enough to say which one, and never a line limit,
    /// which the audit reports as clipped text.
    static func opening(of body: String) -> String? {
        let words = body.split(whereSeparator: \.isWhitespace)
        guard let first = words.first else { return nil }
        var line = String(first.prefix(60))
        for word in words.dropFirst() {
            if line.count + 1 + word.count > 60 { return line + "…" }
            line += " " + word
        }
        return line.count < first.count ? line + "…" : line
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
                    .elderCard()
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
                    .foregroundStyle(Color.primary)
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
