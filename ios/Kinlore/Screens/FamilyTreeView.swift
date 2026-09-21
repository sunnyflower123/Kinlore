import SwiftUI
import UIKit

/// The family drawn as a tree: a generation to a row, a line between a couple,
/// a bracket from parents down to their children — and, below them, everybody
/// nobody has said anything about yet.
///
/// What Ihmiset opens on, on a family member's phone, since 13 Sep 2026, with
/// the list one tap away (`PeopleScreen`). A grandparent's phone (the
/// text-floor signal) and VoiceOver get the list, and the relationships as
/// lists on each person's card, where they read at the largest size and aloud
/// — a picture of lines is nothing to read. That was the whole case against
/// drawing the tree (ARCHITECTURE §8, item 13), and it is why the cut could be
/// reversed: the phone it was a trap for does not see it.
///
/// **A map since 19 Sep 2026, and nothing else on the screen by default.** The
/// drawing fills the window, moves in both directions under one finger with
/// the momentum a map has, and grows about the two fingers pinching it; the
/// generation words ride the window's left edge, and everything that used to
/// stand around the picture — the key to its lines, the way to the list, the
/// door to the names heard, the note about bonds the rows cannot hold, the
/// settings — waits behind one button in the bar (`TreeMenuSheet`). Until
/// then the picture sat inside a vertical page with a horizontal strip cut
/// into it: two nested scroll views, which cannot be dragged diagonally, a
/// zoom anchored at the drawing's corner rather than the fingers, and at the
/// largest text size a rail of generation names taking more than half the
/// width and a sentence of instructions a third of the height, with the
/// family left a sliver between them.
///
/// A person in the tree is tapped for what can be done from there: their card,
/// or a relative added on the spot through the same `RelationPicker` the card
/// uses, so the tree grows where it is looked at.
///
/// Confirmed people and confirmed relationships only (rule 4): a proposal in a
/// picture of the family is the guess drawn as fact. Where everybody lands is
/// `FamilyTreeLayout`, checked on its own by
/// `scripts/family-tree-layout-check.swift`; this view only draws it.
struct FamilyTreeView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

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

    /// The scale the drawing is laid out at. A pinch changes it about the
    /// fingers and the two buttons about the window's middle; either way the
    /// words are laid out again at the new size rather than stretched, which
    /// is what keeps them sharp.
    @State private var zoom: CGFloat = 1

    /// Where the drawing is under the window, reported by the scroll view as
    /// it moves. The generation words are placed by it, and it decides
    /// whether they are about the family in view at all.
    @State private var window: TreeWindow?

    /// How much of the window's bottom the two zoom buttons take, measured
    /// from the buttons themselves. It is handed to the scroll view as part
    /// of its bottom inset, so the last row can be scrolled clear of the
    /// buttons and the drawing opens with nothing under them.
    @State private var controlsHeight: CGFloat = 0

    /// The person whose sheet is up, and what was asked of it. Acted on once
    /// the sheet has gone, so a card or a second sheet never arrives under one
    /// still on its way down.
    @State private var chosen: Subject?
    @State private var pendingOpen: Subject?
    @State private var pendingRelative: RelativeRequest?
    @State private var relative: RelativeRequest?

    /// The menu, and the door chosen in it, opened once it has gone down for
    /// the same reason.
    @State private var menu = false
    @State private var pendingDoor: TreeDoor?

    /// One place and one generation, growing with the text inside them, so a
    /// name at a larger size does not run into its neighbour.
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 156
    /// The same base size and text style `SubjectAvatar` scales by, so the
    /// lines can find the middle of each disc at every text size.
    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 48
    /// The caption's own band above the people related to nobody.
    @ScaledMetric(relativeTo: .headline) private var captionBand: CGFloat = 44
    /// The widest a generation's word may be before it wraps. Wide enough
    /// for *Lastenlastenlapset* on one line at the default text size: the
    /// words float over the drawing now rather than beside it, so their
    /// width is no longer taken from the picture, and *Isoisovan-hemmat*
    /// was the one hyphenation anybody had noticed.
    /// 140 since 19 Sep 2026: the widest generation word, *Isovanhempiesi
    /// polvi*, is 117.3 points of `.caption` at the default text size, and
    /// in the 116 that 128 left it it broke at the space into two lines —
    /// which zoomed out to the smallest covered the names in the row above,
    /// because the rail's words do not zoom and the air between rows does.
    @ScaledMetric(relativeTo: .caption) private var railWidth: CGFloat = 140
    /// The room a generation's word is given above its row: three lines of
    /// the caption face, standing on the top of the row's discs. Over the
    /// air between one generation and the next, where only lines run, and
    /// not over the discs — a word laid on the top of a disc cut a quarter
    /// out of whoever stood in the first column (seen 19 Sep 2026).
    @ScaledMetric(relativeTo: .caption) private var railBand: CGFloat = 60
    /// One line of a name under a disc, which is 21 points of `.body` at the
    /// default text size. It is here so that `cardBand` can be said in the
    /// same units the drawing is drawn in.
    @ScaledMetric(relativeTo: .body) private var nameLine: CGFloat = 21
    /// One line of *Sinä* under your own name, in the footnote face.
    @ScaledMetric(relativeTo: .footnote) private var youLine: CGFloat = 18

    /// From the top of a generation's row to the top of its discs.
    private static let rowInset: CGFloat = 8

    /// The band of a row that the people in it are actually drawn in: the air
    /// above the discs, a disc, the gap under it and a line of the name.
    /// `rowHeight` is this plus the air between one generation and the next,
    /// and the difference matters only to where the drawing opens — a row is
    /// 156 points at the default text size and 487 at AccessibilityXXXL,
    /// where the window under the page's own heading is about 440, so the
    /// middle of a row there is below everything drawn in it.
    private var cardBand: CGFloat { Self.rowInset + discSize + 6 + nameLine }

    private static let zoomRange: ClosedRange<CGFloat> = 0.4 ... 2.5

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

    private var layout: FamilyTreeLayout.Result {
        let ids = Set(people.map(\.id))
        let live = store.relations.filter { relation in
            relation.confirmed && relation.deletedAt == nil
                && ids.contains(relation.fromSubjectID) && ids.contains(relation.toSubjectID)
        }
        // A friendship is not a line in a family tree (§21: a friend is not
        // suku), and the layout is never handed one — as a link it would be
        // placed as a sibling. It is handed who is joined to the family by
        // friendship alone, and draws them apart under it; a friend who is
        // also somebody's kin is placed by the kinship.
        let links = live.compactMap { relation -> FamilyTreeLayout.Link? in
            let kind: FamilyTreeLayout.Kind
            switch relation.kind {
            case .parentOf: kind = .parent
            case .spouseOf: kind = .spouse
            case .siblingOf: kind = .sibling
            case .friendOf: return nil
            }
            return FamilyTreeLayout.Link(from: relation.fromSubjectID, to: relation.toSubjectID, kind: kind)
        }
        let kin = Set(links.flatMap { [$0.from, $0.to] })
        let aside = live.filter { $0.kind == .friendOf }
            .flatMap { [$0.fromSubjectID, $0.toSubjectID] }
            .filter { !kin.contains($0) }
        // How deep a card reaches below the row's centre line, in rows, so
        // that a line leaving somebody starts under their name: half the
        // disc, the gap and the name, and two fifths of a line more for the
        // descenders and some air — measured on the simulator, the letters
        // of a name reach 52.7 points below the disc's centre at the default
        // size, and a line started at the arithmetic's 51 sat on the
        // baseline. On your own card *Sinä* sits under the name, and its
        // letters end 74.7 points down; the bar to your children runs at 78.
        let you = yourCardID
        let name = discSize / 2 + 6 + nameLine
        let card = name + nameLine * 0.4
        let yours = name + 6 + youLine
        return FamilyTreeLayout.layout(people: people.map(\.id), links: links, aside: aside) { id in
            Double((id == you ? yours : card) / rowHeight)
        }
    }

    var body: some View {
        let result = layout
        let people = people
        let you = yourCardID
        // Nothing fits the drawing to the window, and the one thing that did
        // was removed on 19 Sep 2026. A place and a generation are
        // `@ScaledMetric`, so the picture grows with the reader's text while
        // the phone does not, and the obvious answer is to open it at
        // `window.width / (2 * columnWidth)` so that a couple is always in
        // view. That factor is Dynamic Type inverted: it shrinks the drawing
        // by as much as the text grew, so the larger a reader sets their type
        // the smaller this screen draws its names.
        // `testTheDrawingsNamesGrowWithTheReadersText` holds it now. The
        // reader may shrink this drawing; the app may not do it for them.
        ZStack(alignment: .bottomTrailing) {
            // Under the tab bar, the way a map is, and the scroll view keeps
            // that much of the drawing out from under it at the end, so the
            // last row can be scrolled clear of the tabs. Not under the top
            // bar: the status bar fades whatever scrolls beneath it, the
            // audit reads the fade as the name's own colour, and the policy
            // forgives that under the tab bar alone — where it was measured.
            // A grandparents' row faded to grey under the clock is not a
            // colour anybody chose, and the audit would be right to say so.
            //
            // The bars' insets are UIKit's to report, on the scroll view
            // itself, and not a GeometryReader's: measured 19 Sep 2026, a
            // proxy around this canvas answered a top inset of 116 points
            // for a frame that already began below the bar and nothing at
            // all for the tab bar the frame ran under, so the drawing kept
            // 116 points of air over its first row and opened with its last
            // row under the tabs.
            TreeCanvas(
                scale: $zoom,
                range: Self.zoomRange,
                size: CGSize(width: width(of: result), height: height(of: result)),
                controls: controlsHeight,
                opening: opening(result, you: you),
                key: DrawingKey(result: result, people: people, you: you),
                onWindow: { window = $0 }
            ) { scale in
                canvas(result, people: people, you: you)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: width(of: result) * scale,
                        height: height(of: result) * scale,
                        alignment: .topLeading
                    )
                    // The drawing is hosted by UIKit and inherits
                    // nothing from this view's environment on its own.
                    .environment(store)
                    .environment(session)
            }
            .overlay(alignment: .topLeading) {
                labels(result, you: you)
            }
            .ignoresSafeArea(edges: .bottom)

            // Inside the safe area, so they sit above the tabs and not under
            // them. Two small discs in a corner rather than a bar across the
            // bottom: the bar covered a name of any family at rest — Liisa
            // and Veikko at 1.04:1 on 16 Sep 2026 — and the corner covers
            // nothing where the drawing opens, which
            // `testTheTreeOpensWithNothingUnderTheZoomBar` measures.
            zoomButtons
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    controlsHeight = height + 8
                }
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
                    UndrawnBond(from: name(link.from, in: people), to: name(link.to, in: people), bond: bond(link.kind))
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
                open: {
                    pendingOpen = person
                    chosen = nil
                },
                add: { kind, asChild in
                    pendingRelative = RelativeRequest(person: person, kind: kind, asChild: asChild)
                    chosen = nil
                }
            )
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

    // MARK: - Drawing

    private func canvas(_ result: FamilyTreeLayout.Result, people: [Subject], you: String?) -> some View {
        let yours = yourRow(result, you: you)
        return ZStack(alignment: .topLeading) {
            // A band to a generation, every other one, so a row reads as one
            // row across a family too wide to see at once. Counted from your
            // own generation, so yours is always one of the shaded ones and
            // the word for it lands on a band rather than beside one.
            //
            // `Elder.card` on `Elder.paper` measures 1.11:1 — a tint and not
            // an edge, which is what this is for. What matters under rule 1 is
            // what the names measure against it, and primary text on card is
            // 16.81:1 against 15.17:1 on paper: both sides of the stripe are
            // comfortably over the minimum, so no name gets harder to read for
            // being in a shaded generation.
            let band = yourFamily(result, you: you)
            ForEach(treeRows(result, you: you), id: \.self) { row in
                if (row - (yours ?? 0)).isMultiple(of: 2) {
                    Rectangle()
                        .fill(Elder.card)
                        .frame(
                            width: CGFloat(band.map { $0.maxX - $0.minX + 1 } ?? max(result.width, 1)) * columnWidth,
                            height: rowHeight
                        )
                        .offset(x: CGFloat(band?.minX ?? 0) * columnWidth, y: y(ofRow: row, result))
                        .accessibilityHidden(true)
                }
            }

            // Under the people, and through the middle of their discs: every
            // disc has a paper backing, so a line meets it edge to edge. A
            // couple's line runs at that height, above every name, and a line
            // that leaves a person downwards starts under their name — the
            // layout is told how deep a card is — so nothing runs through a
            // word.
            Canvas { context, _ in
                for segment in result.segments {
                    let from = point(segment.x1, segment.y1, result)
                    let to = point(segment.x2, segment.y2, result)
                    // A couple is two lines, the way a genealogy draws a
                    // marriage — which is the one line on this canvas that
                    // joins equals rather than a generation to the next, and
                    // the only way to tell it from a sibling bar at a glance.
                    let offsets: [CGFloat] = segment.kind == .couple ? [-2.5, 2.5] : [0]
                    // The pair is drawn across the line rather than always
                    // under it, and each part reaches a little past its own
                    // ends. A marriage the row could not put side by side —
                    // the third one of a man married three times — bends below
                    // the row to get round whoever stands between, and it has
                    // to read as a marriage all the way round: offset downward
                    // the two uprights of that bend would be one line drawn
                    // twice, and square corners would gape.
                    let run = CGPoint(x: to.x - from.x, y: to.y - from.y)
                    let length = max((run.x * run.x + run.y * run.y).squareRoot(), 0.001)
                    let along = CGPoint(x: run.x / length, y: run.y / length)
                    let reach: CGFloat = segment.kind == .couple ? 2.5 : 0
                    for shift in offsets {
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

            ForEach(people) { person in
                if let place = result.placements[person.id] {
                    // By its top, not its centre: a name that wraps to two
                    // lines must not lift its disc off the line it hangs on.
                    node(person, isYou: person.id == you)
                        .offset(
                            x: point(place.x, Double(place.row), result).x - nodeWidth / 2,
                            y: y(ofRow: place.row, result) + Self.rowInset
                        )
                }
            }
        }
        .frame(width: width(of: result), height: height(of: result), alignment: .topLeading)
    }

    /// Where the window goes when the drawing first appears: your own column
    /// in its middle, and your own row a little under a third of the way
    /// down. A family of 53 is 2376 points wide against a 402-point window
    /// and 1136 tall, so a picture that opens at its own top left corner
    /// opens on whoever happens to be oldest — measured 19 Sep 2026: six of
    /// the fifty-three on screen and the person holding the phone four
    /// places across and three rows down, reachable only by scrolling blind
    /// in two directions at once. Nil on a phone linked to no card, which
    /// opens at the top left like any picture.
    private func opening(_ result: FamilyTreeLayout.Result, you: String?) -> TreeOpening? {
        guard let you, let place = result.placements[you] else { return nil }
        let top = y(ofRow: place.row, result)
        let span = y(ofRow: place.row + 1, result) - top
        return TreeOpening(
            centreX: (CGFloat(place.x) + 0.5) * columnWidth,
            bandTop: top,
            // The band the people are in, not the row they belong to. A
            // target taller than the window cannot put its contents anywhere
            // the reader can see them: at AccessibilityXXXL the tree opened
            // on a disc with its name below the fold and nothing else, which
            // is what a row-tall target bought. A band shorter than the
            // window always lands.
            // Your own card has a line more than the others, the word under
            // the name, and it is the one card the opening keeps whole.
            bandHeight: min(span, cardBand + 6 + youLine),
            row: Self.openingRow,
            // The top of every row with people in it — the rows the layout
            // leaves empty for a caption have no names — so the opening can
            // tell which names the fraction would put under the buttons.
            rows: (0 ..< result.rows)
                .filter { !result.captionRows.contains($0) }
                .map { y(ofRow: $0, result) },
            card: cardBand,
            name: nameLine
        )
    }

    /// Where your own card sits when the picture opens: a little under a
    /// third of the way down rather than halfway, which is a measurement and
    /// not a taste. Halfway left six names in the strip the zoom bar covered —
    /// Saima, Lauri and Hellin with their initials — 0.42 left three, 0.6
    /// left three, and a third of the way down left none. The bar is two
    /// discs in a corner now and the test that fitted this number measures
    /// the discs instead, so the number is kept for the picture it gives —
    /// your parents above you and your children below — rather than for the
    /// strip.
    private static let openingRow: CGFloat = 0.31

    private func node(_ person: Subject, isYou: Bool) -> some View {
        Button {
            chosen = person
        } label: {
            VStack(spacing: 6) {
                SubjectAvatar(subject: person, size: 48)
                    // A paper disc under the ink one. `SubjectAvatar` fills
                    // with ink at 75 %, so a line behind it ran straight
                    // through the letter (seen on 13 Sep 2026). The avatar
                    // draws its disc from its top-leading corner, so the
                    // backing sits there too, at the disc's own size.
                    .background(alignment: .topLeading) {
                        Circle()
                            .fill(Elder.paper)
                            .frame(width: discSize, height: discSize)
                    }
                Text(person.displayTitle)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Which person in the family holds this phone, since 13 Sep
                // 2026: a word under the name rather than a colour, so it does
                // not rest on colour alone (rule 1).
                if isYou {
                    Text("Sinä")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // No card behind the name. A card hid the line between a couple,
            // leaving a dash floating between two names (seen on 13 Sep 2026).
            .frame(width: nodeWidth, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isYou ? Text("\(person.displayTitle), sinä") : Text(person.displayTitle))
    }

    /// Two buttons for a hand that cannot pinch, in the corner a map keeps
    /// its controls in.
    private var zoomButtons: some View {
        HStack(spacing: 12) {
            Button {
                zoom = clamped(zoom / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.title3)
                    .elderTapTarget()
            }
            .accessibilityLabel("Pienennä")

            Button {
                zoom = clamped(zoom * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.title3)
                    .elderTapTarget()
            }
            .accessibilityLabel("Suurenna")
        }
        // The system's bordered style, which is glass on iOS 26 and a tinted
        // disc before it: an edge of its own on paper and on the bands alike,
        // where a paper disc with a hairline would have none (`Elder.rule`).
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    // MARK: - Words on the window

    /// The words that stay where the reader can see them while the drawing
    /// moves: which generation each row is, down the left edge of the window,
    /// and the caption over the people related to nobody.
    ///
    /// The tree drew five discs and some lines and said nothing about what any
    /// row was, and that was the first thing anybody asked of it (16 Sep 2026).
    /// The words are counted from your own row, because that is the only
    /// anchor the archive has: it stores no gender, so a per-person word would
    /// have to read *"Eevan vanhempi"*, while a generation has a name in
    /// Finnish that needs none.
    ///
    /// They ride the window rather than the drawing, and they keep their own
    /// size while the drawing zooms: in a family wide enough to need
    /// scrolling, a word that scrolls away names the rows you are no longer
    /// looking at, and zooming out to see the whole family must leave the one
    /// thing that explains it readable. Until 19 Sep 2026 they were a column
    /// beside the drawing, which is the same promise kept at the price of the
    /// column's width — more than half the screen at the largest text size —
    /// and the caption was painted into the drawing's own left edge, four
    /// places off the screen whenever the picture opened on somebody's own
    /// column.
    private func labels(_ result: FamilyTreeLayout.Result, you: String?) -> some View {
        ZStack(alignment: .topLeading) {
            if let window {
                let yours = yourRow(result, you: you)
                // Counted from your own row, so they are about the picture
                // only while your own family is in it. Scrolled sideways on
                // to a family that shares nobody with yours — which starts at
                // row 0 because neither family knows anything about the
                // other's age — the same words would call its oldest
                // generation your great-grandparents, and nobody entered
                // that. The drawing's own numbering, which a phone linked to
                // no card gets, stays where it is: every family starts at
                // row 0, so a row counted from the top of the drawing is as
                // true of one as of another.
                let mine = yours == nil
                    || FamilyTreeLayout.inView(yourFamily(result, you: you), columns(in: window))
                let left = window.visible.minX + 8
                if mine {
                    ForEach(treeRows(result, you: you), id: \.self) { row in
                        railWord(generationName(row, from: yours), bold: row == yours)
                            .frame(height: railBand, alignment: .bottomLeading)
                            .offset(
                                x: left,
                                y: (y(ofRow: row, result) + Self.rowInset) * window.scale + window.shift.y
                                    - railBand - 2
                            )
                    }
                } else {
                    // Not nothing. The words leaving is the whole point, and
                    // a reader who watched them go is owed the reason they
                    // went — that these people are not counted from anybody.
                    railWord(Text("Toinen perhe"), bold: false)
                        .offset(x: left, y: window.visible.minY + 8)
                }

                // In the empty row the layout leaves above each band of
                // people drawn apart — the friends, and the people related to
                // nobody — standing on the bottom of that row so it stays
                // with them at every text size and every zoom. Shown with no
                // tree above them too: then they are the whole family, and
                // the caption says why nobody is joined.
                if let asideRow = result.asideRow {
                    caption(Text("Ystävät"), over: asideRow, result, scale: window.scale, shiftY: window.shift.y, left: left)
                }
                if let looseRow = result.looseRow {
                    caption(Text("Ei vielä sukupuussa"), over: looseRow, result, scale: window.scale, shiftY: window.shift.y, left: left)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    /// One generation's word. On a scrap of paper so that it reads across
    /// whatever line of the drawing happens to be under the window's edge;
    /// on a band the scrap is a tint lighter than the band, which is what
    /// the band's own colour was chosen to allow.
    private func railWord(_ word: Text, bold: Bool) -> some View {
        word
            .font(.caption)
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: railWidth - 12, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Elder.paper, in: RoundedRectangle(cornerRadius: 6))
    }

    /// The window in the drawing's own units — `x` in person-widths, which is
    /// what an `Extent` is measured in.
    private func columns(in window: TreeWindow) -> ClosedRange<Double> {
        // A pinch in progress can hand this a magnification near zero, and a
        // place is never narrower than a point.
        let place = max(columnWidth * window.scale, 1)
        let first = Double((window.visible.minX - window.shift.x) / place)
        return first ... max(first, Double((window.visible.maxX - window.shift.x) / place))
    }

    /// What a row is called, counted from yours. Nobody linked to a card — a
    /// phone with no family behind it — gets the drawing's own numbering
    /// instead, which claims nothing it cannot know.
    /// A `Text` rather than a key on purpose: `localisation-check.mjs` reads
    /// the literal inside a `Text(` call and nothing else, so a word handed to
    /// a helper as a key has no English and nothing says so. That is exactly
    /// how the help page stayed Finnish on an English phone until 4 Sep 2026.
    private func generationName(_ row: Int, from yours: Int?) -> Text {
        guard let yours else { return Text("\(row + 1). polvi") }
        switch row - yours {
        // Worded as generations, the way your own row is, and not as
        // relationships (19 Sep 2026): the row above you holds your parents'
        // brothers and sisters and the people they married, and *Vanhemmat*
        // over four of them read as four parents. Two generations each way
        // have a word; from three on it is a count, because
        // *Isoisovanhempiesi polvi* and *Lastenlastenlastesi polvi* are 134
        // and 138 points of `.caption` and the rail's word is one line — a
        // second line hides the names in the row above at the smallest zoom.
        case -2: return Text("Isovanhempiesi polvi")
        case -1: return Text("Vanhempiesi polvi")
        case 0: return Text("Sinun polvesi")
        case 1: return Text("Lastesi polvi")
        case 2: return Text("Lastenlastesi polvi")
        case let above where above < 0: return Text("\(-above) polvea ylempänä")
        case let below: return Text("\(below) polvea alempana")
        }
    }

    /// The name on somebody's card, for a sentence rather than a disc.
    private func name(_ id: String, in people: [Subject]) -> String {
        people.first { $0.id == id }?.displayTitle ?? id
    }

    /// What two people were entered as, in a word. Built with
    /// `String(localized:)` because it is a `String` and not a literal inside
    /// `Text`: handed a variable, `Text` shows it verbatim, and an English
    /// phone would read one Finnish word in the middle of the sentence.
    /// `localisation-check.mjs` counts keys, not lookups, so nothing else
    /// would report it.
    private func bond(_ kind: FamilyTreeLayout.Kind) -> String {
        switch kind {
        case .spouse: return String(localized: "aviopuolisot")
        case .sibling: return String(localized: "sisarukset")
        case .parent: return String(localized: "vanhempi ja lapsi")
        }
    }

    /// A caption over a band of people drawn apart from the generations,
    /// standing on the bottom of the empty row the layout leaves over it.
    private func caption(
        _ text: Text, over first: Int, _ result: FamilyTreeLayout.Result,
        scale: CGFloat, shiftY: CGFloat, left: CGFloat
    ) -> some View {
        text
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Elder.paper, in: RoundedRectangle(cornerRadius: 6))
            .frame(height: captionBand, alignment: .bottomLeading)
            .offset(x: left, y: (y(ofRow: first - 1, result) + captionBand) * scale + shiftY - captionBand)
    }

    // MARK: - Arithmetic

    /// A name wraps inside this, and the gap to the next place stays clear.
    private var nodeWidth: CGFloat { columnWidth - 20 }

    /// Layout units to points. A whole row lands on the middle of that
    /// generation's discs; a half row, where a bracket crosses, lands halfway to
    /// the next generation's.
    private func point(_ x: Double, _ y: Double, _ result: FamilyTreeLayout.Result) -> CGPoint {
        CGPoint(
            x: (CGFloat(x) + 0.5) * columnWidth,
            y: CGFloat(y) * rowHeight + Self.rowInset + discSize / 2 - shift(atRow: y, result)
        )
    }

    /// The generations the words are about: the ones your own family has.
    ///
    /// Not every row on the canvas. A family that shares nobody with yours is
    /// drawn beside it and starts at row 0 like every family does, which is no
    /// claim about its age — so a band across it, and a word beside it, would
    /// be. The friends and the people related to nobody are under their
    /// captions and are not generations either: a friend is not one, and
    /// nobody has said what the rest are to anyone.
    private func treeRows(_ result: FamilyTreeLayout.Result, you: String?) -> [Int] {
        let end = yourFamily(result, you: you)?.rows ?? result.bandStart
        return end > 0 ? Array(0 ..< end) : []
    }

    /// The family this phone's card is in, or the first one drawn when it is
    /// in none — which is the family the tree grew from.
    private func yourFamily(_ result: FamilyTreeLayout.Result, you: String?) -> FamilyTreeLayout.Extent? {
        let index = you.flatMap { result.family[$0] } ?? 0
        return result.familyExtents.indices.contains(index) ? result.familyExtents[index] : nil
    }

    /// Your own row, when this phone is linked to a card that is in the tree.
    /// Nil when it is not, and nil when your card is drawn apart — a friend of
    /// the family, or related to nobody — since from down there you are not a
    /// generation to count from.
    private func yourRow(_ result: FamilyTreeLayout.Result, you: String?) -> Int? {
        guard let you, let place = result.placements[you] else { return nil }
        guard place.row < result.bandStart else { return nil }
        return place.row
    }

    /// The top of a row, in points.
    private func y(ofRow row: Int, _ result: FamilyTreeLayout.Result) -> CGFloat {
        CGFloat(row) * rowHeight - shift(atRow: Double(row), result)
    }

    private func width(of result: FamilyTreeLayout.Result) -> CGFloat {
        CGFloat(max(result.width, 1)) * columnWidth
    }

    private func height(of result: FamilyTreeLayout.Result) -> CGFloat {
        CGFloat(max(result.rows, 1)) * rowHeight - captionTrim * CGFloat(result.captionRows.count)
    }

    /// The layout leaves a whole empty generation above each band of people
    /// drawn apart — the friends, and the people related to nobody — for its
    /// caption. A generation's height over one line of text is a hole — 134
    /// points of nothing at the default text size, measured on 16 Sep 2026 —
    /// so everything from a caption down moves up by the difference and the
    /// drawing loses the hole, once for every caption above the row.
    ///
    /// Nothing above the first caption moves, so no line needs a share of it:
    /// the layout draws none below the last generation.
    private func shift(atRow row: Double, _ result: FamilyTreeLayout.Result) -> CGFloat {
        let bandsAbove = [result.asideRow, result.looseRow].compactMap { $0 }.filter { row >= Double($0) }.count
        return captionTrim * CGFloat(bandsAbove)
    }

    private var captionTrim: CGFloat { max(0, rowHeight - captionBand) }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }
}

// MARK: - The map

/// Where the drawing is under the window: the position of its top left
/// corner in the scroll view's own bounds, the scale it is drawn at, and the
/// part of the bounds not under a bar.
private struct TreeWindow: Equatable {
    var shift: CGPoint
    var scale: CGFloat
    var visible: CGRect
}

/// Where the window is put the first time the drawing's size is known, in the
/// drawing's own unscaled points: a column to centre, and a band to stand a
/// fraction of the way down the window.
private struct TreeOpening: Equatable {
    var centreX: CGFloat
    var bandTop: CGFloat
    var bandHeight: CGFloat
    var row: CGFloat
    /// The top of every row that has people in it, in the drawing's points.
    var rows: [CGFloat]
    /// A row's card band, and the line of the name at the bottom of it.
    var card: CGFloat
    var name: CGFloat
}

/// Everything the drawing is drawn from. The scroll view lays the drawing out
/// again only when this changes, and not on every report of where the window
/// has scrolled to — which arrives every frame, and each of which evaluates
/// the body this view is built in.
private struct DrawingKey: Equatable {
    var result: FamilyTreeLayout.Result
    var people: [Subject]
    var you: String?
}

/// A `UIScrollView` around the drawing: one finger moves it in both directions
/// at once and lets go with momentum, two fingers scale it about themselves,
/// and the two buttons scale it about the window's middle.
///
/// Why UIKit, and why not its own zoom. SwiftUI's `ScrollView` scrolls two
/// axes but has no pinch of its own, and the previous shape of this screen —
/// a `MagnifyGesture` over a `scaleEffect` anchored at the drawing's corner —
/// grew the picture about that corner rather than the fingers, which is the
/// difference between a map and a page. `UIScrollView` has the pan and the
/// deceleration. It also has a pinch, and that one is not used: it zooms by
/// transforming the view, so text is stretched from its rendered pixels and
/// blurs until the gesture ends. Here the pinch drives the SwiftUI scale
/// instead and the drawing is laid out again at every step, sharp at every
/// size, with the point under the fingers put back under the fingers by
/// arithmetic — the same arithmetic the buttons use about the middle.
private struct TreeCanvas<Content: View>: UIViewRepresentable {
    @Binding var scale: CGFloat
    let range: ClosedRange<CGFloat>
    /// The drawing's own size at scale 1.
    let size: CGSize
    /// The band the zoom buttons take at the window's bottom, from the
    /// buttons themselves. The bars' own insets are read off the scroll
    /// view, which UIKit keeps current for a view under a tab bar.
    let controls: CGFloat
    let opening: TreeOpening?
    let key: DrawingKey
    let onWindow: (TreeWindow) -> Void
    @ViewBuilder let content: (CGFloat) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TreeScrollView {
        let scrollView = TreeScrollView()
        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        scrollView.delegate = coordinator
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.backgroundColor = .clear

        let host = UIHostingController(rootView: AnyView(content(scale)))
        host.view.backgroundColor = .clear
        // The window's bars are the scroll view's business, above; the
        // drawing is laid out edge to edge in its own frame.
        host.safeAreaRegions = []
        scrollView.addSubview(host.view)
        coordinator.host = host

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        pinch.delegate = coordinator
        scrollView.addGestureRecognizer(pinch)
        scrollView.onLayout = { [weak coordinator] in coordinator?.layoutChanged() }
        scrollView.onSafeArea = { [weak coordinator] in coordinator?.safeAreaChanged() }
        return scrollView
    }

    func updateUIView(_ scrollView: TreeScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }
        coordinator.content = { AnyView(content($0)) }
        coordinator.onWindow = onWindow
        let binding = _scale
        coordinator.setScale = { binding.wrappedValue = $0 }
        coordinator.range = range
        coordinator.opening = opening

        coordinator.strip = controls
        // The zoom buttons are measured after the first layout: measured
        // 19 Sep 2026, an opening taken once at that layout was clamped
        // against a bottom inset without them and the drawing sat 73 points
        // lower than asked, at its own end. So the opening is applied again
        // for as long as the reader has not moved the picture.
        var reopen = coordinator.applyInsets()

        var redraw = false
        if coordinator.size != size {
            coordinator.size = size
            redraw = true
        }
        if coordinator.key != key {
            coordinator.key = key
            redraw = true
        }
        if coordinator.scale != scale {
            // The buttons: about the middle of what the reader can see.
            coordinator.moved = true
            coordinator.apply(scale: scale, about: coordinator.visibleRect.middle, settle: true)
        } else if redraw {
            coordinator.render()
            coordinator.place()
            // A drawing of a new size under the old offset shows some other
            // part of the family, and a smaller one is clamped by the scroll
            // view to an offset the old size never asked for. Measured
            // 19 Sep 2026: the accessibility audit steps the text size
            // through twelve categories and back, the first of them shrank
            // the drawing from 1136 to 981 points, the offset went from 478
            // to 396 and stayed there when the size came back — the loose
            // row under the buttons, and six names' colours read off pixels
            // the drawing had left. So the opening is applied again for a
            // new size as it is for a new inset, for as long as the reader
            // has not moved the picture.
            reopen = true
        }
        if reopen {
            coordinator.open()
            coordinator.report()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var scrollView: TreeScrollView?
        var host: UIHostingController<AnyView>?
        var content: ((CGFloat) -> AnyView)?
        var onWindow: ((TreeWindow) -> Void)?
        var setScale: ((CGFloat) -> Void)?
        var range: ClosedRange<CGFloat> = 0.4 ... 2.5
        var opening: TreeOpening?
        /// The zoom buttons' band at the bottom, part of the inset there.
        var strip: CGFloat = 0
        /// True once the reader has dragged, pinched or pressed a button:
        /// from then on the picture is where they put it, and the opening
        /// is not applied again.
        var moved = false
        var size: CGSize = .zero
        var key: DrawingKey?
        /// The scale the drawing is laid out at now.
        var scale: CGFloat = 1
        /// True while SwiftUI is updating this view, when a report back into
        /// its state has to wait for the update to end.
        var updating = false
        private var pinchStart: CGFloat = 1
        private var lastWindow: TreeWindow?

        /// Where the drawing's top left corner is in the content: zero, or
        /// the margin that centres a drawing smaller than the window.
        var origin: CGPoint { host?.view.frame.origin ?? .zero }

        /// The bars the window runs under, from UIKit, and the buttons'
        /// band, as the content's insets. True when they changed.
        func applyInsets() -> Bool {
            guard let scrollView else { return false }
            let safe = scrollView.safeAreaInsets
            let inset = UIEdgeInsets(top: safe.top, left: safe.left, bottom: safe.bottom + strip, right: safe.right)
            guard scrollView.contentInset != inset else { return false }
            scrollView.contentInset = inset
            scrollView.verticalScrollIndicatorInsets = inset
            scrollView.horizontalScrollIndicatorInsets = inset
            return true
        }

        /// The part of the bounds not under a bar, in the frame's own points.
        var visibleRect: CGRect {
            guard let scrollView else { return .zero }
            let inset = scrollView.contentInset
            return CGRect(
                x: inset.left,
                y: inset.top,
                width: max(0, scrollView.bounds.width - inset.left - inset.right),
                height: max(0, scrollView.bounds.height - inset.top - inset.bottom)
            )
        }

        /// The drawing laid out again at the current scale.
        func render() {
            guard let host, let content else { return }
            host.rootView = content(scale)
            // Now rather than on the next turn of the run loop, so that the
            // picture and its frame change in the same frame.
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        /// The drawing's frame and the content around it. A drawing smaller
        /// than the window is drawn in its middle rather than against a
        /// corner, which a scroll view does not do on its own: the content
        /// is padded to the window and the drawing set in the middle of it.
        func place() {
            guard let scrollView, let host else { return }
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            let visible = visibleRect.size
            let content = CGSize(width: max(drawn.width, visible.width), height: max(drawn.height, visible.height))
            host.view.frame = CGRect(
                origin: CGPoint(x: (content.width - drawn.width) / 2, y: (content.height - drawn.height) / 2),
                size: drawn
            )
            scrollView.contentSize = content
        }

        /// A new scale, with the drawing point under `point` put back under
        /// it. `point` is in the frame's own coordinates — where the fingers
        /// are, or the middle of what can be seen. A pinch in progress is
        /// allowed to overshoot the content, since the pan under the same
        /// fingers is still going; a button settles inside it at once.
        func apply(scale new: CGFloat, about point: CGPoint, settle: Bool) {
            guard let scrollView else { return }
            let clamped = min(max(new, range.lowerBound), range.upperBound)
            let old = scale
            guard clamped != old else { return }
            let offset = scrollView.contentOffset
            // The drawing point under the finger, in the drawing's own units.
            let under = CGPoint(
                x: (point.x + offset.x - origin.x) / old,
                y: (point.y + offset.y - origin.y) / old
            )
            scale = clamped
            render()
            place()
            let target = CGPoint(
                x: origin.x + under.x * clamped - point.x,
                y: origin.y + under.y * clamped - point.y
            )
            scrollView.contentOffset = settle ? clamp(target) : target
            if !updating { setScale?(clamped) }
            report()
        }

        /// The offsets the scroll view would settle at on its own.
        func clamp(_ offset: CGPoint) -> CGPoint {
            guard let scrollView else { return offset }
            let inset = scrollView.contentInset
            let minX = -inset.left
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
            let minY = -inset.top
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
            return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
        }

        /// The window has a size, or a new one.
        func layoutChanged() {
            _ = applyInsets()
            place()
            open()
            report()
        }

        /// UIKit has the bars' insets for this window, or new ones.
        func safeAreaChanged() {
            guard applyInsets() else { return }
            place()
            open()
            report()
        }

        /// Without animation: this is where the picture begins rather than
        /// somewhere it has been carried. Applied at every change of size or
        /// inset until the reader moves the picture themselves.
        func open() {
            // Not before the buttons have been measured: an opening taken
            // against a window without their band is moved when it arrives,
            // and an audit that began between the two read every name's
            // colour off pixels 83 points away from it (19 Sep 2026).
            guard !moved, strip > 0, let scrollView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let visible = visibleRect
            guard let opening else {
                scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
                return
            }
            let band = opening.bandHeight * scale
            let yours = origin.y + opening.bandTop * scale
            var y = yours + opening.row * band - visible.minY - opening.row * visible.height
            // Then the names, if the fraction has left a row's under the
            // buttons: lifted until they end at the strip's top when your
            // own card stays whole, pushed below the strip when it stays
            // whole that way instead, and left where the fraction put them
            // when neither move keeps it. Under the tab bar is below the
            // fold and a finger's business; the strip is the one piece of
            // chrome that stands on the drawing. A disc's edge under a
            // button is the map's own business too — at the largest text
            // size a row is taller than the window, so a disc is under
            // something whatever the opening — and the names are the
            // words. At most one row's names can be in the strip at once,
            // since the air between two rows' names is wider than it, and
            // a move that clears one row cannot carry another in.
            //
            // The last row is the case this began as: measured 19 Sep 2026
            // at the default size, "Saima" and "Lauri" five points under
            // the buttons' top edge with the strip counted and the fraction
            // alone deciding. The first version lifted every row that ended
            // short of the drawing's end and carried Elina off the top at
            // the largest size (y −273); the second lifted the last row
            // alone, and the next row down at that size stood under the
            // buttons with nothing said about it.
            let strip = visible.maxY ..< visible.maxY + strip
            for top in opening.rows {
                let bottom = origin.y + (top + opening.card) * scale - y
                let start = bottom - opening.name * scale
                guard start < strip.upperBound, bottom > strip.lowerBound else { continue }
                let lift = bottom - strip.lowerBound
                let push = strip.upperBound - start
                if yours - (y + lift) >= visible.minY {
                    y += lift
                } else if yours + band - (y - push) <= visible.maxY {
                    y -= push
                }
                break
            }
            scrollView.contentOffset = clamp(CGPoint(
                x: origin.x + opening.centreX * scale - visible.midX,
                y: y
            ))
        }

        /// Where the drawing is now, to whoever placed the words on the window.
        func report() {
            guard let scrollView, let onWindow else { return }
            let window = TreeWindow(
                shift: CGPoint(x: origin.x - scrollView.contentOffset.x, y: origin.y - scrollView.contentOffset.y),
                scale: scale,
                visible: visibleRect
            )
            guard window != lastWindow else { return }
            lastWindow = window
            if updating {
                // The newest window at delivery, not the one in hand: the
                // first update's report is deferred and the first layout's
                // is not, so a deferred report delivered as taken landed
                // after the layout's and put every word where the drawing
                // had been before it opened (measured 19 Sep 2026, the
                // generation words two rows below their rows).
                DispatchQueue.main.async { [weak self] in
                    guard let self, let latest = self.lastWindow else { return }
                    self.onWindow?(latest)
                }
            } else {
                onWindow(window)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            report()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            moved = true
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard let scrollView else { return }
            switch gesture.state {
            case .began:
                moved = true
                pinchStart = scale
            case .changed:
                // `location(in:)` answers in the scroll view's bounds, whose
                // origin is the content offset; the frame's own point is
                // that less the offset.
                let inContent = gesture.location(in: scrollView)
                let point = CGPoint(
                    x: inContent.x - scrollView.contentOffset.x,
                    y: inContent.y - scrollView.contentOffset.y
                )
                apply(scale: pinchStart * gesture.scale, about: point, settle: false)
            case .ended, .cancelled, .failed:
                // Back inside the content, the way the pan bounces back.
                scrollView.setContentOffset(clamp(scrollView.contentOffset), animated: true)
            default:
                break
            }
        }

        /// The pinch and the scroll view's own pan at once, so two fingers
        /// that drift while they pinch move the drawing as well as scale it.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// A scroll view that says when its size is known or has changed — which is
/// when a drawing can be centred in it and the window put where it opens.
private final class TreeScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    var onSafeArea: (() -> Void)?
    private var laidOut: CGSize = .zero

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onSafeArea?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // On a change of size only: a scroll view lays itself out on every
        // move, and the drawing must not be placed again on each of them.
        if bounds.size != laidOut {
            laidOut = bounds.size
            onLayout?()
        }
    }
}

private extension CGRect {
    var middle: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - The menu

/// A door the menu opens, taken once the sheet has gone down.
private enum TreeDoor {
    case list, addPerson, heard, settings
}

/// A bond the drawing could not hold, as a sentence's three parts.
private struct UndrawnBond: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let bond: String
}

/// Everything that used to stand around the drawing, behind one button: the
/// ways out of the screen, the key to its lines, and what the drawing cannot
/// say.
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
                    // and until 16 Sep 2026 nothing on the screen said so.
                    // One under the other, and not three across a row that
                    // folds into a column when the words outgrow it:
                    // `ViewThatFits` was the first shape and the audit
                    // refused it — "Dynamic Type font sizes are partially
                    // unsupported" on all three words. A column is one
                    // arrangement at every size, and it reads as a key.
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
                    // and `FamilyTreeLayout` drops the line rather than draw
                    // a relationship nobody entered — which is rule 4, and
                    // the easy half of it.
                    //
                    // This is the other half (19 Sep 2026). A line quietly
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
    let open: () -> Void
    let add: (RelationKind, Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.displayTitle)
                        .font(Elder.display(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    action("Avaa kortti") { open() }

                    Text("Lisää sukulainen")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    action("Lisää vanhempi") { add(.parentOf, false) }
                    action("Lisää lapsi") { add(.parentOf, true) }
                    action("Lisää puoliso") { add(.spouseOf, false) }
                    action("Lisää sisarus") { add(.siblingOf, false) }
                    // Not kin, and drawn apart (21 Sep 2026): after a gap,
                    // under the heading the card's own menu keeps it under.
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
            }
            .elderSurface()
        }
    }

    /// A title and nothing else: with an icon beside the words the audit has
    /// measured rows like these as not following Dynamic Type. The width is
    /// inside the label, so the whole row takes the tap. Outside it only the
    /// words did, and a tap in the middle of the row met nothing (13 Sep 2026).
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
