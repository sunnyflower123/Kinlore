import SwiftUI
import UIKit

/// The family drawn as a tree: a generation to a row, a line between a
/// couple, a bracket from parents down to their children, a bar over
/// siblings — and under every name, one word for what that person is to
/// whoever holds the phone.
///
/// Rebuilt from zero on 25 Sep 2026, after the shape before it was used on an
/// iPhone 13 mini. That one named the generations on a rail down the window's
/// left edge, and the rail took 156 of the phone's 375 points: the words
/// stood over the names whenever the family was wider than what was left,
/// which at 132 points a place is any family of three. Words pinned to the
/// window over a drawing that moves under them cannot be kept apart from it
/// on a phone that narrow, so nothing is pinned any more. Every word is inside
/// the drawing and moves and scales with it, and what the rail used to say
/// about a row, each card now says about itself — *Vanhempasi*,
/// *Sisaruksesi*, *Puolisosi vanhempi* (`Kinship`), and *Sinä* on your own.
/// Gender-neutral by construction in both languages, because the archive
/// stores no gender, and said only where it is exact: a wrong relationship is
/// worse than a missing one (rule 4), for a word as much as for a line.
///
/// The drawing is a map. It moves in both directions under one finger, grows
/// about two fingers pinching it, and two buttons take the place of the
/// magnifiers a hand that cannot pinch used to get: *Koko suku* fits the whole
/// family in the window, and *Sinä* flies to your own card at its natural
/// size. A tap on a person flies to them as well, into the upper part of the
/// window, and their sheet comes up; when it goes, they are there with their
/// name. Below `detail` the names and words go and the discs stay, each still
/// a tap target; a tap at that size flies to the person at 1×, so the pinch
/// is optional. The map opens at its natural size and never smaller: the
/// reader may shrink this drawing, the app may not do it for them
/// (`Coordinator.open`).
///
/// Confirmed people and confirmed relationships only (rule 4): a proposal in
/// a picture of the family is the guess drawn as fact. Where everybody lands
/// is `FamilyTreeLayout`, checked by `scripts/family-tree-layout-check.swift`;
/// which word each card gets is `Kinship`, checked by
/// `scripts/kinship-check.swift`. This view draws both and decides nothing.
///
/// A grandparent's phone (the text-floor signal) and VoiceOver get the list,
/// and the relationships as lists on each person's card, where they read at
/// the largest size and aloud — a picture of lines is nothing to read. That
/// was the whole case against drawing the tree (ARCHITECTURE §8, item 13),
/// and it is why the cut could be reversed: the phone it was a trap for does
/// not see it.
struct FamilyTreeView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Names heard and not yet checked. The door to them is in the menu, with
    /// a mark on the menu's button while any wait, so the tree hides nothing
    /// the list shows.
    var heardCount = 0
    /// Opens a person's card. The navigation stack belongs to Ihmiset, and so
    /// do the other doors the menu opens.
    var onOpen: (Subject) -> Void = { _ in }
    var onHeard: () -> Void = {}
    var onSettings: () -> Void = {}
    var onList: () -> Void = {}
    var onAddPerson: () -> Void = {}

    /// The last thing asked of the map — fit, fly, zoom — numbered so that
    /// the canvas performs each once and only once.
    @State private var command: TreeCommand?
    @State private var serial = 0

    /// The window's width, measured from the canvas, so that a caption inside
    /// the drawing wraps at it rather than running off it at the largest
    /// text sizes.
    @State private var windowWidth: CGFloat = 0

    /// The person whose sheet is up, and what was asked of it. Acted on once
    /// the sheet has gone, so a card or a second sheet never arrives under one
    /// still on its way down.
    @State private var chosen: Subject?
    /// Shut while two fingers are on the drawing, so that a card's press
    /// that ran through a pinch is not a tap (`TreePinch`).
    @State private var gate = TreeGate()
    @State private var pendingOpen: Subject?
    @State private var pendingRelative: RelativeRequest?
    @State private var relative: RelativeRequest?

    /// The menu, and the door chosen in it, opened once it has gone down for
    /// the same reason.
    @State private var menu = false
    @State private var pendingDoor: TreeDoor?

    /// One place and one generation, growing with the text inside them, so a
    /// name at a larger size does not run into its neighbour. A generation is
    /// taller than it was with the rail (156): every card carries a word now,
    /// and the bar from parents to children runs under the word, not through
    /// it — `TreeGeometry` says where.
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 168
    /// The same base size and text style `SubjectAvatar` scales by, so the
    /// lines can find the middle of each disc at every text size.
    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 48
    /// A caption's own band: over the friends, over the people related to
    /// nobody, and over a family that shares nobody with yours.
    @ScaledMetric(relativeTo: .headline) private var captionBand: CGFloat = 44
    /// One line of a name under a disc, 21 points of `.body` at the default
    /// text size, and one line of the word under it in the footnote face.
    @ScaledMetric(relativeTo: .body) private var nameLine: CGFloat = 21
    @ScaledMetric(relativeTo: .footnote) private var wordLine: CGFloat = 18

    /// From the top of a generation's row to the top of its discs.
    private static let rowInset: CGFloat = 8

    private static let zoomRange: ClosedRange<CGFloat> = 0.4 ... 2.5

    /// Under this the names and words are not drawn, only the discs. A body
    /// name at 0.65 is 11 points, which is the smallest anybody reads; below
    /// it a name is ink in the shape of a word, and the picture reads better
    /// without it — the same threshold the study map in Opinnot uses to
    /// drop its labels.
    static let detail: CGFloat = 0.65

    /// The card this phone's member is in the tree, followed through a merge,
    /// or nil while the family's server links them to none (`Session.linkMe`).
    private var yourCardID: String? {
        guard let id = session.family?.you.personSubjectID else { return nil }
        return store.subject(id: id)?.id
    }

    /// Oldest card first, so the same family always grows from the same person.
    private var people: [Subject] {
        store.subjects(of: .person)
            .filter(\.confirmed)
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let people = people
        let you = yourCardID
        let ids = people.map(\.id)
        let live = liveRelations(among: ids)
        // The words first: how deep a card reaches depends on whether it has
        // one, and the layout is told how deep every card is.
        let words = you.map { Kinship.words(from: $0, people: ids, ties: Self.ties(live)) } ?? [:]
        // How deep a card reaches below the row's centre line, in rows, so
        // that a line leaving somebody downwards starts under their words:
        // half the disc, the gap, the name, the word when there is one, and
        // two fifths of a line more for the descenders and some air. Measured
        // on the simulator before the rail went, the letters of a name reach
        // 52.7 points below the disc's centre at the default size, and a
        // line started at the arithmetic's 51 sat on the baseline.
        let plain = (discSize / 2 + 6 + nameLine + nameLine * 0.4) / rowHeight
        let worded = (discSize / 2 + 6 + nameLine + 4 + wordLine + nameLine * 0.4) / rowHeight
        let result = FamilyTreeLayout.layout(
            people: ids,
            links: Self.links(live),
            friends: Self.friends(live),
            root: you
        ) { id in Double(id == you || words[id] != nil ? worded : plain) }
        let geometry = TreeGeometry(
            result: result,
            columnWidth: columnWidth,
            rowHeight: rowHeight,
            discSize: discSize,
            captionBand: captionBand,
            rowInset: Self.rowInset
        )
        let key = DrawingKey(result: result, people: people, you: you, words: words, wrap: windowWidth)
        let yours = you.flatMap { result.places[$0] }.map { geometry.disc(of: $0) }
        // Where the drawing opens when the family does not fit the window:
        // your own disc — or, on a phone linked to no card, the first card
        // of the oldest row, at the same place. The drawing's own top left
        // corner is not that card: the rows below it are wider, so the
        // oldest generation stands over the middle of its descendants, and
        // at the largest text size `-seed clan` opened on nothing but paper
        // until 27 Sep 2026. Rows before x, so that a family of people
        // related to nobody opens on its own first card as well.
        let opening = yours ?? result.places.values
            .min { ($0.row, $0.x) < ($1.row, $1.x) }
            .map { geometry.disc(of: $0) }

        VStack(spacing: 0) {
            // Inside both bars. Not under the top bar, because the status
            // bar fades whatever scrolls beneath it and the audit reads the
            // fade as the name's own colour; and since 25 Sep 2026 not under
            // the tab bar either, the way a map would be, because the bar is
            // glass and the fade above it a gradient, and a name under either
            // at the largest text size is more colours than the audit's
            // contrast check counts in the fifteen seconds it has (the note
            // at `controls(yours:)`). At the default size the same names
            // were eight forgiven findings on every run, each costing the
            // sweep a dozen element reads.
            TreeCanvas(
                size: geometry.size,
                range: Self.zoomRange,
                opening: opening,
                key: key,
                command: command,
                gate: gate
            ) { scale in
                TreeDrawing(
                    result: result,
                    people: people,
                    you: you,
                    words: words,
                    geometry: geometry,
                    wrap: windowWidth,
                    detailed: scale >= Self.detail,
                    // A disc alone is 19 points at the smallest zoom, and a
                    // tap target is 44 whatever the zoom: the place's frame
                    // is stretched to make up the difference, before the
                    // scale takes it back down.
                    tapHeight: Elder.minTapTarget / scale
                ) { person, point in
                    guard !gate.pinching else { return }
                    fire(.focus(point, atLeast: 1), animated: true)
                    chosen = person
                }
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: geometry.size.width * scale,
                    height: geometry.size.height * scale,
                    alignment: .topLeading
                )
                // The drawing is hosted by UIKit and inherits nothing from
                // this view's environment on its own.
                .environment(store)
                .environment(session)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                windowWidth = width
            }

            // In a band of their own under the drawing since 27 Sep 2026,
            // and not in its corner. They floated over the canvas until
            // then, their height taken off the window the opening was
            // fitted to, so that nothing was under them when the picture
            // opened — and the next row down scrolled straight under them:
            // at the largest text size *Whole family* covered the disc of
            // the card below the one opened on (`LayoutAtSizeTests`). A row
            // of its own can cover nothing. It also takes the buttons out of
            // the canvas's frame altogether, which is where XCUITest's
            // zoom-out pinch puts its fingers — seven points in and nine
            // down from the corners of the frame inset 50 from each side —
            // and a button under a finger made the scroll view pan where it
            // should have zoomed (25 Sep 2026,
            // `testTheTreeZoomsUnderTwoFingersAndKeepsItsPeople`).
            band(yours: yours)
        }
        .toolbar {
            // The one control on the screen that is not the drawing. A menu's
            // rows barely grow with the text size and no UI test here has
            // been able to open one, so what it opens is a sheet of plain
            // buttons rather than a `Menu`.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    menu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .elderTapTarget()
                        .overlay(alignment: .topTrailing) {
                            // A mark while names wait behind the door, so
                            // that putting the door in a menu does not put
                            // the names out of mind. Hidden from the
                            // accessibility tree: VoiceOver never gets this
                            // screen, and the door inside says the count.
                            if heardCount > 0 {
                                Circle()
                                    .fill(Elder.proposal)
                                    .frame(width: 10, height: 10)
                                    .offset(x: -12, y: 12)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .accessibilityLabel("Valikko")
            }
        }
        .sheet(isPresented: $menu, onDismiss: afterMenu) {
            TreeMenuSheet(
                heardCount: heardCount,
                undrawn: result.undrawn.map { link in
                    UndrawnBond(
                        from: name(link.from, in: people),
                        to: name(link.to, in: people),
                        bond: Self.bond(link.bond)
                    )
                },
                choose: { door in
                    pendingDoor = door
                    menu = false
                }
            )
        }
        .sheet(item: $chosen, onDismiss: afterPersonSheet) { person in
            TreePersonSheet(
                person: person,
                word: person.id == you ? String(localized: "Sinä") : words[person.id]?.label,
                memories: store.memories(for: person.id).count,
                open: {
                    pendingOpen = person
                    chosen = nil
                },
                add: { kind, asChild in
                    pendingRelative = RelativeRequest(person: person, kind: kind, asChild: asChild)
                    chosen = nil
                }
            )
            // The window's full height, and no medium detent, though half a
            // window would have left the card just flown to in view over
            // its own sheet. iOS 26 lays a half-height sheet's content out
            // at the window's width and draws it at the sheet's — 402 laid
            // out, 386 drawn, every frame a multiple of a 67th — so every
            // line in it is 4 % smaller than the size the reader asked for,
            // and the audit reported each one clipped at both text sizes.
            // Measured 25 Sep 2026, twice alone on a private simulator, and
            // clean the moment the detent went.
        }
        .sheet(item: $relative) { request in
            RelationPicker(subject: request.person, kind: request.kind, asChild: request.asChild) {
                relative = nil
            }
        }
        .background(Elder.paper)
    }

    private func afterPersonSheet() {
        if let person = pendingOpen {
            pendingOpen = nil
            onOpen(person)
        } else if let request = pendingRelative {
            pendingRelative = nil
            relative = request
        }
    }

    private func afterMenu() {
        guard let door = pendingDoor else { return }
        pendingDoor = nil
        switch door {
        case .list: onList()
        case .addPerson: onAddPerson()
        case .heard: onHeard()
        case .settings: onSettings()
        }
    }

    private func fire(_ move: TreeMove, animated: Bool) {
        serial += 1
        command = TreeCommand(serial: serial, move: move, animated: animated)
    }

    /// The two buttons for a hand that cannot pinch, and for anybody: the
    /// whole family in the window, and your own card at its natural size.
    /// Words rather than magnifiers, because each does one thing that can
    /// be named — and *Sinä* is the same word as under your card, and takes
    /// the reader to the same place.
    private func controls(yours: CGPoint?) -> some View {
        // Side by side at the reading sizes, and one under the other at the
        // band's full width at the accessibility sizes, the way `ChipRow`
        // stacks its chips: at the largest text size two on one line were
        // each a column of broken words. Chosen by the text size and not by
        // `ViewThatFits`, which picked the same two layouts by measuring and
        // was reported by the audit's default-size simulation on every run —
        // *Koko suku* partially unsupported, 121 by 84 points, wherever the
        // band stood — while main's plain row in the same band was not
        // (27 Sep 2026, alone, minutes apart).
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    buttons(yours: yours, wide: true)
                }
            } else {
                HStack(spacing: 12) {
                    buttons(yours: yours, wide: false)
                }
            }
        }
        // Honey with a hairline (`elderSecondary`), and not the system's
        // bordered style, which is glass on iOS 26. Glass refracts whatever
        // is under it into a gradient, and the audit's contrast check reads
        // a text element's pixels into a set of colours one by one — sampled
        // 25 Sep 2026 in testmanagerd: `-[AXAuditContrastDetectionManager
        // _topColorsForImageData:optimized:]` walking `-[UIDeviceRGBColor
        // isEqual:]` chains. Two labels of glass at the largest text size
        // were more colours than its fifteen seconds hold, the check gave
        // up with "Audit failed to complete in time" on every run, and every
        // audit that gave up left its thread running: twenty of them had
        // testmanagerd at 800 % of a core by the end of the evening, twice.
        .buttonStyle(.elderSecondary)
    }

    @ViewBuilder
    private func buttons(yours: CGPoint?, wide: Bool) -> some View {
        Button {
            fire(.fit, animated: true)
        } label: {
            Text("Koko suku")
                .font(.body.weight(.medium))
                .frame(maxWidth: wide ? .infinity : nil)
                .elderTapTarget()
        }
        if let yours {
            Button {
                fire(.home(yours), animated: true)
            } label: {
                Text("Sinä")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: wide ? .infinity : nil)
                    .elderTapTarget()
            }
        }
    }

    /// The band the buttons stand in, under the drawing: the paper, a
    /// hairline above, and the buttons centred in it.
    private func band(yours: CGPoint?) -> some View {
        controls(yours: yours)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Elder.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Elder.rule)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
    }

    // MARK: - From the archive to the engines

    /// Confirmed and not deleted, between people in the picture.
    private func liveRelations(among ids: [String]) -> [Relation] {
        let known = Set(ids)
        return store.relations.filter { relation in
            relation.confirmed && relation.deletedAt == nil
                && known.contains(relation.fromSubjectID) && known.contains(relation.toSubjectID)
        }
    }

    /// A friendship is not a line in a family tree (§21: a friend is not
    /// suku), and the layout is never handed one — as a link it would be
    /// placed as a sibling.
    private static func links(_ relations: [Relation]) -> [FamilyTreeLayout.Link] {
        relations.compactMap { relation in
            let bond: FamilyTreeLayout.Bond
            switch relation.kind {
            case .parentOf: bond = .parent
            case .spouseOf: bond = .spouse
            case .siblingOf: bond = .sibling
            case .friendOf: return nil
            }
            return FamilyTreeLayout.Link(from: relation.fromSubjectID, to: relation.toSubjectID, bond: bond)
        }
    }

    /// Who is joined to the family by friendship, each once. The layout
    /// draws them apart under it, and places anybody among them who is also
    /// somebody's kin by the kinship instead.
    private static func friends(_ relations: [Relation]) -> [String] {
        var seen = Set<String>()
        return relations.filter { $0.kind == .friendOf }
            .flatMap { [$0.fromSubjectID, $0.toSubjectID] }
            .filter { seen.insert($0).inserted }
    }

    /// What the words are read from: everything live, except a parent bond
    /// entered the other way round after its reverse. The layout keeps the
    /// earlier of two bonds that contradict each other and names the later
    /// in `undrawn`, and the words have to follow the drawing: handed both,
    /// Sulo's phone read Onni — drawn as his child — as *Vanhempasi*,
    /// because the engine takes its ties as given and matches upward before
    /// downward. A wrong word on a card is rule 4's failure whichever
    /// engine made it. `-seed clan` has the pair;
    /// `testAContradictedBondReadsTheWayItIsDrawn` reads it from his phone.
    private static func ties(_ relations: [Relation]) -> [Kinship.Tie] {
        var children: [String: Set<String>] = [:]
        return relations.compactMap { relation in
            let bond: Kinship.Bond
            switch relation.kind {
            case .parentOf:
                if children[relation.toSubjectID]?.contains(relation.fromSubjectID) == true { return nil }
                children[relation.fromSubjectID, default: []].insert(relation.toSubjectID)
                bond = .parent
            case .spouseOf: bond = .spouse
            case .siblingOf: bond = .sibling
            case .friendOf: bond = .friend
            }
            return Kinship.Tie(from: relation.fromSubjectID, to: relation.toSubjectID, bond: bond)
        }
    }

    private func name(_ id: String, in people: [Subject]) -> String {
        people.first { $0.id == id }?.displayTitle ?? ""
    }

    /// The bond as the menu names it, when the rows could not hold it. In
    /// the plural or as a pair, the way the cards' own sections are titled.
    private static func bond(_ bond: FamilyTreeLayout.Bond) -> String {
        switch bond {
        case .spouse: String(localized: "aviopuolisot")
        case .parent: String(localized: "vanhempi ja lapsi")
        case .sibling: String(localized: "sisarukset")
        }
    }
}

