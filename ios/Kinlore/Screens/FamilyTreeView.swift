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

    /// Names heard and not yet checked. The door to them sits under the tree
    /// as it sits under the list, so neither view hides them.
    var heardCount = 0
    /// Opens a person's card. The navigation stack belongs to Ihmiset.
    var onOpen: (Subject) -> Void = { _ in }

    /// Pinch to zoom, and two buttons for a hand that cannot pinch.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

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
    /// The caption's own band above the people related to nobody, when
    /// nobody is related yet and there is no tree above them.
    @ScaledMetric(relativeTo: .headline) private var captionBand: CGFloat = 44

    /// From the top of a generation's row to the top of its discs.
    private static let rowInset: CGFloat = 8

    private static let zoomRange: ClosedRange<CGFloat> = 0.4 ... 2.5

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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                // A reader, so a family narrower than the screen is drawn in
                // its middle rather than against the left edge. It needs a
                // height of its own: inside a vertical scroll view nothing
                // proposes one.
                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        canvas(result)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(
                                width: width(of: result) * scale,
                                height: height(of: result) * scale,
                                alignment: .topLeading
                            )
                            .frame(minWidth: proxy.size.width, alignment: .center)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            zoomButtons
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

    private func canvas(_ result: FamilyTreeLayout.Result) -> some View {
        ZStack(alignment: .topLeading) {
            // Under the people, and through the middle of their discs: every
            // disc has a paper backing, so a line meets it edge to edge, and
            // every name sits below the height its lines run at.
            Canvas { context, _ in
                for segment in result.segments {
                    var path = Path()
                    path.move(to: point(segment.x1, segment.y1))
                    path.addLine(to: point(segment.x2, segment.y2))
                    context.stroke(path, with: .color(Elder.supporting), lineWidth: 2)
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
                        height: rowHeight - Self.rowInset - topTrim(result),
                        alignment: .bottomLeading
                    )
                    .offset(x: 10, y: CGFloat(looseRow - 1) * rowHeight)
            }

            ForEach(people) { person in
                if let place = result.placements[person.id] {
                    // By its top, not its centre: a name that wraps to two
                    // lines must not lift its disc off the line it hangs on.
                    node(person)
                        .offset(
                            x: point(place.x, Double(place.row)).x - nodeWidth / 2,
                            y: CGFloat(place.row) * rowHeight + Self.rowInset - topTrim(result)
                        )
                }
            }
        }
        .frame(width: width(of: result), height: height(of: result), alignment: .topLeading)
    }

    private func node(_ person: Subject) -> some View {
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
            }
            // No card behind the name. A card hid the line between a couple,
            // leaving a dash floating between two names (seen on 13 Sep 2026).
            .frame(width: nodeWidth, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.displayTitle)
    }

    private var zoomButtons: some View {
        HStack(spacing: 16) {
            Spacer()
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
    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: (CGFloat(x) + 0.5) * columnWidth,
            y: CGFloat(y) * rowHeight + Self.rowInset + discSize / 2
        )
    }

    private func width(of result: FamilyTreeLayout.Result) -> CGFloat {
        CGFloat(max(result.width, 1)) * columnWidth
    }

    private func height(of result: FamilyTreeLayout.Result) -> CGFloat {
        CGFloat(max(result.rows, 1)) * rowHeight - topTrim(result)
    }

    /// With nobody related yet there is no tree above the caption, and a whole
    /// generation's height over one line of text is a hole at the top of the
    /// screen, so everything below moves up by the difference. The lines need
    /// no share of it: with nobody related there are none.
    private func topTrim(_ result: FamilyTreeLayout.Result) -> CGFloat {
        result.looseRow == 1 ? max(0, rowHeight - captionBand) : 0
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
