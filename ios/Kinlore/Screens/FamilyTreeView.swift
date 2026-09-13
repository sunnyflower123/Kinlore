import SwiftUI

/// The family drawn as a tree: a generation to a row, a line between a couple,
/// and a bracket from parents down to their children.
///
/// On family members' phones, behind the tree beside the gear on Ihmiset, and
/// nowhere else. A grandparent's phone (the text-floor signal)
/// and VoiceOver keep the relationships as lists on each person's card, where
/// they read at the largest size and aloud — a picture of lines is nothing to
/// read. That was the whole case against drawing the tree when it was cut on
/// 31 Jul 2026 (ARCHITECTURE §8), and it is why the cut was reversed on
/// 13 Sep: the phone it was a trap for no longer sees it, and the person who
/// set the archive up does.
///
/// Confirmed people and confirmed relationships only (rule 4): a proposal in a
/// picture of the family is the guess drawn as fact. Where everybody lands is
/// `FamilyTreeLayout`, checked on its own by
/// `scripts/family-tree-layout-check.swift`; this view only draws it.
struct FamilyTreeView: View {
    @Environment(MemoryStore.self) private var store

    /// Pinch to zoom, and two buttons for a hand that cannot pinch.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    /// One place and one generation, growing with the text inside them, so a
    /// name at a larger size does not run into its neighbour.
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 156
    /// The same base size and text style `SubjectAvatar` scales by, so the
    /// lines can find the middle of each disc at every text size.
    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 48

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
                if result.placements.isEmpty {
                    Text("Sukupuu piirtyy, kun ihmisten korteille lisätään sukulaisia.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Elder.screenPadding)
                } else {
                    // A reader, so a family narrower than the screen is drawn
                    // in its middle rather than against the left edge. It needs
                    // a height of its own: inside a vertical scroll view nothing
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

                    zoomButtons
                        .padding(.horizontal, Elder.screenPadding)
                }

                if !result.unconnected.isEmpty {
                    unconnected(result.unconnected)
                        .padding(.horizontal, Elder.screenPadding)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Sukupuu")
        .elderSurface()
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

            ForEach(people) { person in
                if let place = result.placements[person.id] {
                    // By its top, not its centre: a name that wraps to two
                    // lines must not lift its disc off the line it hangs on.
                    node(person)
                        .offset(
                            x: point(place.x, Double(place.row)).x - nodeWidth / 2,
                            y: CGFloat(place.row) * rowHeight + Self.rowInset
                        )
                }
            }
        }
        .frame(width: width(of: result), height: height(of: result), alignment: .topLeading)
    }

    private func node(_ person: Subject) -> some View {
        NavigationLink(value: person) {
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

    /// People nobody has joined to anyone yet. Not left out, just not in the
    /// picture — and the way into it is on their own card.
    private func unconnected(_ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ei vielä sukupuussa")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(ids, id: \.self) { id in
                if let person = store.subject(id: id) {
                    NavigationLink(value: person) {
                        HStack(spacing: 14) {
                            SubjectAvatar(subject: person)
                            Text(person.displayTitle)
                                .font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Elder.supporting)
                                .accessibilityHidden(true)
                        }
                        .elderTapTarget()
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Lisää sukulainen henkilön kortilta, niin hän tulee puuhun.")
                .font(.subheadline)
                .foregroundStyle(Elder.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        CGFloat(max(result.rows, 1)) * rowHeight
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }
}