// MARK: - The drawing

/// Layout units to points: where every row begins, and where a disc's
/// middle is. A place is `columnWidth` wide and a generation `rowHeight`
/// tall; a caption's row is `captionBand` tall instead, because a
/// generation's height over one line of text is a hole — 134 points of
/// nothing at the default size, measured before there were captions at all.
private struct TreeGeometry: Equatable {
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let discSize: CGFloat
    let captionBand: CGFloat
    let rowInset: CGFloat
    /// The top of each row, and one more for the bottom of the last.
    let tops: [CGFloat]
    /// A caption's band over the families, when there is more than one:
    /// *Toinen perhe* over every family but the first.
    let familyBand: CGFloat
    let size: CGSize

    init(
        result: FamilyTreeLayout.Result,
        columnWidth: CGFloat,
        rowHeight: CGFloat,
        discSize: CGFloat,
        captionBand: CGFloat,
        rowInset: CGFloat
    ) {
        self.columnWidth = columnWidth
        self.rowHeight = rowHeight
        self.discSize = discSize
        self.captionBand = captionBand
        self.rowInset = rowInset
        familyBand = result.families.count > 1 ? captionBand : 0
        // Siblings nobody has entered parents for hang from a bar 0.4 rows
        // above their own, and on the first row that is above the drawing.
        // Room for it, and only when it is drawn.
        let overhang = result.lines.contains { min($0.y1, $0.y2) < 0 }
            ? max(0, 0.4 * rowHeight - discSize / 2 - rowInset + 6)
            : 0
        var tops = [familyBand + overhang]
        for row in 0 ..< result.rows {
            tops.append(tops[row] + (result.captionRows.contains(row) ? captionBand : rowHeight))
        }
        self.tops = tops
        size = CGSize(
            width: max(CGFloat(result.width), 1) * columnWidth,
            height: max(tops[result.rows], rowHeight)
        )
    }

