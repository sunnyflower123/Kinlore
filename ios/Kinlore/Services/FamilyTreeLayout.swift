import Foundation

/// Where each person goes in the drawn family tree, and the lines between them.
///
/// Pure arithmetic on purpose, with no SwiftUI and no store in it. The drawing
/// is the part a screenshot can check; where somebody lands is the part it
/// cannot — a child placed one row above her mother still draws, and reads as
/// the family upside down. `scripts/family-tree-layout-check.swift` compiles
/// this file on its own and asks exactly those questions.
///
/// Rows are generations, top to bottom. `x` is measured in person-widths, so a
/// couple sits one apart and a gap between two families is one empty place.
/// People related to nobody are placed too, below every family, so the whole
/// family is in one picture (since 13 Sep 2026).
///
/// Only what a human has confirmed should come in (rule 4): a proposal drawn
/// into a picture of the family is the guess shown as fact. The caller filters;
/// this file does not know what a proposal is.
enum FamilyTreeLayout {
    enum Kind: Equatable {
        /// `from` is the parent, `to` the child.
        case parent
        case spouse
        case sibling
    }

    struct Link: Equatable {
        let from: String
        let to: String
        let kind: Kind
    }

    struct Placement: Equatable {
        let row: Int
        let x: Double
    }

    /// What a line between two people means. The drawing tells them apart —
    /// a couple is drawn as two lines, the way a genealogy does it — and a
    /// picture whose lines all look the same cannot be read without being
    /// explained (16 Sep 2026).
    enum SegmentKind: Equatable {
        /// Between the two of a couple, along their own row.
        case couple
        /// From between parents down to a child.
        case descent
        /// The bar over siblings nobody has entered parents for.
        case sibling
    }

    /// A straight line, in the same units as `Placement`: `x` in
    /// person-widths, `y` in rows, with a row's people centred on its integer.
    struct Segment: Equatable {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
        var kind: SegmentKind = .descent
    }

    /// Where one family sits: the places it takes, and how many generations
    /// deep it is. Families share nobody, so these do not overlap.
    struct Extent: Equatable {
        var minX: Double
        var maxX: Double
        var rows: Int
    }

    struct Result: Equatable {
        var placements: [String: Placement] = [:]
        /// Which family each person is in — everybody related to them, however
        /// distantly. **A row is a generation only inside one family.** Two
        /// families that share nobody both start at row 0 because neither
        /// knows anything about the other's age, so drawing them in one band
        /// and calling that band a generation says something nobody entered
        /// (seen on 16 Sep 2026: a couple related to nobody, drawn level with
        /// somebody's great-great-grandparents and labelled as them).
        var family: [String: Int] = [:]
        /// One per family, in the order they are drawn.
        var familyExtents: [Extent] = []
        /// People with no relationship to anybody drawn, in the order given.
        /// They are placed below every family and have no lines.
        var unconnected: [String] = []
        /// The first row of those people. The row above it is left empty for
        /// the screen's caption. Nil when everybody is related to somebody.
        var looseRow: Int?
        var rows = 0
        var width = 0.0
        var segments: [Segment] = []
    }

    /// How far under a row a marriage's line dips when the two cannot be put
    /// side by side. Under the discs, which are a fifth of a row tall, and
    /// above the bracket to the children at half a row.
    private static let roundAbout = 0.25

    static func layout(people: [String], links: [Link]) -> Result {
        var result = Result()

        var unique: [String] = []
        var known = Set<String>()
        for id in people where known.insert(id).inserted { unique.append(id) }

        // Links to nobody in the tree, links from somebody to themself, and
        // the same link twice are dropped before anything is placed.
        var linkKeys = Set<String>()
        var clean: [Link] = []
        for link in links where link.from != link.to && known.contains(link.from) && known.contains(link.to) {
            let pair = [link.from, link.to].sorted().joined(separator: "|")
            let key: String
            switch link.kind {
            case .parent: key = "p:\(link.from)>\(link.to)"
            case .spouse: key = "s:\(pair)"
            case .sibling: key = "b:\(pair)"
            }
            if linkKeys.insert(key).inserted { clean.append(link) }
        }

        var neighbours: [String: [(id: String, delta: Int)]] = [:]
        for link in clean {
            let delta = link.kind == .parent ? 1 : 0
            neighbours[link.from, default: []].append((link.to, delta))
            neighbours[link.to, default: []].append((link.from, -delta))
        }

        // Generations, one family at a time, breadth first from whoever was
        // given first. The first answer a person gets is the one they keep:
        // data that contradicts itself — somebody entered as both the parent
        // and the child of the same person — still places everybody, and loses
        // only the line that disagrees.
        var row: [String: Int] = [:]
        var discovered: [String: Int] = [:]
        var families: [[String]] = []
        for person in unique where row[person] == nil {
            guard neighbours[person] != nil else {
                result.unconnected.append(person)
                continue
            }
            var members: [String] = []
            var queue = [person]
            row[person] = 0
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                discovered[current] = discovered.count
                members.append(current)
                for (other, delta) in neighbours[current] ?? [] where row[other] == nil {
                    row[other] = row[current]! + delta
                    queue.append(other)
                }
            }
            let top = members.compactMap { row[$0] }.min() ?? 0
            for id in members { row[id]! -= top }
            families.append(members)
        }

