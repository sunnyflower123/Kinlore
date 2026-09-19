import SwiftUI

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

    /// Names heard and not yet checked. The door to them sits under the tree
    /// as it sits under the list, so neither view hides them.
    var heardCount = 0
    /// Opens a person's card. The navigation stack belongs to Ihmiset.
    var onOpen: (Subject) -> Void = { _ in }

    /// Whether the drawing has been put where it opens. Once per appearance
    /// and never again: after that, where the picture sits is the reader's
    /// own business.
    @State private var opened = false

    /// Pinch to zoom, and two buttons for a hand that cannot pinch.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    /// The part of the drawing under the window, in the drawing's own points
    /// before the zoom is divided back out. Nil until it has been measured,
    /// and the rail asks it: a picture nobody has scrolled yet is one nobody
    /// has scrolled off their own family.
    @State private var window: CGRect?

    /// The person whose sheet is up, and what was asked of it. Acted on once
    /// the sheet has gone, so a card or a second sheet never arrives under one
    /// still on its way down.
    @State private var chosen: Subject?
    @State private var pendingOpen: Subject?
    @State private var pendingRelative: RelativeRequest?
    @State private var relative: RelativeRequest?

    /// One place and one generation, growing with the text inside them, so a
    /// name at a larger size does not run into its neighbour.
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 156
    /// The same base size and text style `SubjectAvatar` scales by, so the
    /// lines can find the middle of each disc at every text size.
    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 48
    /// The caption's own band above the people related to nobody.
    @ScaledMetric(relativeTo: .headline) private var captionBand: CGFloat = 44
    /// The rail down the left, naming each generation. It does not scroll
    /// sideways with the drawing: in a family wide enough to need scrolling,
    /// a label that scrolls away names the rows you are no longer looking at.
    @ScaledMetric(relativeTo: .caption) private var railWidth: CGFloat = 78
    /// The little drawing of a line in the legend, beside the word for it.
    @ScaledMetric(relativeTo: .caption) private var markWidth: CGFloat = 20

    /// From the top of a generation's row to the top of its discs.
    private static let rowInset: CGFloat = 8

    private static let zoomRange: ClosedRange<CGFloat> = 0.4 ... 2.5

    /// The horizontal scroll view's own space, which the drawing's frame is
    /// measured in.
    private static let space = "tree"

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
        let links = store.relations.compactMap { relation -> FamilyTreeLayout.Link? in
            guard relation.confirmed, relation.deletedAt == nil,
                  ids.contains(relation.fromSubjectID), ids.contains(relation.toSubjectID)
            else { return nil }
            let kind: FamilyTreeLayout.Kind
            switch relation.kind {
            case .parentOf: kind = .parent
            case .spouseOf: kind = .spouse
            case .siblingOf: kind = .sibling
            }
            return FamilyTreeLayout.Link(from: relation.fromSubjectID, to: relation.toSubjectID, kind: kind)
        }
        return FamilyTreeLayout.layout(people: people.map(\.id), links: links)
    }

    var body: some View {
        let result = layout
        let scale = zoom * pinch
        // Inside a reader, because where the drawing starts is the whole
        // difference between a family of five and a family of 53. At 53 it is
        // 2376 points wide against a 324-point canvas and 1136 tall against
        // some 625 — seven windows across and two down — so a picture that
        // opens at its own top left corner opens on whoever happens to be
        // oldest. Measured 19 Sep 2026: six of the fifty-three on screen,
        // Hilma and Aapo and half of Lyyli, and the person holding the phone
        // four places across and three rows down, reachable only by scrolling
        // blind in two directions at once.
        ScrollViewReader { reader in
            drawing(result, scale: scale)
                // Once, and without animation: this is where the picture
                // begins rather than somewhere it has been carried.
                .task {
                    guard !opened, let you = yourCardID else { return }
                    show(you, result, reader)
                    opened = true
                }
        }
    }

    /// Everything under the title: the key, the rail beside the drawing, the
    /// drawing itself, and the zoom below all of it.
    private func drawing(_ result: FamilyTreeLayout.Result, scale: CGFloat) -> some View {
        // The bar is below the drawing, not over it. As a `safeAreaInset` it
        // floated on top, and a family of any size always has somebody under
        // it: the audit measured Liisa and Veikko at 1.04:1 on 16 Sep 2026,
        // which is paper on paper — a name that is not dimmed but covered.
        // Everything can still be scrolled into view, and that is exactly the
        // answer that makes a picture worse: you cannot see the tree and the
        // part of it behind the bar at the same time.
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    // Above the drawing, because a key is read before the
                    // picture rather than beside it — and because down in the
                    // fixed bar it cost 150 points of an 874-point screen at
                    // the default text size, for three words nobody needs
                    // twice. It scrolls away with the tree; the rail, which
                    // answers a question you keep asking, does not.
                    legend
                        .padding(.horizontal, Elder.screenPadding)

                    // A reader, so a family narrower than the screen is drawn in
                    // its middle rather than against the left edge. It needs a
                    // height of its own: inside a vertical scroll view nothing
                    // proposes one.
                    HStack(alignment: .top, spacing: 0) {
                        generationRail(result, scale: scale)
                        GeometryReader { proxy in
                            ScrollView(.horizontal) {
                                canvas(result, you: yourCardID)
                                    .scaleEffect(scale, anchor: .topLeading)
                                    .frame(
                                        width: width(of: result) * scale,
                                        height: height(of: result) * scale,
                                        alignment: .topLeading
                                    )
                                    // Which part of the drawing is under the
                                    // window, so the rail can stop naming
                                    // generations over a family its words are
                                    // not about. Taken from the drawing's own
                                    // frame rather than the scroll offset,
                                    // because the frame carries the centring
                                    // of a family narrower than the screen as
                                    // well as the scrolling of one wider.
                                    .background {
                                        GeometryReader { drawing in
                                            let left = -drawing.frame(in: .named(Self.space)).minX
                                            Color.clear.onChange(
                                                of: CGRect(x: left, y: 0,
                                                           width: proxy.size.width, height: 0),
                                                initial: true
                                            ) { _, seen in window = seen }
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        anchors(result, scale: scale)
                                    }
                                    .frame(minWidth: proxy.size.width, alignment: .center)
                            }
                            .coordinateSpace(name: Self.space)
                        }
                    }
                    .frame(height: height(of: result) * scale)
                    .simultaneousGesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = clamped(zoom * value.magnification) }
                    )

                    // Under the tree, not above it. Above, at the largest text size
                    // it took a quarter of the screen and pushed the first
                    // generation down behind the zoom buttons, where the sweep's
                    // tap on the first person never opened the sheet (13 Sep 2026).
                    Text("Napauta ihmistä, niin voit lisätä hänelle sukulaisen.")
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Elder.screenPadding)

                    if !result.undrawn.isEmpty {
                        undrawnNote(result)
                            .padding(.horizontal, Elder.screenPadding)
                    }

                    if heardCount > 0 {
                        heardDoor
                            .padding(.horizontal, Elder.screenPadding)
                    }
                }
                .padding(.vertical, 12)
            }

            // Fixed below the tree rather than scrolling after it. There, every
            // tap moved the buttons down or up by a fifth of the tree, and the
            // next tap in the same place landed on whatever had moved under it —
            // on the first run of the tests, the door to the names heard.
            HStack(spacing: 16) {
                Spacer()
                zoomButtons
            }
            .padding(.horizontal, Elder.screenPadding)
            .padding(.vertical, 4)
            .background(Elder.paper)
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
        .elderSurface()
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

    // MARK: - Drawing

    private func canvas(_ result: FamilyTreeLayout.Result, you: String?) -> some View {
        let yours = yourRow(result)
        return ZStack(alignment: .topLeading) {
            // A band to a generation, every other one, so a row reads as one
            // row across a family too wide to see at once. Counted from your
            // own generation, so yours is always one of the shaded ones and
            // the rail's word for it lands on a band rather than beside one.
            //
            // `Elder.card` on `Elder.paper` measures 1.11:1 — a tint and not
            // an edge, which is what this is for. What matters under rule 1 is
            // what the names measure against it, and primary text on card is
            // 16.81:1 against 15.17:1 on paper: both sides of the stripe are
            // comfortably over the minimum, so no name gets harder to read for
            // being in a shaded generation.
            let band = yourFamily(result)
            ForEach(treeRows(result), id: \.self) { row in
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
            // disc has a paper backing, so a line meets it edge to edge, and
            // every name sits below the height its lines run at.
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

            // In the empty row the layout leaves above the people related to
            // nobody, standing on the bottom of that row so it stays with them
            // at every text size. Shown with no tree above them too: then they
            // are the whole family, and the caption says why nobody is joined.
            if let looseRow = result.looseRow {
                Text("Ei vielä sukupuussa")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        width: width(of: result) - 20,
                        height: captionBand,
                        alignment: .bottomLeading
                    )
                    .offset(x: 10, y: CGFloat(looseRow - 1) * rowHeight)
            }

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

    /// The handholds the reader in `body` scrolls by, and the reason they
    /// exist rather than an `.id` on each person: a place in the drawing is
    /// an `.offset`, which moves what is painted and leaves the layout frame
    /// where it started. Every node therefore reports the drawing's own top
    /// left corner, and a reader handed a person scrolls to the corner it is
    /// already showing. Measured 19 Sep 2026 on a tree that did not move at
    /// all, for anybody.
    ///
    /// So: one empty rectangle per place in the grid, laid out rather than
    /// offset, and over the scaled drawing rather than inside it —
    /// `scaleEffect` is a rendering transform for the same reason, and a grid
    /// measured in scaled points stays true at any zoom. Nothing is drawn and
    /// nothing is read; this is geometry the scroll views can see.
    private func anchors(_ result: FamilyTreeLayout.Result, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0 ..< max(result.rows, 1), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0 ..< Int(max(result.width, 1).rounded(.up)), id: \.self) { column in
                        Color.clear
                            .frame(
                                width: columnWidth * scale,
                                height: (y(ofRow: row + 1, result) - y(ofRow: row, result)) * scale
                            )
                            .id(Self.cell(row: row, column: column))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Puts a person's own column on the screen. A placement's `x` can fall
    /// between two columns — a parent centred over her children — and the
    /// nearest is the one to put in the window.
    ///
    /// Sideways only, and the reason is measured rather than chosen. The
    /// drawing hangs in two scroll views, the sideways one inside the
    /// up-and-down one, and a reader handed an id lying in both moves only
    /// the inner; a second set of handholds beside the rail, outside the
    /// sideways view, drove the other one and worked — the tree opened on
    /// Elina with her parents above her and her daughter below, which is the
    /// picture this was written for.
    ///
    /// It cost the screen its accessibility audit, and not over a colour.
    /// Between the scroll view's fold and the tab bar lie some 52 points that
    /// are on the screen without being in the scroll view: the zoom bar is
    /// drawn there, opaque, and anything the fold cuts off lands behind it,
    /// laid out and painted nowhere. Measured 19 Sep 2026 from the pixels of
    /// the audit's own frames — Saima 1.03:1, Lauri 1.04:1, twelve shades of
    /// paper and no ink in either. The rows repeat every 156 points and a
    /// name is 20 tall, so better than one stopping place in two strands one
    /// there: centring your own row failed at the default text size,
    /// centring the row above it failed at the largest, each passing where
    /// the other failed.
    ///
    /// It is not a fault this morning introduced. One `swipeUp()` added to
    /// the sweep at `e396bfb` fails the same way on a disc cut by the
    /// right-hand edge, so the screen has never passed its audit anywhere but
    /// at rest in its own corner — which, until today, is the only place it was ever
    /// seen. Closing it means the strip cannot hold opaque chrome, and where
    /// the zoom buttons go instead is a question about the screen rather than
    /// about this function. Sideways alone is clean at both text sizes, and
    /// sideways is the larger half: seven windows across against two down.
    private func show(_ person: String, _ result: FamilyTreeLayout.Result, _ reader: ScrollViewProxy) {
        guard let place = result.placements[person] else { return }
        reader.scrollTo(Self.cell(row: place.row, column: Int(place.x.rounded())), anchor: .center)
    }

    private static func cell(row: Int, column: Int) -> String { "cell-\(row)-\(column)" }

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

    private var zoomButtons: some View {
        HStack(spacing: 16) {
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
    }

    /// Which generation each row is, down the left of the drawing.
    ///
    /// The tree drew five discs and some lines and said nothing about what any
    /// row was, and that was the first thing anybody asked of it (16 Sep 2026).
    /// The words are counted from your own row, because that is the only
    /// anchor the archive has: it stores no gender, so a per-person word would
    /// have to read *"Eevan vanhempi"*, while a generation has a name in
    /// Finnish that needs none.
    ///
    /// Not inside the drawing, and not scaled with it: the labels keep their
    /// own size while the tree zooms, so zooming out to see the whole family
    /// leaves the one thing that explains it readable.
    private func generationRail(_ result: FamilyTreeLayout.Result, scale: CGFloat) -> some View {
        let yours = yourRow(result)
        // Counted from your own row, so they are about the picture only while
        // your own family is in it. Scrolled sideways on to a family that
        // shares nobody with yours — which starts at row 0 because neither
        // family knows anything about the other's age — the same words would
        // call its oldest generation your great-grandparents, and nobody
        // entered that. The band under the rows already stops at your family's
        // last column; until now the words did not.
        //
        // The drawing's own numbering, which a phone linked to no card gets,
        // stays where it is: every family starts at row 0, so a row counted
        // from the top of the drawing is as true of one as of another.
        let mine = yours == nil || FamilyTreeLayout.inView(yourFamily(result), columns(at: scale))
        return ZStack(alignment: .topLeading) {
            if mine {
                ForEach(treeRows(result), id: \.self) { row in
                    generationName(row, from: yours)
                        .font(.caption)
                        .fontWeight(row == yours ? .bold : .regular)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: railWidth - 12, alignment: .leading)
                        .offset(x: 6, y: y(ofRow: row, result) * scale + Self.rowInset)
                }
            } else {
                // Not an empty column. The words leaving is the whole point,
                // and a reader who watched them go is owed the reason they
                // went — that these people are not counted from anybody.
                Text("Toinen perhe")
                    .font(.caption)
                    .foregroundStyle(Elder.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: railWidth - 12, alignment: .leading)
                    .offset(x: 6, y: Self.rowInset)
            }
        }
        .frame(width: railWidth, alignment: .topLeading)
    }

    /// The window in the drawing's own units — `x` in person-widths, which is
    /// what an `Extent` is measured in. Everything while nothing has been
    /// measured, so the rail is never missing from a picture at rest.
    private func columns(at scale: CGFloat) -> ClosedRange<Double> {
        guard let window else { return -.greatestFiniteMagnitude ... .greatestFiniteMagnitude }
        // A pinch in progress can hand this a magnification near zero, and a
        // place is never narrower than a point.
        let place = max(columnWidth * scale, 1)
        let first = Double(window.minX / place)
        return first ... max(first, Double(window.maxX / place))
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
        case -3: return Text("Isoisovanhemmat")
        case -2: return Text("Isovanhemmat")
        case -1: return Text("Vanhemmat")
        case 0: return Text("Sinun polvesi")
        case 1: return Text("Lapset")
        case 2: return Text("Lastenlapset")
        case 3: return Text("Lastenlastenlapset")
        case let above where above < 0: return Text("\(-above) polvea ylempänä")
        case let below: return Text("\(below) polvea alempana")
        }
    }

    /// What the lines mean, over the drawing they are in.
    ///
    /// The drawing is a code — two lines for a couple, a bracket down to the
    /// children, a bar over siblings — and until 16 Sep 2026 nothing on the
    /// screen said so. Not under the tree: under the tree is off the bottom of
    /// a family of any size.
    /// One under the other, and not three across a row that folds into a
    /// column when the words outgrow it. `ViewThatFits` was the first shape
    /// and the audit refused it — "Dynamic Type font sizes are partially
    /// unsupported" on all three words, in both tree sweeps, at the default
    /// text size. A column is one arrangement at every size, and it reads as
    /// a key rather than a caption.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendItem(Text("Pariskunta")) { coupleMark }
            legendItem(Text("Lapset")) { descentMark }
            legendItem(Text("Sisarukset")) { siblingMark }
        }
    }

    private func legendItem(_ word: Text, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 6) {
            mark()
                .frame(width: markWidth, alignment: .center)
                .accessibilityHidden(true)
            word
                .font(.caption)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    /// What the archive holds and the drawing cannot say. Everybody is of one
    /// generation in a picture, so a marriage between two of them, or a pair
    /// each entered as the other's parent, leaves a bond with nowhere to go,
    /// and `FamilyTreeLayout` drops the line rather than draw a relationship
    /// nobody entered — which is rule 4, and the easy half of it.
    ///
    /// This is the other half (19 Sep 2026). A line quietly absent is the
    /// picture disagreeing with the cards, and from the drawing alone it looks
    /// exactly like a bond nobody has entered yet — the one reading that sends
    /// somebody off to enter it a second time. Nothing here calls anybody
    /// wrong: the app does not know which of two answers the family meant, and
    /// saying otherwise would be the guess asserted as fact all over again.
    private func undrawnNote(_ result: FamilyTreeLayout.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nämä eivät mahdu kuvaan")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Kuvassa jokainen on yhdessä polvessa, eivätkä nämä siteet mahdu siihen. Ne ovat tallessa kummankin omalla kortilla.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(result.undrawn.enumerated()), id: \.offset) { _, link in
                Text("\(name(link.from)) ja \(name(link.to)) — \(bond(link.kind))")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The name on somebody's card, for a sentence rather than a disc.
    private func name(_ id: String) -> String {
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

    /// The door `PeopleScreen` puts under the list, in the same words. Outside
    /// a list a link draws no chevron of its own, so this one has one.
    private var heardDoor: some View {
        NavigationLink(value: HeardNamesRoute()) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HeardNamesDoorLabel(count: heardCount)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Elder.supporting)
                    .accessibilityHidden(true)
            }
            .elderTapTarget()
        }
        .buttonStyle(.plain)
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
    /// be. The people related to nobody are under the caption and are not a
    /// generation either: nobody has said what they are to anyone.
    private func treeRows(_ result: FamilyTreeLayout.Result) -> [Int] {
        let end = yourFamily(result)?.rows ?? result.looseRow.map { $0 - 1 } ?? result.rows
        return end > 0 ? Array(0 ..< end) : []
    }

    /// The family this phone's card is in, or the first one drawn when it is
    /// in none — which is the family the tree grew from.
    private func yourFamily(_ result: FamilyTreeLayout.Result) -> FamilyTreeLayout.Extent? {
        let index = yourCardID.flatMap { result.family[$0] } ?? 0
        return result.familyExtents.indices.contains(index) ? result.familyExtents[index] : nil
    }

    /// Your own row, when this phone is linked to a card that is in the tree.
    /// Nil when it is not, and nil when your card is one of the people related
    /// to nobody — from down there you are not a generation to count from.
    private func yourRow(_ result: FamilyTreeLayout.Result) -> Int? {
        guard let you = yourCardID, let place = result.placements[you] else { return nil }
        guard result.looseRow.map({ place.row < $0 - 1 }) ?? true else { return nil }
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
        CGFloat(max(result.rows, 1)) * rowHeight - looseTrim(result)
    }

    /// The layout leaves a whole empty generation above the people related to
    /// nobody, for the caption. A generation's height over one line of text is
    /// a hole — 134 points of nothing at the default text size, measured on
    /// 16 Sep 2026 — so everything from the caption down moves up by the
    /// difference and the drawing loses the hole.
    ///
    /// Until then this only happened when the hole was at the very top, with
    /// nobody related at all; under a tree it was left as it was. The tree was
    /// then 468 points tall for five people, a third of it air.
    ///
    /// Nothing above the caption moves, so no line needs a share of it: the
    /// layout draws none below the last generation.
    private func shift(atRow row: Double, _ result: FamilyTreeLayout.Result) -> CGFloat {
        guard let loose = result.looseRow, row >= Double(loose) else { return 0 }
        return looseTrim(result)
    }

    private func looseTrim(_ result: FamilyTreeLayout.Result) -> CGFloat {
        result.looseRow == nil ? 0 : max(0, rowHeight - captionBand)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
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