    func x(_ x: Double) -> CGFloat {
        (CGFloat(x) + 0.5) * columnWidth
    }

    /// A whole row lands on the middle of that generation's discs; a
    /// fraction of one, where a bar runs, lands that far towards the next.
    /// Lines never enter a caption's row, so the fraction is always of a
    /// generation's height.
    func y(_ y: Double) -> CGFloat {
        let row = min(max(Int(y.rounded(.down)), 0), max(tops.count - 2, 0))
        return tops[row] + rowInset + discSize / 2 + (CGFloat(y) - CGFloat(row)) * rowHeight
    }

    func top(ofRow row: Int) -> CGFloat {
        tops[min(max(row, 0), tops.count - 1)]
    }

    func disc(of place: FamilyTreeLayout.Place) -> CGPoint {
        CGPoint(x: x(place.x), y: top(ofRow: place.row) + rowInset + discSize / 2)
    }
}

/// The family, at scale 1: the bands, the lines, the captions and the people.
/// Everything in it moves and scales with it; nothing on the screen is
/// pinned over it.
private struct TreeDrawing: View {
    let result: FamilyTreeLayout.Result
    let people: [Subject]
    let you: String?
    let words: [String: Kinship.Word]
    let geometry: TreeGeometry
    /// The window's width, or zero before it is known: how wide a caption
    /// may be before it wraps.
    let wrap: CGFloat
    /// Names and words, or discs alone.
    let detailed: Bool
    /// The least a place may be tall, in the drawing's own points, so that
    /// it is still a tap target once the scale has shrunk it.
    let tapHeight: CGFloat
    let onTap: (Subject, CGPoint) -> Void