        // Only relationships that agree with the rows are drawn.
        var parents: [String: [String]] = [:]
        var spouses: [String: [String]] = [:]
        var siblings: [String: [String]] = [:]
        for link in clean {
            guard let from = row[link.from], let to = row[link.to] else { continue }
            switch link.kind {
            case .parent where to == from + 1:
                parents[link.to, default: []].append(link.from)
            case .spouse where to == from:
                spouses[link.from, default: []].append(link.to)
                spouses[link.to, default: []].append(link.from)
            case .sibling where to == from:
                siblings[link.from, default: []].append(link.to)
                siblings[link.to, default: []].append(link.from)
            default:
                continue
            }
        }

        var x: [String: Double] = [:]
        var offset = 0.0
        for (index, members) in families.enumerated() {
            for id in members { result.family[id] = index }
            let depth = (members.compactMap { row[$0] }.max() ?? 0) + 1
            result.rows = max(result.rows, depth)
            var byRow = Array(repeating: [String](), count: depth)
            for id in members.sorted(by: { discovered[$0]! < discovered[$1]! }) {
                byRow[row[id]!].append(id)
            }

            var rightEdge = offset
            for r in 0 ..< depth {
                // A couple is one unit, so the two are never split by a sort —
                // and somebody married more than once is one unit with all of
                // their marriages, standing between them.
                //
                // Any other order draws the second marriage as a line straight
                // through the first wife, and drops that marriage's children
                // from the middle of the couple, which with a wife on each
                // side of him is her own place. The picture then says the two
                // wives are a couple and the second marriage's daughter hangs
                // from the first — neither of which anybody entered. Both were
                // in `-seed clan` until 16 Sep 2026.
                let here = Set(byRow[r])
                func married(_ person: String) -> [String] {
                    (spouses[person] ?? []).filter { here.contains($0) }
                }
                var units: [[String]] = []
                var placed = Set<String>()
                for first in byRow[r] where !placed.contains(first) {
                    // Everybody one chain of marriages joins, in the order the
                    // family reached them, so the walk below is decided by the
                    // archive and not by a dictionary.
                    var group = [first]
                    var found: Set<String> = [first]
                    var head = 0
                    while head < group.count {
                        for partner in married(group[head]) where found.insert(partner).inserted {
                            group.append(partner)
                        }
                        head += 1
                    }
                    let reached = Dictionary(uniqueKeysWithValues: group.enumerated().map { ($0.element, $0.offset) })

                    // From an end of the chain — whoever married fewest — on
                    // to the partner with fewest marriages left, which leaves
                    // the one married twice in the middle. Three marriages are
                    // one more than a row can stand side by side: everybody is
                    // still placed, and the one line that then has to reach
                    // past somebody is bent under the row further down.
                    var unit: [String] = []
                    var taken = Set<String>()
                    func left(_ person: String) -> Int { married(person).filter { !taken.contains($0) }.count }
                    func nearest(_ among: [String]) -> String? {
                        among.min { a, b in left(a) == left(b) ? reached[a]! < reached[b]! : left(a) < left(b) }
                    }
                    var walking = nearest(group)
                    while let person = walking {
                        unit.append(person)
                        taken.insert(person)
                        walking = nearest(married(person).filter { !taken.contains($0) })
                            ?? group.first { !taken.contains($0) }
                    }
                    placed.formUnion(unit)
                    units.append(unit)
                }

                // Each unit wants to sit under its parents — a couple between
                // both sets — and a sibling nobody has entered parents for
                // borrows the parents of a sibling somebody has.
                func wanted(_ unit: [String]) -> Double? {
                    let above = unit.flatMap { parents[$0] ?? [] }.compactMap { x[$0] }
                    if !above.isEmpty { return above.reduce(0, +) / Double(above.count) }
                    let borrowed = unit.flatMap { siblings[$0] ?? [] }.flatMap { parents[$0] ?? [] }.compactMap { x[$0] }
                    if !borrowed.isEmpty { return borrowed.reduce(0, +) / Double(borrowed.count) }
                    return nil
                }

                let ordered = units.enumerated()
                    .map { (index: $0.offset, unit: $0.element, want: wanted($0.element)) }
                    .sorted { a, b in
                        switch (a.want, b.want) {
                        case let (wa?, wb?): return wa == wb ? a.index < b.index : wa < wb
                        case (nil, nil): return a.index < b.index
                        case (.some, nil): return true
                        case (nil, .some): return false
                        }
                    }

                var next = offset
                for entry in ordered {
                    let width = Double(entry.unit.count)
                    // Centred under what it wants, but never over the unit before it.
                    let start = entry.want.map { max(next, $0 - (width - 1) / 2) } ?? next
                    for (i, id) in entry.unit.enumerated() { x[id] = start + Double(i) }
                    next = start + width
                }
                rightEdge = max(rightEdge, next)
            }
            let places = members.compactMap { x[$0] }
            result.familyExtents.append(
                Extent(minX: places.min() ?? offset, maxX: places.max() ?? offset, rows: depth)
            )
            // One empty place between two families that share nobody.
            offset = rightEdge + 1
        }

