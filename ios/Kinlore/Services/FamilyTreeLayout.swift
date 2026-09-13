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

    /// A straight line, in the same units as `Placement`: `x` in
    /// person-widths, `y` in rows, with a row's people centred on its integer.
    struct Segment: Equatable {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    struct Result: Equatable {
        var placements: [String: Placement] = [:]
        /// People with no relationship to anybody drawn, in the order given.
        /// They are not in the tree; the screen lists them beneath it.
        var unconnected: [String] = []
        var rows = 0
        var width = 0.0
        var segments: [Segment] = []
    }

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
        for members in families {
            let depth = (members.compactMap { row[$0] }.max() ?? 0) + 1
            result.rows = max(result.rows, depth)
            var byRow = Array(repeating: [String](), count: depth)
            for id in members.sorted(by: { discovered[$0]! < discovered[$1]! }) {
                byRow[row[id]!].append(id)
            }

            var rightEdge = offset
            for r in 0 ..< depth {
                // A couple is one unit, so the two are never split by a sort.
                var units: [[String]] = []
                var paired = Set<String>()
                for id in byRow[r] where !paired.contains(id) {
                    paired.insert(id)
                    if let partner = (spouses[id] ?? []).first(where: { byRow[r].contains($0) && !paired.contains($0) }) {
                        paired.insert(partner)
                        units.append([id, partner])
                    } else {
                        units.append([id])
                    }
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
            // One empty place between two families that share nobody.
            offset = rightEdge + 1
        }

        for (id, value) in x { result.placements[id] = Placement(row: row[id]!, x: value) }
        result.width = max(0, offset - 1)

        var segments: [Segment] = []
        var drawn = Set<String>()

        // A couple: one line between the two, through the middle of the row.
        for (id, partners) in spouses {
            for partner in partners {
                let key = "s:" + [id, partner].sorted().joined(separator: "|")
                guard drawn.insert(key).inserted, let a = x[id], let b = x[partner], let r = row[id] else { continue }
                segments.append(Segment(x1: min(a, b), y1: Double(r), x2: max(a, b), y2: Double(r)))
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
            segments.append(Segment(x1: anchor, y1: Double(r), x2: anchor, y2: middle))
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
                segments.append(Segment(x1: ax, y1: Double(r), x2: ax, y2: bar))
                segments.append(Segment(x1: min(ax, bx), y1: bar, x2: max(ax, bx), y2: bar))
                segments.append(Segment(x1: bx, y1: bar, x2: bx, y2: Double(r)))
            }
        }

        // Sorted, so the same family always comes out as the same drawing.
        result.segments = segments.sorted { ($0.y1, $0.x1, $0.y2, $0.x2) < ($1.y1, $1.x1, $1.y2, $1.x2) }
        return result
    }
}