    /// A name wraps inside this, and the gap to the next place stays clear.
    private var nodeWidth: CGFloat { geometry.columnWidth - 20 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bands
            lines
            captions
            ForEach(people) { person in
                if let place = result.places[person.id] {
                    // By its top, not its centre: a name that wraps to two
                    // lines must not lift its disc off the line it hangs on.
                    node(person, isYou: person.id == you)
                        .offset(
                            x: geometry.x(place.x) - (detailed ? nodeWidth : geometry.columnWidth) / 2,
                            y: geometry.top(ofRow: place.row) + geometry.rowInset
                        )
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }

    /// A band to a generation, every other one, so a row reads as one row
    /// across a family too wide to see at once. Per family, since each
    /// starts at row 0 and knows nothing of the others' age; in yours,
    /// counted from your own row, so it is always one of the shaded ones.
    ///
    /// `Elder.card` on `Elder.paper` measures 1.11:1 — a tint and not an
    /// edge, which is what this is for. What matters under rule 1 is what
    /// the names measure against it, and primary text on card is 16.81:1
    /// against 15.17:1 on paper: both sides of the stripe are comfortably
    /// over the minimum, so no name gets harder to read for being in a
    /// shaded generation.
    private var bands: some View {
        let yourRow = you.flatMap { result.places[$0]?.row }
        return ForEach(Array(result.families.enumerated()), id: \.offset) { index, family in
            let origin = index == 0 && you.map(family.members.contains) == true ? (yourRow ?? 0) : 0
            ForEach(0 ..< family.rows, id: \.self) { row in
                if (row - origin).isMultiple(of: 2) {
                    Rectangle()
                        .fill(Elder.card)
                        .frame(
                            width: CGFloat(family.maxX - family.minX + 1) * geometry.columnWidth,
                            height: geometry.top(ofRow: row + 1) - geometry.top(ofRow: row)
                        )
                        .offset(x: CGFloat(family.minX) * geometry.columnWidth, y: geometry.top(ofRow: row))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Under the people, and through the middle of their discs: every disc
    /// has a paper backing, so a line meets it edge to edge. A couple's line
    /// runs at that height, above every name, and a line that leaves a
    /// person downwards starts under their words — the layout is told how
    /// deep a card is — so nothing runs through one.
    private var lines: some View {
        Canvas { context, _ in
            for line in result.lines {
                let from = CGPoint(x: geometry.x(line.x1), y: geometry.y(line.y1))
                let to = CGPoint(x: geometry.x(line.x2), y: geometry.y(line.y2))
                // A couple is two lines, the way a genealogy draws a
                // marriage — the one line on this canvas that joins equals
                // rather than a generation to the next, and the only way to
                // tell it from a sibling bar at a glance. The pair is drawn
                // across the line and each part reaches a little past its
                // ends, so a marriage that dips under the row to get round
                // whoever stands between reads as a marriage all the way
                // round: square corners would gape.
                let couple = line.stroke == .couple
                let run = CGPoint(x: to.x - from.x, y: to.y - from.y)
                let length = max((run.x * run.x + run.y * run.y).squareRoot(), 0.001)
                let along = CGPoint(x: run.x / length, y: run.y / length)
                let reach: CGFloat = couple ? 2.5 : 0
                for shift in (couple ? [-2.5, 2.5] : [0]) as [CGFloat] {
                    let across = CGPoint(x: -along.y * shift, y: along.x * shift)
                    var path = Path()
                    path.move(to: CGPoint(x: from.x + across.x - along.x * reach,
                                          y: from.y + across.y - along.y * reach))
                    path.addLine(to: CGPoint(x: to.x + across.x + along.x * reach,
                                             y: to.y + across.y + along.y * reach))
                    context.stroke(path, with: .color(Elder.supporting), lineWidth: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The three captions, each in its own band inside the drawing: over a
    /// family that shares nobody with the first, over the friends, and over
    /// the people related to nobody. In the drawing rather than on the
    /// window, so they scroll and shrink with what they are about — and go
    /// with the names below `detail`, where a headline is seven points.
    /// Wrapped at the window's width all the same: a name stops at its
    /// place's edge and a caption has no edge to stop at, so *Ei vielä
    /// sukupuussa* at the largest text size ran 461 points across a window
    /// of 402, and the audit reported it clipped (25 Sep 2026).
    @ViewBuilder
    private var captions: some View {
        if detailed {
            ForEach(Array(result.families.enumerated().dropFirst()), id: \.offset) { _, family in
                // Drawn beside it and starting at row 0 like every family,
                // which is no claim about its age — so nothing here counts
                // its rows from yours, and the caption says why the words
                // stop at its edge.
                caption(Text("Toinen perhe"), x: CGFloat(family.minX) * geometry.columnWidth, top: 0, alignment: .topLeading)
            }
            if let row = result.friendsRow {
                caption(Text("Ystävät"), x: 0, top: geometry.top(ofRow: row - 1), alignment: .bottomLeading)
            }
            if let row = result.looseRow {
                caption(Text("Ei vielä sukupuussa"), x: 0, top: geometry.top(ofRow: row - 1), alignment: .bottomLeading)
            }
        }
    }

    private func caption(_ text: Text, x: CGFloat, top: CGFloat, alignment: Alignment) -> some View {
        // The room a caption has: the window's width once it is known and
        // the drawing's until then, from the caption's own left edge, less
        // its offset and the same air on the right.
        let room = (wrap > 0 ? min(wrap, geometry.size.width - x) : geometry.size.width - x) - 16
        return text
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Elder.paper, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: max(room, 44), alignment: .leading)
            .frame(height: geometry.captionBand, alignment: alignment)
            .offset(x: x + 8, y: top)
    }

    private func node(_ person: Subject, isYou: Bool) -> some View {
        Button {
            onTap(person, geometry.disc(of: result.places[person.id] ?? FamilyTreeLayout.Place(row: 0, x: 0)))
        } label: {
            VStack(spacing: 6) {
                SubjectAvatar(subject: person, size: 48)
                    // A paper disc under the ink one. `SubjectAvatar` fills
                    // with ink at 75 %, so a line behind it ran straight
                    // through the letter. The avatar draws its disc from its
                    // top-leading corner, so the backing sits there too, at
                    // the disc's own size.
                    .background(alignment: .topLeading) {
                        Circle()
                            .fill(Elder.paper)
                            .frame(width: geometry.discSize, height: geometry.discSize)
                    }
                if detailed {
                    Text(person.displayTitle)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    // What this person is to whoever holds the phone, in one
                    // word — and *Sinä* on your own card, a word rather than
                    // a colour, so it does not rest on colour alone (rule 1).
                    // Nothing when the word would not be exact.
                    if isYou {
                        word(Text("Sinä"))
                    } else if let word = words[person.id] {
                        self.word(Text(word.label))
                    }
                }
            }
            // No card behind the name. A card hid the line between a couple,
            // leaving a dash floating between two names.
            .frame(width: detailed ? nodeWidth : geometry.columnWidth, alignment: .top)
            .frame(minHeight: detailed ? 0 : tapHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isYou ? Text("\(person.displayTitle), sinä") : Text(person.displayTitle))
    }

    private func word(_ text: Text) -> some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Elder.supporting)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -2)
    }
}

/// What the canvas is drawn from. When any of it changes the drawing is laid
/// out again; the reader's own moves do not touch it.
private struct DrawingKey: Equatable {
    var result: FamilyTreeLayout.Result
    var people: [Subject]
    var you: String?
    var words: [String: Kinship.Word]
    /// The window's width the captions wrap at; a window of a new width is
    /// a new drawing, so a caption wrapped for the old one is not kept.
    var wrap: CGFloat
}

// MARK: - The map

/// Something asked of the map, in the drawing's own points at scale 1.
private enum TreeMove: Equatable {
    /// The whole family in the window, at whatever scale fits it, never
    /// larger than natural.
    case fit
    /// This point into the upper part of the window, at the natural scale
    /// if the map was smaller, and at its own if it was larger.
    case focus(CGPoint, atLeast: CGFloat)
    /// This point into the upper part of the window at the natural scale
    /// exactly: where the *Sinä* button takes the reader.
    case home(CGPoint)
}

private struct TreeCommand: Equatable {
    let serial: Int
    let move: TreeMove
    let animated: Bool
}

/// The scroll view the drawing lives in — a map's: both directions under one
/// finger with the momentum a map has, and a pinch about the fingers.
///
/// The pinch is `TreePinch`, a recognizer of our own on the scroll view
/// that drives the scroll view's zoom: it transforms the drawing while the
/// fingers are down, which is smooth and slightly soft, and when they lift
/// the transform is made permanent: the drawing is laid out again at the new
/// size, sharp, with the same part of the family under the window
/// (`Coordinator.settleZoom`). The shape before this one laid the drawing
/// out on every change of a custom pinch instead, at a cost nobody measured.
private struct TreeCanvas<Content: View>: UIViewRepresentable {
    /// The drawing's own size at scale 1.
    let size: CGSize
    let range: ClosedRange<CGFloat>
    /// Where the drawing opens when the whole family does not fit at a
    /// readable size: your own disc when this phone's card is in the tree,
    /// and the first card of the oldest row when it is not. Nil only when
    /// there is nobody to open on.
    let opening: CGPoint?
    let key: DrawingKey
    let command: TreeCommand?
    let gate: TreeGate
    @ViewBuilder let content: (CGFloat) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TreeScrollView {
        let scrollView = TreeScrollView()
        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        scrollView.delegate = coordinator
        coordinator.gate = gate
        coordinator.pinchTarget.handle = { [weak coordinator] in coordinator?.pinched($0) }
        scrollView.addGestureRecognizer(
            TreePinch(target: coordinator.pinchTarget, action: #selector(PinchTarget.pinched(_:)))
        )
        // The bars' insets are the scroll view's business, below, and not
        // UIKit's: with the adjustment on, a drawing under a tab bar opened
        // with its first row under the top bar's inset as well.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let host = UIHostingController(rootView: AnyView(content(1)))
        host.view.backgroundColor = .clear
        // The window's bars are the scroll view's business, above; the
        // drawing is laid out edge to edge in its own frame.
        host.safeAreaRegions = []
        scrollView.addSubview(host.view)
        coordinator.host = host
        scrollView.onLayout = { [weak coordinator] in coordinator?.settle() }
        scrollView.onSafeArea = { [weak coordinator] in coordinator?.settle() }
        return scrollView
    }

    func updateUIView(_ scrollView: TreeScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.content = { AnyView(content($0)) }
        coordinator.range = range
        coordinator.opening = opening

        var changed = false
        if coordinator.size != size || coordinator.key != key {
            coordinator.size = size
            coordinator.key = key
            coordinator.render()
            changed = true
        }
        // A drawing of a new size under the old offset shows some other part
        // of the family, and a smaller one is clamped by the scroll view to
        // an offset the old size never asked for: the accessibility audit
        // steps the text size through twelve categories and back. So the
        // opening is applied again for a new size as it is for a new inset,
        // for as long as the reader has not moved the picture.
        if changed {
            coordinator.settle()
        }
        if let command, command.serial != coordinator.served {
            coordinator.served = command.serial
            coordinator.perform(command)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: TreeScrollView?
        var host: UIHostingController<AnyView>?
        var content: ((CGFloat) -> AnyView)?
        var range: ClosedRange<CGFloat> = 0.4 ... 2.5
        var opening: CGPoint?
        var size: CGSize = .zero
        var key: DrawingKey?
        var served = 0
        var gate: TreeGate?
        let pinchTarget = PinchTarget()
        /// The zoom when the fingers came down, and the point of the drawing
        /// that was under them then, in the drawing's own coordinates.
        private var pinchFrom: CGFloat = 1
        private var pinchAnchor: CGPoint = .zero

        /// The scale the drawing is laid out at.
        private(set) var scale: CGFloat = 1
        /// True once the reader has dragged, pinched or pressed a button:
        /// from then on the picture is where they put it, and the opening
        /// is not applied again.
        private var moved = false
        private var settling = false

        /// Where your own card is put when the drawing opens on it or flies
        /// to somebody: the window's middle across, and a little under a
        /// third of the way down — your parents above you and your children
        /// below, in the same window as yourself, and the card clear of the
        /// buttons in the corner. Computed, because the coordinator is nested
        /// in a generic type and a stored static is not allowed there.
        private static var focus: CGPoint { CGPoint(x: 0.5, y: 0.3) }

        private var bars: UIEdgeInsets { scrollView?.safeAreaInsets ?? .zero }

        /// The part of the scroll view's frame not under a bar, in its own
        /// frame's coordinates. The buttons are outside the frame (`band`).
        private var window: CGRect {
            guard let scrollView else { return .zero }
            let bounds = scrollView.bounds
            return CGRect(
                x: bars.left,
                y: bars.top,
                width: max(0, bounds.width - bars.left - bars.right),
                height: max(0, bounds.height - bars.top - bars.bottom)
            )
        }

        /// The scale at which the whole drawing is inside the window.
        private var fit: CGFloat {
            let window = window
            guard window.width > 0, window.height > 0, size.width > 0, size.height > 0 else { return 1 }
            return min(window.width / size.width, window.height / size.height)
        }

        /// The drawing laid out at `scale`.
        func render() {
            guard let host, let scrollView, let content else { return }
            host.rootView = content(scale)
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            host.view.frame = CGRect(origin: .zero, size: drawn)
            scrollView.contentSize = drawn
            // The pinch works on top of the layout's own scale, so its
            // limits are the range less what the layout already holds.
            scrollView.minimumZoomScale = range.lowerBound / scale
            scrollView.maximumZoomScale = range.upperBound / scale
            // The scroll view's own pinch would zoom as well on the rare
            // touch that begins beside the drawing rather than on it, and
            // one pinch is enough (`TreePinch`).
            scrollView.pinchGestureRecognizer?.isEnabled = false
        }

        /// The bars' insets and the air that centres a drawing smaller than
        /// the window.
        private func applyInsets() {
            guard let scrollView else { return }
            let window = window
            let drawn = scrollView.contentSize
            let spareX = max(0, (window.width - drawn.width) / 2)
            let spareY = max(0, (window.height - drawn.height) / 2)
            let inset = UIEdgeInsets(
                top: bars.top + spareY,
                left: bars.left + spareX,
                bottom: bars.bottom + spareY,
                right: bars.right + spareX
            )
            if scrollView.contentInset != inset {
                scrollView.contentInset = inset
            }
        }

        private func clamp(_ offset: CGPoint) -> CGPoint {
            guard let scrollView else { return offset }
            let inset = scrollView.contentInset
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
            let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
            return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
        }

        /// The offset that puts a point of the drawing at a fraction of the
        /// window, as far as the drawing's edges allow.
        private func offset(showing point: CGPoint, at fraction: CGPoint) -> CGPoint {
            let window = window
            return clamp(CGPoint(
                x: point.x * scale - (window.minX + fraction.x * window.width),
                y: point.y * scale - (window.minY + fraction.y * window.height)
            ))
        }

        private var start: CGPoint {
            guard let scrollView else { return .zero }
            return CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        }

        private func set(scale new: CGFloat) {
            let clamped = min(max(new, range.lowerBound), range.upperBound)
            guard clamped != scale else { return }
            scale = clamped
            render()
        }

        /// The window has a size, or a new one, or new insets: the drawing
        /// is centred in it if it is smaller, opened in it if the reader
        /// has not moved it yet, and kept inside it otherwise.
        func settle() {
            guard let scrollView, !settling, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            settling = true
            defer { settling = false }
            applyInsets()
            if moved {
                scrollView.contentOffset = clamp(scrollView.contentOffset)
            } else {
                open()
            }
        }

        /// Where the picture begins: at its natural size, centred when the
        /// whole family fits the window; on your own card when it does not;
        /// and on the first card of the oldest row, at the same place, on a
        /// phone linked to no card — at its own top left corner, like any
        /// picture, until 27 Sep 2026, and the oldest row's first card is
        /// not there (`opening`, in the view above).
        ///
        /// Never smaller than natural, not even for a family that would fit
        /// whole at 0.9×. The reader may shrink this drawing and the app may
        /// not do it for them: the rule of 19 Sep 2026, and the audit is what
        /// measures it. Its default-size run steps the text through twelve
        /// sizes, and an opening that fitted a family — this one did, down to
        /// `detail` — shrank the drawing at the sizes where the family nearly
        /// fit, and the audit reported every name on the screen clipped,
        /// twice alone on 25 Sep 2026. *Koko suku* is the same fit, and the
        /// reader's to press.
        private func open() {
            guard let scrollView else { return }
            set(scale: 1)
            applyInsets()
            if let opening, fit < 1 {
                scrollView.contentOffset = offset(showing: opening, at: Self.focus)
            } else {
                scrollView.contentOffset = clamp(start)
            }
        }

        func perform(_ command: TreeCommand) {
            guard let scrollView, scrollView.bounds.width > 0 else { return }
            moved = true
            let target: CGPoint
            switch command.move {
            case .fit:
                set(scale: min(fit, 1))
                applyInsets()
                target = clamp(start)
            case let .focus(point, atLeast):
                set(scale: max(scale, atLeast))
                applyInsets()
                target = offset(showing: point, at: Self.focus)
            case let .home(point):
                set(scale: 1)
                applyInsets()
                target = offset(showing: point, at: Self.focus)
            }
            // The map's flight: 420 milliseconds, the study map's, and none
            // at all for a reader who has asked the phone for less motion.
            if command.animated, !UIAccessibility.isReduceMotionEnabled {
                UIView.animate(withDuration: 0.42, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    scrollView.contentOffset = target
                }
            } else {
                scrollView.contentOffset = target
            }
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            moved = true
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            moved = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // A drawing pinched smaller than the window stays centred in it.
            applyInsets()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale zoomed: CGFloat) {
            settleZoom()
        }

        /// The two fingers, from `TreePinch`: the scroll view's zoom driven
        /// about the point that was under them, and made permanent when they
        /// lift.
        func pinched(_ pinch: UIPinchGestureRecognizer) {
            guard let scrollView, let host else { return }
            switch pinch.state {
            case .began:
                moved = true
                gate?.pinching = true
                pinchFrom = scrollView.zoomScale
                pinchAnchor = pinch.location(in: host.view)
            case .changed:
                guard pinch.numberOfTouches == 2 else { return }
                let zoom = min(max(pinchFrom * pinch.scale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
                // Where the fingers are in the window, and where the point
                // that was under them has gone at the new zoom: the offset
                // that puts it back under them.
                let fingers = pinch.location(in: scrollView)
                let inWindow = CGPoint(x: fingers.x - scrollView.contentOffset.x, y: fingers.y - scrollView.contentOffset.y)
                scrollView.zoomScale = zoom
                let anchor = host.view.convert(pinchAnchor, to: scrollView)
                scrollView.contentOffset = clamp(CGPoint(x: anchor.x - inWindow.x, y: anchor.y - inWindow.y))
            case .ended, .cancelled, .failed:
                settleZoom()
                // The cards' presses complete as the fingers lift, in an
                // order UIKit does not promise, so the gate stays shut a
                // moment longer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.gate?.pinching = false
                }
            default:
                break
            }
        }

        /// The transform the fingers left, made permanent: laid out again at
        /// the new size, with the same part of the family under the window.
        /// The offset is in the zoomed content's own coordinates already,
        /// which are the new layout's, so it is kept across the change.
        private func settleZoom() {
            guard let scrollView, !settling else { return }
            settling = true
            defer { settling = false }
            let zoomed = scrollView.zoomScale
            let offset = scrollView.contentOffset
            scrollView.zoomScale = 1
            set(scale: scale * zoomed)
            applyInsets()
            scrollView.contentOffset = clamp(offset)
        }
    }
}

/// Shut while two fingers are on the drawing. SwiftUI's presses on the cards
/// run on through a pinch and complete when the fingers lift, so the
/// coordinator says when it is pinching and the card's action asks.
private final class TreeGate {
    var pinching = false
}

/// The two-finger zoom, as a recognizer of the scroll view's own kind that
/// cannot be prevented. UIScrollView brings one, and it never fires here:
/// the drawing is SwiftUI, and SwiftUI's responder recognizer on the hosted
/// view recognises on the first touch and prevents every other recognizer
/// in the chain, the scroll view's pinch among them. Measured 25 Sep 2026:
/// that pinch held two touches at the first event and none from the first
/// move, and a pinch that had begun on two cards ended as two taps, a
/// sheet and no zoom. This one refuses to be prevented and drives the
/// scroll view's zoom the way its own would have (`Coordinator.pinched`);
/// the presses it ran through still complete, which is what `TreeGate`
/// is for.
private final class TreePinch: UIPinchGestureRecognizer {
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// `TreePinch`'s target: a class of its own, because the coordinator is
/// nested in a generic type, where an `@objc` method is not allowed.
private final class PinchTarget: NSObject {
    var handle: ((UIPinchGestureRecognizer) -> Void)?
    @objc func pinched(_ pinch: UIPinchGestureRecognizer) { handle?(pinch) }
}

/// A scroll view that says when its size is known or has changed — which is
/// when a drawing can be centred in it and the window put where it opens.
private final class TreeScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    var onSafeArea: (() -> Void)?
    private var laidOut: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOut {
            laidOut = bounds.size
            onLayout?()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onSafeArea?()
    }
}

// MARK: - The sheets

/// The doors the menu opens. The tree asks Ihmiset for them rather than
/// pushing them: the navigation stack is the tab's.
private enum TreeDoor {
    case list, addPerson, heard, settings
}

/// A bond the rows could not hold, named for the menu.
private struct UndrawnBond: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let bond: String
}

/// Everything that stands around the drawing, behind one button: the ways
/// out of the screen, the key to its lines, and what the drawing cannot say.
///
/// A sheet of plain buttons rather than a menu, like the person's sheet: a
/// menu's rows barely grow with the text size, and no UI test here has been
/// able to open one.
private struct TreeMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    let heardCount: Int
    let undrawn: [UndrawnBond]
    let choose: (TreeDoor) -> Void

    /// The little drawing of a line in the key, beside the word for it.
    @ScaledMetric(relativeTo: .caption) private var markWidth: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sukupuu")
                        .font(Elder.display(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    action("Luettelo") { choose(.list) }
                    action("Lisää henkilö") { choose(.addPerson) }
                    // The door `PeopleScreen` puts under the list, in the
                    // same words.
                    if heardCount > 0 {
                        Button {
                            choose(.heard)
                        } label: {
                            HeardNamesDoorLabel(count: heardCount)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .elderTapTarget()
                        }
                        .buttonStyle(.borderless)
                    }
                    action("Asetukset") { choose(.settings) }

                    // The drawing is a code — two lines for a couple, a
                    // bracket down to the children, a bar over siblings —
                    // and nothing on the drawing says so. One under the
                    // other, and not three across a row that folds into a
                    // column when the words outgrow it: the audit refused a
                    // `ViewThatFits` here as "Dynamic Type font sizes are
                    // partially unsupported" on all three words. A column is
                    // one arrangement at every size, and it reads as a key.
                    Text("Mitä viivat tarkoittavat")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)
                    legendItem(Text("Pariskunta")) { coupleMark }
                    legendItem(Text("Lapset")) { descentMark }
                    legendItem(Text("Sisarukset")) { siblingMark }

                    // What the archive holds and the drawing cannot say.
                    // Everybody is of one generation in a picture, so a
                    // marriage between two of them, or a pair each entered as
                    // the other's parent, leaves a bond with nowhere to go,
                    // and `FamilyTreeLayout` names it rather than draw a
                    // relationship nobody entered — which is rule 4, and the
                    // easy half of it. This is the other half: a line quietly
                    // absent is the picture disagreeing with the cards, and
                    // from the drawing alone it looks exactly like a bond
                    // nobody has entered yet — the one reading that sends
                    // somebody off to enter it a second time. Nothing here
                    // calls anybody wrong: the app does not know which of
                    // two answers the family meant, and saying otherwise
                    // would be the guess asserted as fact all over again.
                    if !undrawn.isEmpty {
                        Text("Nämä eivät mahdu kuvaan")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                            .accessibilityAddTraits(.isHeader)
                        Text("Kuvassa jokainen on yhdessä polvessa, eivätkä nämä siteet mahdu siihen. Ne ovat tallessa kummankin omalla kortilla.")
                            .font(.subheadline)
                            .foregroundStyle(Elder.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(undrawn) { link in
                            Text("\(link.from) ja \(link.to) — \(link.bond)")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

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
                // A sheet of text buttons, so ink and not the accent
                // (`Elder.wax`, which is the red of removal).
                .tint(Color.primary)
            }
            .elderSurface()
        }
    }

    /// A title and nothing else: with an icon beside the words the audit has
    /// measured rows like these as not following Dynamic Type. The width is
    /// inside the label, so the whole row takes the tap.
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

    private func legendItem(_ word: Text, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 8) {
            mark()
                .frame(width: markWidth, alignment: .center)
                .accessibilityHidden(true)
            word
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var bar: some View { Rectangle().fill(Elder.supporting).frame(height: 2) }
    private var tick: some View { Rectangle().fill(Elder.supporting).frame(width: 2, height: 5) }

    private var coupleMark: some View {
        VStack(spacing: 3) { bar; bar }
    }

    private var descentMark: some View {
        VStack(spacing: 0) { bar; tick }
    }

    private var siblingMark: some View {
        VStack(spacing: 0) {
            bar
            HStack(spacing: 0) {
                tick
                Spacer(minLength: 0)
                tick
            }
        }
    }
}

/// What can be done from a person in the tree: open their card, or add a
/// relative for them without leaving the picture.
///
/// A sheet of plain buttons rather than a menu: a menu's rows barely grow with
/// the text size, and no UI test here has been able to open one.
private struct TreePersonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let person: Subject
    /// The same word as under the card, so the sheet says whose it is in
    /// the same terms; nil where the card has none.
    let word: String?
    /// How many memories the archive holds about them — the count under the
    /// name on the person list, the map plan's *"2 muistoa"* on a chip — so
    /// the sheet says whether the card has anything before *Avaa kortti*
    /// is tapped. Nothing when none: fifty-five cards saying *0 muistoa*
    /// would be the drawing repeating itself.
    let memories: Int
    let open: () -> Void
    let add: (RelationKind, Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.displayTitle)
                        .font(Elder.display(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                    if let word {
                        Text(word)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Elder.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if memories > 0 {
                        // Two keys, as on the person list: with no plural
                        // rule the count does not inflect by itself, and one
                        // memory read "1 muistoa" here — "1 memories" on an
                        // English phone — until 26 Sep 2026.
                        Group {
                            if memories == 1 {
                                Text("1 muisto")
                            } else {
                                Text("\(memories) muistoa")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    action("Avaa kortti") { open() }
                        .padding(.top, 8)

                    Text("Lisää sukulainen")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    action("Lisää vanhempi") { add(.parentOf, false) }
                    action("Lisää lapsi") { add(.parentOf, true) }
                    action("Lisää puoliso") { add(.spouseOf, false) }
                    action("Lisää sisarus") { add(.siblingOf, false) }
                    // Not kin, and drawn apart: after a gap, under the
                    // heading the card's own menu keeps it under.
                    action("Lisää ystävä") { add(.friendOf, false) }
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
                // Ink, for the menu sheet's reason above.
                .tint(Color.primary)
            }
            .elderSurface()
        }
    }

    /// A title and nothing else: with an icon beside the words the audit has
    /// measured rows like these as not following Dynamic Type. The width is
    /// inside the label, so the whole row takes the tap.
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

/// A relative asked for from the tree, carried across the sheet that asked.
private struct RelativeRequest: Identifiable {
    let id = UUID()
    let person: Subject
    let kind: RelationKind
    let asChild: Bool
}