        result.width = max(0, offset - 1)

        // Everybody related to nobody, below every family and as wide as the
        // tree above them, never fewer than three to a row, with the row above
        // them left empty for the screen's caption — under a tree or, when
        // nobody is related yet, at the top. No lines, because nobody has said
        // who they are to anyone.
        if !result.unconnected.isEmpty {
            let perRow = max(3, Int(result.width.rounded(.up)))
            let first = result.rows + 1
            result.looseRow = first
            for (i, id) in result.unconnected.enumerated() {
                row[id] = first + i / perRow
                x[id] = Double(i % perRow)
            }
            result.rows = first + (result.unconnected.count + perRow - 1) / perRow
            result.width = max(result.width, Double(min(result.unconnected.count, perRow)))
        }

        for (id, value) in x { result.placements[id] = Placement(row: row[id]!, x: value) }

        var segments: [Segment] = []
        var drawn = Set<String>()

        // A couple: one line between the two, through the middle of the row.
        //
        // Unless somebody stands between them, which the row above can only
        // avoid for two marriages of one person and not for three. Then the
        // line dips under the row and goes around her: a line that ran through
        // her would say she is the one married, and a marriage nobody entered
        // is the mistake rule 4 exists to prevent.
        for (id, partners) in spouses {
            for partner in partners {
                let key = "s:" + [id, partner].sorted().joined(separator: "|")
                guard drawn.insert(key).inserted, let a = x[id], let b = x[partner], let r = row[id] else { continue }
                let (left, right) = (min(a, b), max(a, b))
                guard right - left > 1 else {
                    segments.append(Segment(x1: left, y1: Double(r), x2: right, y2: Double(r), kind: .couple))
                    continue
                }
                segments.append(Segment(x1: left, y1: Double(r), x2: left, y2: Double(r) + roundAbout, kind: .couple))
                segments.append(Segment(x1: left, y1: Double(r) + roundAbout, x2: right, y2: Double(r) + roundAbout, kind: .couple))
                segments.append(Segment(x1: right, y1: Double(r) + roundAbout, x2: right, y2: Double(r), kind: .couple))
            }
        }

        // Children, grouped by the parents they share: one bracket per family —
        // down from between the parents, across above the children, and down
        // to each of them.
        var broods: [[String]: [String]] = [:]
        for (child, theirParents) in parents {
            broods[Array(Set(theirParents)).sorted(), default: []].append(child)
        }
        for (theirParents, children) in broods {
            guard let r = row[theirParents[0]] else { continue }
            let above = theirParents.compactMap { x[$0] }
            let below = children.compactMap { x[$0] }
            guard !above.isEmpty, !below.isEmpty else { continue }
            let anchor = above.reduce(0, +) / Double(above.count)
            let middle = Double(r) + 0.5
            // From the parents themselves, or — where their marriage had to
            // bend under the row to get round somebody — from that line, so
            // the children are not hung on the person it went around.
            let top = (above.max()! - above.min()! > 1) ? Double(r) + roundAbout : Double(r)
            segments.append(Segment(x1: anchor, y1: top, x2: anchor, y2: middle))
            let low = min(anchor, below.min()!)
            let high = max(anchor, below.max()!)
            if low < high { segments.append(Segment(x1: low, y1: middle, x2: high, y2: middle)) }
            for childX in below {
                segments.append(Segment(x1: childX, y1: middle, x2: childX, y2: Double(r + 1)))
            }
        }

        // Siblings nobody has entered shared parents for get a bar of their own,
        // above the row, so a brother is not drawn as a stranger.
        for (id, others) in siblings {
            for other in others {
                let key = "b:" + [id, other].sorted().joined(separator: "|")
                guard drawn.insert(key).inserted else { continue }
                if let a = parents[id], let b = parents[other], !Set(a).isDisjoint(with: b) { continue }
                guard let ax = x[id], let bx = x[other], let r = row[id] else { continue }
                let bar = Double(r) - 0.4
                // Both drops run the same way, from the bar down. They ran
                // opposite ways until 13 Sep 2026, and which sibling this loop
                // meets first is a dictionary's order — random per process —
                // so the same family came out as two different lists of lines
                // that draw the same. The layout check caught it, in half of
                // the runs of some processes and none of others.
                segments.append(Segment(x1: ax, y1: bar, x2: ax, y2: Double(r), kind: .sibling))
                segments.append(Segment(x1: min(ax, bx), y1: bar, x2: max(ax, bx), y2: bar, kind: .sibling))
                segments.append(Segment(x1: bx, y1: bar, x2: bx, y2: Double(r), kind: .sibling))
            }
        }

        // Sorted, so the same family always comes out as the same drawing.
        result.segments = segments.sorted { ($0.y1, $0.x1, $0.y2, $0.x2) < ($1.y1, $1.x1, $1.y2, $1.x2) }
        return result
    }
}
