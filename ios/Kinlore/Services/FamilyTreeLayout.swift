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
        /// Relationships somebody entered that no row can hold, in the order
        /// they were given. A person is of one generation in a drawing, so a
        /// marriage between two generations, or a pair each entered as the
        /// other's parent, leaves a line with nowhere to go, and rule 4 drops
        /// it rather than draw a relationship nobody entered.
        ///
        /// Dropping it is the easy half. Which ones were dropped is the other
        /// half, because a line quietly absent is the picture disagreeing
        /// with the cards and nothing anywhere admitting it (19 Sep 2026).
        var undrawn: [Link] = []
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

    /// How far under a row a marriage's line dips when somebody stands
    /// between the two. Under the names — a card, disc and name, reaches
    /// about two fifths of a row below the centre line (`depth`), and until
    /// 19 Sep 2026 this was a quarter, which ran the dip through the name of
    /// whoever it went round — and above the bracket to the children at half
    /// a row.
    private static let roundAbout = 0.4

    /// How far under a row the bar over a family's children hangs, in rows:
    /// half a row, unless it would meet another bar on the same row.
    ///
    /// Two bars at one height that touch are one bar, and every child on it
    /// reads as every parent's. The first family entered on a phone had a
    /// child of one parent beside a child of two, and the picture said the
    /// second parent was hers too (21 Sep 2026); a couple with three
    /// children next to anybody's one did the same, and 14 683 of 20 000
    /// random families had at least one such pair. So the bars on a row are
    /// dealt out — fewest parents first, then from the left — and each takes
    /// the first of these that no bar it would touch has taken. The order
    /// is what the drawing has room for: the sibling bar of the row below
    /// runs at six tenths, the discs begin at about 0.85, and the third of
    /// these is for a person with children by two others and alone, which
    /// nobody has entered yet.
    private static let broodDepths = [0.5, 0.7, 0.6]

    /// `depth` is how far below a row's centre line a person's card reaches,
    /// in rows: the lower half of the disc, the gap, the name and a little
    /// air under it — and, on the phone's own card, the word *Sinä* under
    /// the name. A line that leaves a person downwards starts there, under
    /// the name, rather than at the centre of the disc and down through the
    /// name (19 Sep 2026). The screen measures it from its own text metrics;
    /// about two fifths of a row is what those come to at every text size,
    /// and is what a caller with no text gets. A card deeper than the
    /// bracket at half a row gets no drop of its own; its children hang from
    /// the bracket alone.
    static func layout(
        people: [String],
        links: [Link],
        depth: (String) -> Double = { _ in 0.38 }
    ) -> Result {
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

        var neighbours: [String: [(id: String, delta: Int, blood: Bool)]] = [:]
        for link in clean {
            let delta = link.kind == .parent ? 1 : 0
            let blood = link.kind != .spouse
            neighbours[link.from, default: []].append((link.to, delta, blood))
            neighbours[link.to, default: []].append((link.from, -delta, blood))
        }

        // Generations, one family at a time, breadth first from whoever was
        // given first. The first answer a person gets is the one they keep:
        // data that contradicts itself — somebody entered as both the parent
        // and the child of the same person — still places everybody, and loses
        // only the line that disagrees.
        //
        // Blood before marriage, since 19 Sep 2026. A parent or a sibling says
        // which generation somebody is of; whom they married does not, and a
        // walk that takes whichever it reaches first decides that by accident.
        // In the fixture's family it decided it wrong: Eemeli took his
        // generation from his wife, landed a row below his own brother, and
        // the brotherhood was the line that went — where the marriage is what
        // crosses two generations and the fixture says so in as many words.
        // A marriage still answers for whoever has no blood relative in the
        // tree at all, which is everybody who married in, and is why it is an
        // order rather than a ban. One person of the fifty-three moves under
        // this rule, onto his brother's row.
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
            // Marriages met along the way, kept until the blood walk has
            // nobody left to reach.
            var married: [(of: String, id: String)] = []
            row[person] = 0
            var head = 0
            var wed = 0
            while head < queue.count || wed < married.count {
                while head < queue.count {
                    let current = queue[head]
                    head += 1
                    discovered[current] = discovered.count
                    members.append(current)
                    for (other, delta, blood) in neighbours[current] ?? [] where row[other] == nil {
                        if blood {
                            row[other] = row[current]! + delta
                            queue.append(other)
                        } else {
                            married.append((current, other))
                        }
                    }
                }
                // One marriage, then back to blood: whoever has just married
                // in may bring a family of their own, and inside that family
                // it is descent that answers again.
                while wed < married.count {
                    let (of, other) = married[wed]
                    wed += 1
                    guard row[other] == nil else { continue }
                    row[other] = row[of]!
                    queue.append(other)
                    break
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
                result.undrawn.append(link)
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
                //
                // A child of one parent, where that parent also has children
                // with somebody on her own row, wants the place beside her
                // on the far side from them (21 Sep 2026). Straight under
                // her, the child's line left from the end of the bar to the
                // other parent, and the first family entered on a phone read
                // Erkko as Antti's and Juhani as Jorma's from exactly that
                // T. Beside her, the bar to the child leaves her line on its
                // own side, at its own height, and nothing else touches it.
                // With a partner on each side of her the child stays under
                // her: that is the one shape a row cannot mend.
                func wanted(_ unit: [String]) -> Double? {
                    let raw = unit.flatMap { parents[$0] ?? [] }
                    let above = raw.compactMap { x[$0] }
                    if !above.isEmpty {
                        if unit.count == 1, Set(raw).count == 1, let only = raw.first, let place = x[only] {
                            let others = parents.values.filter { $0.contains(only) }.flatMap { $0 }
                                .filter { $0 != only && row[$0] == row[only] }.compactMap { x[$0] }
                            let toRight = others.contains { $0 > place }, toLeft = others.contains { $0 < place }
                            if toRight != toLeft { return toRight ? place - 1 : place + 1 }
                        }
                        return above.reduce(0, +) / Double(above.count)
                    }
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

                // Siblings want the same place, their parents', and go down
                // as one block centred under it rather than one at a time
                // from it. One at a time, each began where the one before
                // ended, so a first marriage's second child stood where the
                // second marriage's children start, and the two bars met
                // (21 Sep 2026).
                //
                // The first block may start left of the family's edge — the
                // child beside her parent, with nobody to her left. The
                // whole family is moved right by that much once its rows
                // are placed.
                var next = offset
                if let first = ordered.first, let want = first.want {
                    let width = ordered.prefix { $0.want == want }.reduce(0.0) { $0 + Double($1.unit.count) }
                    next = min(next, want - (width - 1) / 2)
                }
                var i = 0
                while i < ordered.count {
                    let want = ordered[i].want
                    var block = [ordered[i]]
                    while let want, i + block.count < ordered.count, ordered[i + block.count].want == want {
                        block.append(ordered[i + block.count])
                    }
                    let width = block.reduce(0.0) { $0 + Double($1.unit.count) }
                    // Centred under what it wants, but never over the block before it.
                    var start = want.map { max(next, $0 - (width - 1) / 2) } ?? next
                    for entry in block {
                        for (k, id) in entry.unit.enumerated() { x[id] = start + Double(k) }
                        start += Double(entry.unit.count)
                    }
                    next = start
                    i += block.count
                }
                rightEdge = max(rightEdge, next)
            }
            var places = members.compactMap { x[$0] }
            if let leftmost = places.min(), leftmost < offset {
                for id in members { x[id]? += offset - leftmost }
                rightEdge += offset - leftmost
                places = members.compactMap { x[$0] }
            }
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
        /// Whether anybody on a row stands strictly between two places on it.
        func somebodyBetween(_ left: Double, _ right: Double, on r: Int) -> Bool {
            x.contains { row[$0.key] == r && left < $0.value && $0.value < right }
        }

        for (id, partners) in spouses {
            for partner in partners {
                let key = "s:" + [id, partner].sorted().joined(separator: "|")
                guard drawn.insert(key).inserted, let a = x[id], let b = x[partner], let r = row[id] else { continue }
                let (left, right) = (min(a, b), max(a, b))
                // Straight when nobody is in the way. Until 19 Sep 2026 the
                // test was the distance, `right - left > 1`, and a row whose
                // places are means of thirds puts a couple a place and
                // 2⁻⁵² apart: 17 of 30 000 random families bent a marriage
                // under the row round nobody. Whether somebody stands
                // between is the question the dip exists to answer.
                guard somebodyBetween(left, right, on: r) else {
                    segments.append(Segment(x1: left, y1: Double(r), x2: right, y2: Double(r), kind: .couple))
                    continue
                }
                // Down from under each name to the dip. A card deeper than
                // the dip — the phone's own, with *Sinä* under the name —
                // has no leg to draw, and the dip runs along its foot.
                let dip = Double(r) + roundAbout
                for (place, person) in [(a, id), (b, partner)] {
                    let top = Double(r) + min(depth(person), roundAbout)
                    if top < dip {
                        segments.append(Segment(x1: place, y1: top, x2: place, y2: dip, kind: .couple))
                    }
                }
                segments.append(Segment(x1: left, y1: dip, x2: right, y2: dip, kind: .couple))
            }
        }

        // Children, grouped by the parents they share: one bracket per family —
        // down from between the parents, across above the children, and down
        // to each of them.
        var broods: [[String]: [String]] = [:]
        for (child, theirParents) in parents {
            broods[Array(Set(theirParents)).sorted(), default: []].append(child)
        }
        struct Bar {
            let folks: [String]
            let below: [Double]
            let row: Int
            let wed: Bool
            let low: Double
            let high: Double
        }
        var bars: [Bar] = []
        for (theirParents, children) in broods {
            guard let r = row[theirParents[0]] else { continue }
            let above = theirParents.compactMap { x[$0] }
            let below = children.compactMap { x[$0] }
            guard !above.isEmpty, !below.isEmpty else { continue }
            // From between the parents when the archive has them as a
            // couple; from under each parent's own name otherwise.
            let wed = theirParents.count == 2
                && spouses[theirParents[0]]?.contains(theirParents[1]) == true
            let reach = wed ? [above.reduce(0, +) / Double(above.count)] : above
            bars.append(Bar(folks: theirParents, below: below, row: r, wed: wed,
                            low: (below + reach).min()!, high: (below + reach).max()!))
        }
        // Dealt in a fixed order, so the same family is always the same
        // drawing: fewest parents first, then from the left.
        bars.sort { a, b in
            (a.folks.count, a.low, a.high, a.folks.joined(separator: "|"))
                < (b.folks.count, b.low, b.high, b.folks.joined(separator: "|"))
        }
        var hangs: [Double] = []
        for (i, bar) in bars.enumerated() {
            let taken = bars.indices.filter { j in
                j < i && bars[j].row == bar.row && bars[j].low <= bar.high && bar.low <= bars[j].high
            }.map { hangs[$0] }
            hangs.append(broodDepths.first { !taken.contains($0) } ?? broodDepths.last!)
        }
        for (i, bar) in bars.enumerated() {
            let r = bar.row
            let hang = Double(r) + hangs[i]
            // From between the parents when the archive has them as a
            // couple: from their line, or — where it had to dip under the
            // row to get round somebody — from the dip, so the children are
            // not hung on the person it went round.
            //
            // From under each parent's own name otherwise (19 Sep 2026): one
            // parent entered and no other, or two nobody has entered as a
            // couple. The first family somebody entered on a phone was both
            // — a child from each parent and no marriage, which rule 4 will
            // not infer — and its children hung from the empty space between
            // two people the picture had not joined, while a child of one
            // parent hung from a line run down through her name.
            if bar.wed {
                let above = bar.folks.compactMap { x[$0] }
                let anchor = above.reduce(0, +) / Double(above.count)
                let top = somebodyBetween(above.min()!, above.max()!, on: r) ? Double(r) + roundAbout : Double(r)
                segments.append(Segment(x1: anchor, y1: top, x2: anchor, y2: hang))
            } else {
                for parent in bar.folks {
                    guard let place = x[parent], row[parent] == r else { continue }
                    let top = Double(r) + min(depth(parent), hangs[i])
                    if top < hang {
                        segments.append(Segment(x1: place, y1: top, x2: place, y2: hang))
                    }
                }
            }
            if bar.low < bar.high { segments.append(Segment(x1: bar.low, y1: hang, x2: bar.high, y2: hang)) }
            for childX in bar.below {
                segments.append(Segment(x1: childX, y1: hang, x2: childX, y2: Double(r + 1)))
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

    /// Whether any of a family is inside the part of the drawing on screen.
    ///
    /// The screen's generation rail is one column for the whole picture and
    /// deliberately does not scroll with the drawing — a label that scrolls
    /// away names the rows you are no longer looking at. The cost of that is
    /// this question: its words are counted from your own row, so scrolled
    /// sideways on to a family that shares nobody with yours they go on
    /// standing beside people they are not about. Both families start at row 0
    /// because neither knows anything about the other's age, so *Isovanhemmat*
    /// beside the other one's oldest generation is a relationship nobody
    /// entered — the same fault as a marriage drawn through a third person,
    /// and the same rule against it (rule 4).
    ///
    /// `visible` is in the same units as `Placement`: `x` in person-widths,
    /// with a place running from its own integer to the next. Touching counts
    /// as visible, so the words stay while the last column of your family is
    /// still under the window.
    static func inView(_ family: Extent?, _ visible: ClosedRange<Double>) -> Bool {
        guard let family else { return false }
        return family.minX <= visible.upperBound && visible.lowerBound <= family.maxX + 1
    }
}
