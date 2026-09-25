import Foundation

/// Where every card of the family tree stands, and every line between them.
///
/// Rebuilt from zero on 25 Sep 2026, against a specification that carries the
/// first engine's lessons as rules rather than as code. Each rule is here
/// because breaking it was silent — the picture still drew, and said
/// something false:
///
/// - **Rows are generations per family, and every family starts at row 0.**
///   Two families that share nobody know nothing about each other's age; a
///   couple related to nobody was once drawn level with somebody's
///   great-great-grandparents and read as them.
/// - **The earlier link wins.** A marriage across generations, or two people
///   each entered as the other's parent, cannot be held by any rows. The later
///   link is handed back in `undrawn` for the screen to name, and draws no
///   line: a line would assert it.
/// - **Two bars on one row that overlap never share a height.** A shared
///   height reads as one bar, and every child on it as every parent's —
///   14 683 of 20 000 random families did that once.
/// - **No line crosses a third person's card.** A couple line dips under
///   whoever stands between the two, and a stem starts below the name it
///   leaves; otherwise the drawing marries somebody nobody entered.
///
/// How: rows come from a weighted union-find over the links in input order.
/// The order along each row comes from barycentric sweeps over rigid spouse
/// chains, keeping a union's children, a sibling bar's members and a union's
/// unmarried parents in one run. The x positions come from isotonic
/// regression per row (pool adjacent violators) — the least-squares answer to
/// "centre these under that" when nobody may overlap — finished on the
/// half-person grid.
///
/// Flat index arrays rather than dictionaries in every loop, because
/// `scripts/family-tree-layout-check.swift` compiles this file without
/// optimisation and lays out tens of thousands of random families with it.
/// That check holds every rule above.
enum FamilyTreeLayout {
    /// The three kinships a tree draws. A friendship is not one: it is handed
    /// in as `friends`, never as a link.
    enum Bond: Equatable { case parent /* from is the parent of to */, spouse, sibling }

    struct Link: Hashable {
        let from: String
        let to: String
        let bond: Bond
    }

    struct Place: Equatable {
        let row: Int
        let x: Double
    }

    enum Stroke: Equatable {
        case couple    // along a couple's own row (or dipping under it round somebody)
        case descent   // stem, bar and drops from parents to their children
        case sibling   // the bar above siblings nobody has entered parents for
    }

    /// A straight line in the same units as `Place`: x in person-widths,
    /// y in rows (row centre = integer).
    struct Line: Equatable {
        let x1: Double, y1: Double, x2: Double, y2: Double
        let stroke: Stroke
    }

    /// One connected family (two or more people joined by kinship links).
    struct Family: Equatable {
        let members: [String]   // sorted by id
        let minX: Double
        let maxX: Double
        let topRow: Int         // its first row (0 for every family, see R2)
        let rows: Int           // how many generations it spans
    }

    struct Result: Equatable {
        var places: [String: Place] = [:]     // EVERY id in `people`
        var lines: [Line] = []
        var families: [Family] = []           // drawing order, left to right
        var undrawn: [Link] = []              // entered, no row could hold them (input order, deduplicated)
        var friends: [String] = []            // drawn on the friends band, input order
        var friendsRow: Int?                  // first row of that band; the row above it is empty (caption)
        var loose: [String] = []              // related to nobody, input order
        var looseRow: Int?                    // first row of them; the row above it is empty (caption)
        var rows: Int = 0                     // total rows including caption rows and bands
        var width: Double = 0                 // max x + 1 over everybody (leftmost person is at x = 0)
        var captionRows: [Int] { [friendsRow, looseRow].compactMap { $0.map { $0 - 1 } } }
    }

    /// `people`: every confirmed person, in the caller's order (oldest card
    ///   first) — the tie-breaker wherever the picture has a choice.
    /// `links`: confirmed kinship links; may repeat, may contradict, may name
    ///   ids not in `people` (those are ignored).
    /// `friends`: ids joined to the family by friendship alone. One that
    ///   also has a kinship link is placed by the kinship and ignored here.
    /// `root`: whose phone this is — their family is drawn first (leftmost);
    ///   nil when the phone is linked to no card.
    /// `depth`: how far below a row's centre a person's card reaches, in
    ///   rows (disc, gap, name — and *Sinä* on the root's card), so that a
    ///   line leaving somebody downwards starts under their name and not
    ///   through it. Typical value 0.38; the root's about 0.5.
    static func layout(
        people: [String],
        links: [Link],
        friends: [String],
        root: String?,
        depth: (String) -> Double
    ) -> Result {
        var result = Result()

        // Everybody once, in the caller's order. A repeated id is the same
        // card, not a second one (R1).
        var index: [String: Int] = [:]
        index.reserveCapacity(people.count)
        var ids: [String] = []
        ids.reserveCapacity(people.count)
        var i = 0
        while i < people.count {
            let id = people[i]
            if index[id] == nil {
                index[id] = ids.count
                ids.append(id)
            }
            i += 1
        }
        let n = ids.count
        if n == 0 { return result }

        // Generations, the earlier link winning (R3). A link to an unknown id
        // or from somebody to themselves is ignored like one to nobody: it
        // names no second card that a row could or could not hold.
        var generations = Generations(count: n)
        var seen = Set<Int>(minimumCapacity: links.count)
        var kin = [Bool](repeating: false, count: n)
        var drawnFrom: [Int] = [], drawnTo: [Int] = [], drawnBond: [Int] = []
        drawnFrom.reserveCapacity(links.count)
        drawnTo.reserveCapacity(links.count)
        drawnBond.reserveCapacity(links.count)
        i = 0
        while i < links.count {
            let link = links[i]
            i += 1
            guard let a = index[link.from], let b = index[link.to], a != b else { continue }
            kin[a] = true
            kin[b] = true
            let bond = link.bond == .parent ? 0 : link.bond == .spouse ? 1 : 2
            let key = bond == 0 ? (a * n + b) * 3 : (min(a, b) * n + max(a, b)) * 3 + bond
            if !seen.insert(key).inserted { continue }
            if generations.hold(a, b, rise: bond == 0 ? 1 : 0) {
                drawnFrom.append(a)
                drawnTo.append(b)
                drawnBond.append(bond)
            } else {
                result.undrawn.append(link)
            }
        }

        // Families: connected by kinship, numbered by their earliest card. A
        // link the rows could not hold never joins two families — it failed
        // precisely because both ends were already in one.
        var familyOf = [Int](repeating: -1, count: n)
        var familyOfTop = [Int](repeating: -1, count: n)
        var level = [Int](repeating: 0, count: n)
        var familyCount = 0
        var p = 0
        while p < n {
            if kin[p] {
                let (top, row) = generations.find(p)
                level[p] = row
                if familyOfTop[top] < 0 {
                    familyOfTop[top] = familyCount
                    familyCount += 1
                }
                familyOf[p] = familyOfTop[top]
            }
            p += 1
        }

        var memberStart = [Int](repeating: 0, count: familyCount + 1)
        p = 0
        while p < n {
            if kin[p] { memberStart[familyOf[p] + 1] += 1 }
            p += 1
        }
        var f = 0
        while f < familyCount {
            memberStart[f + 1] += memberStart[f]
            f += 1
        }
        var members = [Int](repeating: 0, count: memberStart[familyCount])
        var cursor = memberStart
        p = 0
        while p < n {
            if kin[p] {
                members[cursor[familyOf[p]]] = p
                cursor[familyOf[p]] += 1
            }
            p += 1
        }

        var linkStart = [Int](repeating: 0, count: familyCount + 1)
        var l = 0
        while l < drawnFrom.count {
            linkStart[familyOf[drawnFrom[l]] + 1] += 1
            l += 1
        }
        f = 0
        while f < familyCount {
            linkStart[f + 1] += linkStart[f]
            f += 1
        }
        var familyLinks = [Int](repeating: 0, count: drawnFrom.count)
        cursor = linkStart
        l = 0
        while l < drawnFrom.count {
            let g = familyOf[drawnFrom[l]]
            familyLinks[cursor[g]] = l
            cursor[g] += 1
            l += 1
        }

        // The root's family first, then by the earliest card (R2).
        var drawing = [Int](repeating: 0, count: familyCount)
        f = 0
        while f < familyCount {
            drawing[f] = f
            f += 1
        }
        if let root, let r = index[root], kin[r] {
            var k = familyOf[r]
            while k > 0 {
                drawing[k] = drawing[k - 1]
                k -= 1
            }
            drawing[0] = familyOf[r]
        }

        // Families side by side, one empty place between them, each from row 0.
        var local = [Int](repeating: -1, count: n)
        var left = 0.0
        var familyRows = 0
        var familyWidth = 0.0
        result.places.reserveCapacity(n)
        var d = 0
        while d < familyCount {
            let g = drawing[d]
            let s = memberStart[g], count = memberStart[g + 1] - s
            var top = Int.max
            var depths = [Double](repeating: 0, count: count)
            var k = 0
            while k < count {
                let q = members[s + k]
                local[q] = k
                if level[q] < top { top = level[q] }
                depths[k] = depth(ids[q])
                k += 1
            }
            var rows = [Int](repeating: 0, count: count)
            k = 0
            while k < count {
                rows[k] = level[members[s + k]] - top
                k += 1
            }
            let ls = linkStart[g], lc = linkStart[g + 1] - ls
            var from = [Int](repeating: 0, count: lc)
            var to = [Int](repeating: 0, count: lc)
            var bond = [Int](repeating: 0, count: lc)
            k = 0
            while k < lc {
                let q = familyLinks[ls + k]
                from[k] = local[drawnFrom[q]]
                to[k] = local[drawnTo[q]]
                bond[k] = drawnBond[q]
                k += 1
            }

            var sketch = Sketch(row: rows, depth: depths, from: from, to: to, bond: bond)
            sketch.arrange()

            var names = [String](repeating: "", count: count)
            var right = 0.0
            k = 0
            while k < count {
                let x = sketch.x[k] + left
                result.places[ids[members[s + k]]] = Place(row: rows[k], x: x)
                names[k] = ids[members[s + k]]
                if x > right { right = x }
                k += 1
            }
            sketch.draw(shift: left, into: &result.lines)
            names.sort()
            result.families.append(
                Family(members: names, minX: left, maxX: right, topRow: 0, rows: sketch.rows)
            )
            if sketch.rows > familyRows { familyRows = sketch.rows }
            familyWidth = right + 1
            left = right + 2
            d += 1
        }

        // Friends, then everybody related to nobody, each band under an empty
        // caption row and wrapped at the families' width (R8).
        var friendly = [Bool](repeating: false, count: n)
        i = 0
        while i < friends.count {
            if let q = index[friends[i]], !kin[q], !friendly[q] {
                friendly[q] = true
                result.friends.append(ids[q])
            }
            i += 1
        }
        p = 0
        while p < n {
            if !kin[p] && !friendly[p] { result.loose.append(ids[p]) }
            p += 1
        }
        let wrap = max(3, Int(familyWidth.rounded(.up)))
        var nextRow = familyRows
        var width = familyWidth
        func band(_ band: [String]) -> Int? {
            if band.isEmpty { return nil }
            let first = nextRow + 1
            var k = 0
            while k < band.count {
                result.places[band[k]] = Place(row: first + k / wrap, x: Double(k % wrap))
                k += 1
            }
            nextRow = first + (band.count + wrap - 1) / wrap
            width = max(width, Double(min(band.count, wrap)))
            return first
        }
        result.friendsRow = band(result.friends)
        result.looseRow = band(result.loose)
        result.rows = nextRow
        result.width = width
        return result
    }
}

/// How far below its parents' row a bar hangs, in the order they are dealt.
/// The first three are the specification's. The rest halve the gaps between
/// 0.5 and 0.7, because four unions of one person can overlap each other on a
/// row, and three heights cannot keep four bars apart (25 Sep 2026).
private let hangs: [Double] = {
    var values = [0.5, 0.7, 0.6]
    var step = 0.05
    var level = 0
    while level < 5 {
        var odd = 1.0
        while step * odd < 0.2 - 1e-9 {
            values.append(0.5 + step * odd)
            odd += 2
        }
        step /= 2
        level += 1
    }
    return values
}()

/// Rows by weighted union-find: `offset[i]` is i's row minus its parent's, so
/// holding a link is one comparison, and the first link to fix two people's
/// rows relative to each other is the one that stays (R3).
private struct Generations {
    private var up: [Int]
    private var offset: [Int]
    private var size: [Int]

    init(count: Int) {
        up = [Int](repeating: 0, count: count)
        offset = [Int](repeating: 0, count: count)
        size = [Int](repeating: 1, count: count)
        var i = 0
        while i < count {
            up[i] = i
            i += 1
        }
    }

    /// The component's representative, and `i`'s row relative to it.
    mutating func find(_ i: Int) -> (root: Int, row: Int) {
        var root = i, total = 0
        while up[root] != root {
            total += offset[root]
            root = up[root]
        }
        var j = i, remaining = total
        while up[j] != j {
            let next = up[j], step = offset[j]
            up[j] = root
            offset[j] = remaining
            remaining -= step
            j = next
        }
        return (root, total)
    }

    /// Records row(b) = row(a) + rise, unless the rows already say otherwise.
    mutating func hold(_ a: Int, _ b: Int, rise: Int) -> Bool {
        let (ra, oa) = find(a), (rb, ob) = find(b)
        if ra == rb { return ob - oa == rise }
        let shift = oa + rise - ob
        if size[ra] >= size[rb] {
            up[rb] = ra
            offset[rb] = shift
            size[ra] += size[rb]
        } else {
            up[ra] = rb
            offset[ra] = -shift
            size[rb] += size[ra]
        }
        return true
    }
}

/// One family, in local indices: member k is the family's k-th card in
/// `people` order, so comparing two indices compares two cards — which is how
/// every tie below is broken without looking at the order links came in (R7).
private struct Sketch {
    let rows: Int
    let row: [Int]
    let depth: [Double]
    private(set) var x: [Double]

    // Kinship, each list sorted by local index.
    private var spouseStart: [Int] = [], spouses: [Int] = []
    private var parentStart: [Int] = [], parents: [Int] = []

    // Unions: the set of parents a group of children shares.
    private var unionCount = 0
    private var unionOf: [Int] = []
    private var unionParentStart: [Int] = [0], unionParents: [Int] = []
    private var unionChildStart: [Int] = [], unionChildren: [Int] = []
    private var unionRow: [Int] = []
    private var unionCouple: [Bool] = []
    private var unionChildGroup: [Int] = []
    private var unionBlockStart: [Int] = [0], unionBlocks: [Int] = []
    private var parentUnionStart: [Int] = [], parentUnions: [Int] = []
    private var rowUnionStart: [Int] = [], rowUnions: [Int] = []

    // Sibling bars: siblings the descent does not already show as siblings.
    private var barCount = 0
    private var barStart: [Int] = [0], barMembers: [Int] = []
    private var barRow: [Int] = []
    private var rowBarStart: [Int] = [], rowBars: [Int] = []

    // Blocks: spouse chains, which move as one.
    private var blockCount = 0
    private var blockOf: [Int] = [], slot: [Int] = []
    private var blockStart: [Int] = [0], blockMembers: [Int] = []
    private var blockRow: [Int] = []
    private var rowStart: [Int] = [], rowBlocks: [Int] = []
    private var visited: [Bool] = []

    // Groups: blocks that should stand in one run. Clusters: blocks joined by
    // groups, which always do.
    private var groupCount = 0
    private var groupStart: [Int] = [0], groupBlocks: [Int] = []
    private var groupRow: [Int] = []
    private var blockGroupStart: [Int] = [], blockGroups: [Int] = []
    private var rowGroupStart: [Int] = [], rowGroups: [Int] = []
    private var clusterOf: [Int] = []

    // Scratch, allocated once per family.
    private var placed: [Bool] = []
    private var at: [Int] = [], before: [Int] = [], packed: [Int] = []
    private var acc: [Double] = [], wsum: [Double] = [], yv: [Double] = []
    private var weighted: [Bool] = []
    private var key: [Double] = [], hasKey: [Bool] = [], current: [Double] = [], rank: [Double] = []
    private var cSum: [Double] = [], cN: [Double] = [], cCur: [Double] = [], cCount: [Double] = []
    private var cKey: [Double] = []
    private var gKey: [Double] = [], gRank: [Double] = [], gOrder: [Int] = []
    private var list: [Int] = [], prevW: [Int] = [], nextW: [Int] = []
    private var poolValue: [Double] = [], poolWeight: [Double] = [], poolSize: [Int] = []
    private var memberKey: [Double] = [], memberHas: [Bool] = []

    /// How hard an unpulled block holds on to where it stood. Small enough to
    /// give way to anybody who is pulled, large enough to stop it drifting.
    private static let inertia = 0.01

    init(row: [Int], depth: [Double], from: [Int], to: [Int], bond: [Int]) {
        let m = row.count
        self.row = row
        self.depth = depth
        var top = 0
        var k = 0
        while k < m {
            if row[k] > top { top = row[k] }
            k += 1
        }
        rows = top + 1
        x = [Double](repeating: 0, count: m)
        link(m, from, to, bond)
        gatherUnions(m)
        gatherBars(m, from, to, bond)
        buildBlocks(m)
        buildGroups()

        placed = [Bool](repeating: false, count: rows)
        at = [Int](repeating: 0, count: blockCount)
        before = at
        packed = at
        list = at
        prevW = at
        nextW = at
        poolSize = at
        acc = [Double](repeating: 0, count: blockCount)
        wsum = acc
        yv = acc
        key = acc
        current = acc
        rank = acc
        poolValue = acc
        poolWeight = acc
        weighted = [Bool](repeating: false, count: blockCount)
        hasKey = weighted
        cSum = acc
        cN = acc
        cCur = acc
        cCount = acc
        cKey = acc
        gKey = [Double](repeating: 0, count: groupCount)
        gRank = gKey
        gOrder = [Int](repeating: 0, count: groupCount)
        memberKey = [Double](repeating: 0, count: m)
        memberHas = [Bool](repeating: false, count: m)
    }

    // MARK: - Structure

    private mutating func link(_ m: Int, _ from: [Int], _ to: [Int], _ bond: [Int]) {
        spouseStart = [Int](repeating: 0, count: m + 1)
        parentStart = [Int](repeating: 0, count: m + 1)
        var l = 0
        while l < bond.count {
            if bond[l] == 0 {
                parentStart[to[l] + 1] += 1
            } else if bond[l] == 1 {
                spouseStart[from[l] + 1] += 1
                spouseStart[to[l] + 1] += 1
            }
            l += 1
        }
        var k = 0
        while k < m {
            spouseStart[k + 1] += spouseStart[k]
            parentStart[k + 1] += parentStart[k]
            k += 1
        }
        spouses = [Int](repeating: 0, count: spouseStart[m])
        parents = [Int](repeating: 0, count: parentStart[m])
        var spouseFill = spouseStart, parentFill = parentStart
        l = 0
        while l < bond.count {
            let a = from[l], b = to[l]
            if bond[l] == 0 {
                parents[parentFill[b]] = a
                parentFill[b] += 1
            } else if bond[l] == 1 {
                spouses[spouseFill[a]] = b
                spouseFill[a] += 1
                spouses[spouseFill[b]] = a
                spouseFill[b] += 1
            }
            l += 1
        }
        k = 0
        while k < m {
            Sketch.sort(&spouses, spouseStart[k], spouseStart[k + 1])
            Sketch.sort(&parents, parentStart[k], parentStart[k + 1])
            k += 1
        }
    }

    private static func sort(_ a: inout [Int], _ s: Int, _ e: Int) {
        var i = s + 1
        while i < e {
            let v = a[i]
            var j = i - 1
            while j >= s && a[j] > v {
                a[j + 1] = a[j]
                j -= 1
            }
            a[j + 1] = v
            i += 1
        }
    }

    private func isSpouse(_ a: Int, _ b: Int) -> Bool {
        var k = spouseStart[a]
        while k < spouseStart[a + 1] {
            if spouses[k] == b { return true }
            k += 1
        }
        return false
    }

    private func shareParent(_ a: Int, _ b: Int) -> Bool {
        var i = parentStart[a], j = parentStart[b]
        while i < parentStart[a + 1] && j < parentStart[b + 1] {
            if parents[i] == parents[j] { return true }
            if parents[i] < parents[j] { i += 1 } else { j += 1 }
        }
        return false
    }

    private func sameParents(_ u: Int, _ s: Int, _ e: Int) -> Bool {
        let us = unionParentStart[u]
        if unionParentStart[u + 1] - us != e - s { return false }
        var k = 0
        while k < e - s {
            if unionParents[us + k] != parents[s + k] { return false }
            k += 1
        }
        return true
    }

    /// Groups children by the exact set of parents entered for them. A child
    /// with one parent entered and a sibling with two are two unions: the
    /// archive does not know they share the second.
    private mutating func gatherUnions(_ m: Int) {
        unionOf = [Int](repeating: -1, count: m)
        var latest = [Int](repeating: -1, count: m)
        var earlier: [Int] = []
        var c = 0
        while c < m {
            let s = parentStart[c], e = parentStart[c + 1]
            if s < e {
                var u = latest[parents[s]]
                while u >= 0 && !sameParents(u, s, e) { u = earlier[u] }
                if u < 0 {
                    u = unionCount
                    unionCount += 1
                    earlier.append(latest[parents[s]])
                    latest[parents[s]] = u
                    var k = s
                    while k < e {
                        unionParents.append(parents[k])
                        k += 1
                    }
                    unionParentStart.append(unionParents.count)
                    unionRow.append(row[c] - 1)
                }
                unionOf[c] = u
            }
            c += 1
        }

        unionChildStart = [Int](repeating: 0, count: unionCount + 1)
        c = 0
        while c < m {
            if unionOf[c] >= 0 { unionChildStart[unionOf[c] + 1] += 1 }
            c += 1
        }
        var u = 0
        while u < unionCount {
            unionChildStart[u + 1] += unionChildStart[u]
            u += 1
        }
        unionChildren = [Int](repeating: 0, count: unionChildStart[unionCount])
        var fill = unionChildStart
        c = 0
        while c < m {
            let v = unionOf[c]
            if v >= 0 {
                unionChildren[fill[v]] = c
                fill[v] += 1
            }
            c += 1
        }

        unionCouple = [Bool](repeating: false, count: unionCount)
        parentUnionStart = [Int](repeating: 0, count: m + 1)
        rowUnionStart = [Int](repeating: 0, count: rows + 1)
        u = 0
        while u < unionCount {
            let s = unionParentStart[u], e = unionParentStart[u + 1]
            unionCouple[u] = e - s == 2 && isSpouse(unionParents[s], unionParents[s + 1])
            var k = s
            while k < e {
                parentUnionStart[unionParents[k] + 1] += 1
                k += 1
            }
            rowUnionStart[unionRow[u] + 1] += 1
            u += 1
        }
        c = 0
        while c < m {
            parentUnionStart[c + 1] += parentUnionStart[c]
            c += 1
        }
        var r = 0
        while r < rows {
            rowUnionStart[r + 1] += rowUnionStart[r]
            r += 1
        }
        parentUnions = [Int](repeating: 0, count: parentUnionStart[m])
        rowUnions = [Int](repeating: 0, count: unionCount)
        var parentFill = parentUnionStart, rowFill = rowUnionStart
        u = 0
        while u < unionCount {
            var k = unionParentStart[u]
            while k < unionParentStart[u + 1] {
                let v = unionParents[k]
                parentUnions[parentFill[v]] = u
                parentFill[v] += 1
                k += 1
            }
            rowUnions[rowFill[unionRow[u]]] = u
            rowFill[unionRow[u]] += 1
            u += 1
        }
    }

    /// Sibling links the descent does not already show: siblings who share an
    /// entered parent hang from the same bar and need nothing more, and every
    /// other sibling link joins a bar above the row (R6).
    private mutating func gatherBars(_ m: Int, _ from: [Int], _ to: [Int], _ bond: [Int]) {
        // Union by the smaller index, so each component's root is its earliest card.
        var up = [Int](repeating: 0, count: m)
        var k = 0
        while k < m {
            up[k] = k
            k += 1
        }
        var l = 0
        while l < bond.count {
            if bond[l] == 2 && !shareParent(from[l], to[l]) {
                var a = from[l], b = to[l]
                while up[a] != a { a = up[a] }
                while up[b] != b { b = up[b] }
                if a < b { up[b] = a } else if b < a { up[a] = b }
            }
            l += 1
        }
        var size = [Int](repeating: 0, count: m)
        var rootOf = [Int](repeating: 0, count: m)
        k = 0
        while k < m {
            var r = k
            while up[r] != r { r = up[r] }
            rootOf[k] = r
            size[r] += 1
            k += 1
        }
        var barOfRoot = [Int](repeating: -1, count: m)
        var barOf = [Int](repeating: -1, count: m)
        k = 0
        while k < m {
            let r = rootOf[k]
            if size[r] >= 2 {
                if barOfRoot[r] < 0 {
                    barOfRoot[r] = barCount
                    barCount += 1
                    barRow.append(row[k])
                }
                barOf[k] = barOfRoot[r]
            }
            k += 1
        }
        barStart = [Int](repeating: 0, count: barCount + 1)
        k = 0
        while k < m {
            if barOf[k] >= 0 { barStart[barOf[k] + 1] += 1 }
            k += 1
        }
        var g = 0
        while g < barCount {
            barStart[g + 1] += barStart[g]
            g += 1
        }
        barMembers = [Int](repeating: 0, count: barStart[barCount])
        var fill = barStart
        k = 0
        while k < m {
            let b = barOf[k]
            if b >= 0 {
                barMembers[fill[b]] = k
                fill[b] += 1
            }
            k += 1
        }
        rowBarStart = [Int](repeating: 0, count: rows + 1)
        g = 0
        while g < barCount {
            rowBarStart[barRow[g] + 1] += 1
            g += 1
        }
        var r = 0
        while r < rows {
            rowBarStart[r + 1] += rowBarStart[r]
            r += 1
        }
        rowBars = [Int](repeating: 0, count: barCount)
        var rowFill = rowBarStart
        g = 0
        while g < barCount {
            rowBars[rowFill[barRow[g]]] = g
            rowFill[barRow[g]] += 1
            g += 1
        }
    }

    /// Spouse chains. Somebody married more than once stands between their
    /// first two spouses in `people` order — not the first two links entered,
    /// which would let link order move people (R7) — and any further spouse
    /// stands beyond them, the couple line dipping under whoever is between.
    private mutating func buildBlocks(_ m: Int) {
        blockOf = [Int](repeating: -1, count: m)
        slot = [Int](repeating: 0, count: m)
        visited = [Bool](repeating: false, count: m)
        var v = 0
        while v < m {
            if blockOf[v] < 0 {
                let b = blockRow.count
                if spouseStart[v + 1] > spouseStart[v] {
                    let chain = extend(v, from: -1)
                    var t = 0
                    while t < chain.count {
                        blockOf[chain[t]] = b
                        slot[chain[t]] = t
                        blockMembers.append(chain[t])
                        t += 1
                    }
                } else {
                    blockOf[v] = b
                    visited[v] = true
                    blockMembers.append(v)
                }
                blockStart.append(blockMembers.count)
                blockRow.append(row[v])
            }
            v += 1
        }
        blockCount = blockRow.count

        rowStart = [Int](repeating: 0, count: rows + 1)
        var b = 0
        while b < blockCount {
            rowStart[blockRow[b] + 1] += 1
            b += 1
        }
        var r = 0
        while r < rows {
            rowStart[r + 1] += rowStart[r]
            r += 1
        }
        rowBlocks = [Int](repeating: 0, count: blockCount)
        var fill = rowStart
        b = 0
        while b < blockCount {
            rowBlocks[fill[blockRow[b]]] = b
            fill[blockRow[b]] += 1
            b += 1
        }
    }

    /// The chain through `v`, beginning at the end that touches `from`
    /// (−1: `v` starts the chain, which may then grow both ways). A spouse
    /// already placed — a ring of marriages — is not placed twice; its line
    /// dips round whoever ends up between.
    private mutating func extend(_ v: Int, from: Int) -> [Int] {
        visited[v] = true
        let s = spouseStart[v], e = spouseStart[v + 1]
        let first = e > s ? spouses[s] : -1
        let second = e > s + 1 ? spouses[s + 1] : -1
        var result: [Int] = []
        if from < 0 {
            // The start: first spouse to the left, second to the right, and
            // further ones beyond them, alternating, so their dips go opposite ways.
            var leftSide: [Int] = []
            var rightSide: [Int] = []
            if first >= 0 && !visited[first] { leftSide = extend(first, from: v) }
            if second >= 0 && !visited[second] { rightSide = extend(second, from: v) }
            var k = s + 2
            var toLeft = true
            while k < e {
                let w = spouses[k]
                if !visited[w] {
                    if toLeft { leftSide += extend(w, from: v) } else { rightSide += extend(w, from: v) }
                    toLeft.toggle()
                }
                k += 1
            }
            result = leftSide.reversed()
            result.append(v)
            result += rightSide
        } else if from == first || from == second {
            // `from` is one of the two who flank v: the other goes on the far
            // side, and further spouses beyond it.
            result.append(v)
            let other = from == first ? second : first
            if other >= 0 && !visited[other] { result += extend(other, from: v) }
            var k = s + 2
            while k < e {
                if !visited[spouses[k]] { result += extend(spouses[k], from: v) }
                k += 1
            }
        } else {
            // `from` is a further spouse of v: v still stands between its first
            // two, and `from` lies beyond the first of them.
            if first >= 0 && !visited[first] { result = extend(first, from: v).reversed() }
            result.append(v)
            if second >= 0 && !visited[second] { result += extend(second, from: v) }
            var k = s + 2
            while k < e {
                let w = spouses[k]
                if w != from && !visited[w] { result += extend(w, from: v) }
                k += 1
            }
        }
        return result
    }

    /// Which blocks should stand in one run: a union's children, a sibling
    /// bar's members, and the parents of a union who are not a couple. Blocks
    /// joined through groups form a cluster, and a cluster is never split.
    private mutating func buildGroups() {
        var mark = [Int](repeating: -1, count: blockCount)
        var stamp = 0
        unionChildGroup = [Int](repeating: -1, count: unionCount)
        var u = 0
        while u < unionCount {
            let start = groupBlocks.count
            var k = unionChildStart[u]
            while k < unionChildStart[u + 1] {
                let b = blockOf[unionChildren[k]]
                if mark[b] != stamp {
                    mark[b] = stamp
                    groupBlocks.append(b)
                }
                k += 1
            }
            Sketch.sort(&groupBlocks, start, groupBlocks.count)
            unionChildGroup[u] = groupRow.count
            groupStart.append(groupBlocks.count)
            groupRow.append(unionRow[u] + 1)
            stamp += 1
            u += 1
        }
        var g = 0
        while g < barCount {
            let start = groupBlocks.count
            var k = barStart[g]
            while k < barStart[g + 1] {
                let b = blockOf[barMembers[k]]
                if mark[b] != stamp {
                    mark[b] = stamp
                    groupBlocks.append(b)
                }
                k += 1
            }
            Sketch.sort(&groupBlocks, start, groupBlocks.count)
            groupStart.append(groupBlocks.count)
            groupRow.append(barRow[g])
            stamp += 1
            g += 1
        }
        u = 0
        while u < unionCount {
            let start = unionBlocks.count
            var k = unionParentStart[u]
            while k < unionParentStart[u + 1] {
                let b = blockOf[unionParents[k]]
                if mark[b] != stamp {
                    mark[b] = stamp
                    unionBlocks.append(b)
                }
                k += 1
            }
            Sketch.sort(&unionBlocks, start, unionBlocks.count)
            unionBlockStart.append(unionBlocks.count)
            if !unionCouple[u] && unionBlocks.count - start >= 2 {
                k = start
                while k < unionBlocks.count {
                    groupBlocks.append(unionBlocks[k])
                    k += 1
                }
                groupStart.append(groupBlocks.count)
                groupRow.append(unionRow[u])
            }
            stamp += 1
            u += 1
        }
        groupCount = groupRow.count

        blockGroupStart = [Int](repeating: 0, count: blockCount + 1)
        rowGroupStart = [Int](repeating: 0, count: rows + 1)
        g = 0
        while g < groupCount {
            var k = groupStart[g]
            while k < groupStart[g + 1] {
                blockGroupStart[groupBlocks[k] + 1] += 1
                k += 1
            }
            rowGroupStart[groupRow[g] + 1] += 1
            g += 1
        }
        var b = 0
        while b < blockCount {
            blockGroupStart[b + 1] += blockGroupStart[b]
            b += 1
        }
        var r = 0
        while r < rows {
            rowGroupStart[r + 1] += rowGroupStart[r]
            r += 1
        }
        blockGroups = [Int](repeating: 0, count: blockGroupStart[blockCount])
        rowGroups = [Int](repeating: 0, count: groupCount)
        var blockFill = blockGroupStart, rowFill = rowGroupStart
        g = 0
        while g < groupCount {
            var k = groupStart[g]
            while k < groupStart[g + 1] {
                let c = groupBlocks[k]
                blockGroups[blockFill[c]] = g
                blockFill[c] += 1
                k += 1
            }
            rowGroups[rowFill[groupRow[g]]] = g
            rowFill[groupRow[g]] += 1
            g += 1
        }

        // Clusters, numbered by their earliest block.
        var up = [Int](repeating: 0, count: blockCount)
        b = 0
        while b < blockCount {
            up[b] = b
            b += 1
        }
        g = 0
        while g < groupCount {
            var root = groupBlocks[groupStart[g]]
            while up[root] != root { root = up[root] }
            var k = groupStart[g] + 1
            while k < groupStart[g + 1] {
                var other = groupBlocks[k]
                while up[other] != other { other = up[other] }
                if other < root {
                    up[root] = other
                    root = other
                } else if other > root {
                    up[other] = root
                }
                k += 1
            }
            g += 1
        }
        clusterOf = [Int](repeating: 0, count: blockCount)
        b = 0
        while b < blockCount {
            var root = b
            while up[root] != root { root = up[root] }
            clusterOf[b] = root
            b += 1
        }
    }

    // MARK: - Order and place

    /// One pass down to seed every row, two rounds of up-and-down sweeps that
    /// reorder and re-place, two rounds that only re-place, and a last pass
    /// down on the half-person grid, so the children end centred under their
    /// parents rather than the other way round.
    mutating func arrange() {
        var r = 0
        while r < rows {
            order(r, down: true)
            place(r, down: true, final: false)
            r += 1
        }
        var round = 0
        while round < 2 {
            r = rows - 2
            while r >= 0 {
                order(r, down: false)
                place(r, down: false, final: false)
                r -= 1
            }
            r = 1
            while r < rows {
                order(r, down: true)
                place(r, down: true, final: false)
                r += 1
            }
            round += 1
        }
        round = 0
        while round < 2 {
            r = rows - 2
            while r >= 0 {
                place(r, down: false, final: false)
                r -= 1
            }
            r = 1
            while r < rows {
                place(r, down: true, final: false)
                r += 1
            }
            round += 1
        }
        r = 0
        while r < rows {
            place(r, down: true, final: true)
            r += 1
        }
        var lowest = Double.infinity
        var k = 0
        while k < x.count {
            if x[k] < lowest { lowest = x[k] }
            k += 1
        }
        k = 0
        while k < x.count {
            x[k] -= lowest
            k += 1
        }
    }

    /// The middle of a union's parents: where its children hang from.
    private func anchor(_ u: Int) -> Double {
        var lo = Double.infinity, hi = -Double.infinity
        var k = unionParentStart[u]
        while k < unionParentStart[u + 1] {
            let v = x[unionParents[k]]
            if v < lo { lo = v }
            if v > hi { hi = v }
            k += 1
        }
        return (lo + hi) / 2
    }

    /// The middle of a union's children: where its parents would stand.
    private func centre(_ u: Int) -> Double {
        var lo = Double.infinity, hi = -Double.infinity
        var k = unionChildStart[u]
        while k < unionChildStart[u + 1] {
            let v = x[unionChildren[k]]
            if v < lo { lo = v }
            if v > hi { hi = v }
            k += 1
        }
        return (lo + hi) / 2
    }

    /// Where a member wants to be: under its parents (down) or over its
    /// children (up), if it has any on that side.
    private func want(_ v: Int, down: Bool) -> (Bool, Double) {
        if down {
            let u = unionOf[v]
            return u >= 0 ? (true, anchor(u)) : (false, 0)
        }
        let s = parentUnionStart[v], e = parentUnionStart[v + 1]
        if s == e { return (false, 0) }
        var sum = 0.0
        var k = s
        while k < e {
            sum += centre(parentUnions[k])
            k += 1
        }
        return (true, sum / Double(e - s))
    }

    /// Sorts a row: clusters by where they want to be, and within a cluster
    /// its groups by the same, each block after the groups it belongs to — so
    /// a block two groups share lands between them. Then turns each chain
    /// the way its members want.
    private mutating func order(_ r: Int, down: Bool) {
        let s = rowStart[r], e = rowStart[r + 1]
        let known = placed[r]
        var j = s
        while j < e {
            let b = rowBlocks[j]
            var sum = 0.0, count = 0.0, spot = 0.0
            var t = blockStart[b]
            while t < blockStart[b + 1] {
                let v = blockMembers[t]
                let (has, value) = want(v, down: down)
                if has {
                    sum += value
                    count += 1
                }
                spot += x[v]
                t += 1
            }
            hasKey[b] = count > 0
            key[b] = count > 0 ? sum / count : 0
            current[b] = known ? spot / Double(blockStart[b + 1] - blockStart[b]) : .infinity
            let c = clusterOf[b]
            cSum[c] = 0
            cN[c] = 0
            cCur[c] = 0
            cCount[c] = 0
            j += 1
        }
        j = s
        while j < e {
            let b = rowBlocks[j], c = clusterOf[b]
            if hasKey[b] {
                cSum[c] += key[b]
                cN[c] += 1
            }
            cCur[c] += current[b]
            cCount[c] += 1
            j += 1
        }
        j = s
        while j < e {
            let c = clusterOf[rowBlocks[j]]
            cKey[c] = cN[c] > 0 ? cSum[c] / cN[c] : known ? cCur[c] / cCount[c] : .infinity
            j += 1
        }

        let gs = rowGroupStart[r], gc = rowGroupStart[r + 1] - gs
        var q = 0
        while q < gc {
            let g = rowGroups[gs + q]
            var sum = 0.0, count = 0.0, spot = 0.0
            var t = groupStart[g]
            while t < groupStart[g + 1] {
                let b = groupBlocks[t]
                if hasKey[b] {
                    sum += key[b]
                    count += 1
                }
                spot += current[b]
                t += 1
            }
            gKey[g] = count > 0 ? sum / count
                : known ? spot / Double(groupStart[g + 1] - groupStart[g]) : .infinity
            gOrder[q] = g
            q += 1
        }
        q = 1
        while q < gc {
            let g = gOrder[q]
            var i = q - 1
            while i >= 0 && groupAfter(gOrder[i], g) {
                gOrder[i + 1] = gOrder[i]
                i -= 1
            }
            gOrder[i + 1] = g
            q += 1
        }
        var lastCluster = -1, localRank = 0.0
        q = 0
        while q < gc {
            let g = gOrder[q], c = clusterOf[groupBlocks[groupStart[g]]]
            if c != lastCluster {
                lastCluster = c
                localRank = 0
            } else {
                localRank += 1
            }
            gRank[g] = localRank
            q += 1
        }
        j = s
        while j < e {
            let b = rowBlocks[j]
            var sum = 0.0, count = 0.0
            var t = blockGroupStart[b]
            while t < blockGroupStart[b + 1] {
                sum += gRank[blockGroups[t]]
                count += 1
                t += 1
            }
            rank[b] = count > 0 ? sum / count : 0
            j += 1
        }

        j = s + 1
        while j < e {
            let b = rowBlocks[j]
            var i = j - 1
            while i >= s && blockAfter(rowBlocks[i], b) {
                rowBlocks[i + 1] = rowBlocks[i]
                i -= 1
            }
            rowBlocks[i + 1] = b
            j += 1
        }

        j = s
        while j < e {
            let c = clusterOf[rowBlocks[j]]
            var k = j + 1
            while k < e && clusterOf[rowBlocks[k]] == c { k += 1 }
            var t = j
            while t < k {
                orient(rowBlocks[t], down: down, side: Double(t - j) - Double(k - 1 - j) / 2, run: k - j)
                t += 1
            }
            j = k
        }
    }

    private func groupAfter(_ a: Int, _ b: Int) -> Bool {
        let ca = clusterOf[groupBlocks[groupStart[a]]], cb = clusterOf[groupBlocks[groupStart[b]]]
        if ca != cb { return ca > cb }
        if gKey[a] != gKey[b] { return gKey[a] > gKey[b] }
        return a > b
    }

    private func blockAfter(_ a: Int, _ b: Int) -> Bool {
        let ca = clusterOf[a], cb = clusterOf[b]
        if ca != cb {
            if cKey[ca] != cKey[cb] { return cKey[ca] > cKey[cb] }
            return ca > cb
        }
        if rank[a] != rank[b] { return rank[a] > rank[b] }
        let ka = hasKey[a] ? key[a] : current[a], kb = hasKey[b] ? key[b] : current[b]
        if ka != kb { return ka > kb }
        return a > b
    }

    /// Turns a chain so that its members' wants rise left to right. When they
    /// do not say (one member pulled, or all pulled the same way), whoever
    /// nothing pulls — usually somebody who married in — faces out of the
    /// cluster, so that the one who is pulled stands next to their siblings.
    private mutating func orient(_ b: Int, down: Bool, side: Double, run: Int) {
        let s = blockStart[b], e = blockStart[b + 1]
        if e - s < 2 { return }
        var keyed = 0.0, keyedAt = 0.0, keyedSum = 0.0, free = 0.0, freeAt = 0.0
        var t = s
        while t < e {
            let (has, value) = want(blockMembers[t], down: down)
            memberHas[t - s] = has
            memberKey[t - s] = value
            if has {
                keyed += 1
                keyedAt += Double(t - s)
                keyedSum += value
            } else {
                free += 1
                freeAt += Double(t - s)
            }
            t += 1
        }
        var slope = 0.0
        if keyed >= 2 {
            let meanAt = keyedAt / keyed, meanKey = keyedSum / keyed
            t = 0
            while t < e - s {
                if memberHas[t] { slope += (Double(t) - meanAt) * (memberKey[t] - meanKey) }
                t += 1
            }
        }
        var flip = slope < -1e-9
        if !flip && slope <= 1e-9 && keyed > 0 && free > 0 && run > 1 && side != 0 {
            let freeRight = freeAt / free > keyedAt / keyed
            flip = side < 0 ? freeRight : !freeRight
        }
        if flip {
            var i = s, k = e - 1
            while i < k {
                let v = blockMembers[i]
                blockMembers[i] = blockMembers[k]
                blockMembers[k] = v
                i += 1
                k -= 1
            }
            t = s
            while t < e {
                slot[blockMembers[t]] = t - s
                t += 1
            }
        }
    }

    /// Places one row in its current order: every block as close as it can get
    /// to where the row above (down) or below (up) wants it, nobody closer
    /// than one apart. In y = left − (widths before it) the spacing rule is
    /// y rising, so this is isotonic regression, solved by pooling.
    private mutating func place(_ r: Int, down: Bool, final: Bool) {
        let s = rowStart[r], e = rowStart[r + 1]
        var width = 0
        var j = s
        while j < e {
            let b = rowBlocks[j]
            at[b] = j
            before[b] = width
            width += blockStart[b + 1] - blockStart[b]
            acc[b] = 0
            wsum[b] = 0
            j += 1
        }
        if down {
            if r > 0 {
                var q = rowUnionStart[r - 1]
                while q < rowUnionStart[r] {
                    pullChildren(rowUnions[q])
                    q += 1
                }
            }
        } else if r + 1 < rows {
            var q = rowUnionStart[r]
            while q < rowUnionStart[r + 1] {
                pullParents(rowUnions[q])
                q += 1
            }
        }

        let known = placed[r]
        var top = 0
        j = s
        while j < e {
            let b = rowBlocks[j]
            var w = wsum[b], value = 0.0
            if w > 0 {
                value = acc[b] / w
            } else if known {
                // Where the block stood, whichever way it has since been turned.
                var stood = Double.infinity
                var t = blockStart[b]
                while t < blockStart[b + 1] {
                    if x[blockMembers[t]] < stood { stood = x[blockMembers[t]] }
                    t += 1
                }
                w = Sketch.inertia
                value = stood - Double(before[b])
            }
            weighted[b] = w > 0
            if w > 0 {
                poolValue[top] = value
                poolWeight[top] = w
                poolSize[top] = 1
                top += 1
                while top > 1 && poolValue[top - 2] > poolValue[top - 1] {
                    let a = top - 2, c = top - 1
                    let merged = poolWeight[a] + poolWeight[c]
                    poolValue[a] = (poolValue[a] * poolWeight[a] + poolValue[c] * poolWeight[c]) / merged
                    poolWeight[a] = merged
                    poolSize[a] += poolSize[c]
                    top -= 1
                }
            }
            j += 1
        }
        var pool = 0, remaining = top > 0 ? poolSize[0] : 0
        var last = -1
        j = s
        while j < e {
            let b = rowBlocks[j]
            if weighted[b] {
                if remaining == 0 {
                    pool += 1
                    remaining = poolSize[pool]
                }
                yv[b] = poolValue[pool]
                remaining -= 1
                last = j
            } else {
                prevW[j - s] = last
            }
            j += 1
        }
        last = -1
        j = e - 1
        while j >= s {
            if weighted[rowBlocks[j]] { last = j } else { nextW[j - s] = last }
            j -= 1
        }
        // A block nothing pulls stands against a neighbour of its own cluster,
        // or failing that against its left neighbour — never floating between.
        j = s
        while j < e {
            let b = rowBlocks[j]
            if !weighted[b] {
                let p = prevW[j - s], q = nextW[j - s]
                if p < 0 && q < 0 {
                    yv[b] = 0
                } else if p < 0 {
                    yv[b] = yv[rowBlocks[q]]
                } else if q < 0 {
                    yv[b] = yv[rowBlocks[p]]
                } else if clusterOf[rowBlocks[p]] != clusterOf[b] && clusterOf[rowBlocks[q]] == clusterOf[b] {
                    yv[b] = yv[rowBlocks[q]]
                } else {
                    yv[b] = yv[rowBlocks[p]]
                }
            }
            j += 1
        }
        j = s
        while j < e {
            let b = rowBlocks[j]
            // Rounding is monotone, so the half-person grid keeps the spacing.
            let y = final ? (yv[b] * 2).rounded() / 2 : yv[b]
            let left = y + Double(before[b])
            var t = blockStart[b]
            while t < blockStart[b + 1] {
                x[blockMembers[t]] = left + Double(t - blockStart[b])
                t += 1
            }
            j += 1
        }
        placed[r] = true
    }

    /// Sorts `list[0..<count]` by where each block stands on its row, and
    /// records where each would start if the run were packed.
    private mutating func packList(_ count: Int) {
        var i = 1
        while i < count {
            let b = list[i]
            var k = i - 1
            while k >= 0 && at[list[k]] > at[b] {
                list[k + 1] = list[k]
                k -= 1
            }
            list[k + 1] = b
            i += 1
        }
        var run = 0
        i = 0
        while i < count {
            packed[list[i]] = run
            run += blockStart[list[i] + 1] - blockStart[list[i]]
            i += 1
        }
    }

    /// Pulls a union's children, packed as one run, until their middle is
    /// under the union's anchor (R5).
    private mutating func pullChildren(_ u: Int) {
        let target = anchor(u)
        let g = unionChildGroup[u]
        let count = groupStart[g + 1] - groupStart[g]
        var i = 0
        while i < count {
            list[i] = groupBlocks[groupStart[g] + i]
            i += 1
        }
        packList(count)
        var lo = Int.max, hi = Int.min
        var k = unionChildStart[u]
        while k < unionChildStart[u + 1] {
            let c = unionChildren[k]
            let spot = packed[blockOf[c]] + slot[c]
            if spot < lo { lo = spot }
            if spot > hi { hi = spot }
            k += 1
        }
        let middle = Double(lo + hi) / 2
        i = 0
        while i < count {
            let b = list[i]
            acc[b] += target - middle + Double(packed[b] - before[b])
            wsum[b] += 1
            i += 1
        }
    }

    /// Pulls a union's parents, packed as one run, until their middle is over
    /// the middle of their children.
    private mutating func pullParents(_ u: Int) {
        let target = centre(u)
        let s = unionBlockStart[u], count = unionBlockStart[u + 1] - s
        var i = 0
        while i < count {
            list[i] = unionBlocks[s + i]
            i += 1
        }
        packList(count)
        var lo = Int.max, hi = Int.min
        var k = unionParentStart[u]
        while k < unionParentStart[u + 1] {
            let p = unionParents[k]
            let spot = packed[blockOf[p]] + slot[p]
            if spot < lo { lo = spot }
            if spot > hi { hi = spot }
            k += 1
        }
        let middle = Double(lo + hi) / 2
        i = 0
        while i < count {
            let b = list[i]
            acc[b] += target - middle + Double(packed[b] - before[b])
            wsum[b] += 1
            i += 1
        }
    }

    // MARK: - Lines

    /// How far a couple line dips to pass under `blockMembers[a+1..<b]` (R4).
    private func dip(_ a: Int, _ b: Int) -> Double {
        var deepest = 0.0
        var t = a + 1
        while t < b {
            if depth[blockMembers[t]] > deepest { deepest = depth[blockMembers[t]] }
            t += 1
        }
        return max(0.4, deepest + 0.05)
    }

    func draw(shift: Double, into lines: inout [FamilyTreeLayout.Line]) {
        typealias Line = FamilyTreeLayout.Line

        // Couples, row by row, left to right. A couple with somebody between
        // them dips under that somebody rather than through them.
        var dipRow: [Int] = [], dipLeft: [Double] = [], dipRight: [Double] = [], dipDepth: [Double] = []
        var r = 0
        while r < rows {
            var j = rowStart[r]
            while j < rowStart[r + 1] {
                let b = rowBlocks[j]
                let s = blockStart[b], e = blockStart[b + 1]
                var t = s
                while t < e {
                    let v = blockMembers[t]
                    var t2 = t + 1
                    while t2 < e {
                        let w = blockMembers[t2]
                        if isSpouse(v, w) {
                            let xl = x[v] + shift, xr = x[w] + shift, y = Double(r)
                            if t2 == t + 1 {
                                lines.append(Line(x1: xl, y1: y, x2: xr, y2: y, stroke: .couple))
                            } else {
                                let d = dip(t, t2)
                                let low = y + d, leftTop = y + min(depth[v], d), rightTop = y + min(depth[w], d)
                                if leftTop < low { lines.append(Line(x1: xl, y1: leftTop, x2: xl, y2: low, stroke: .couple)) }
                                lines.append(Line(x1: xl, y1: low, x2: xr, y2: low, stroke: .couple))
                                if rightTop < low { lines.append(Line(x1: xr, y1: rightTop, x2: xr, y2: low, stroke: .couple)) }
                                dipRow.append(r)
                                dipLeft.append(x[v])
                                dipRight.append(x[w])
                                dipDepth.append(d)
                            }
                        }
                        t2 += 1
                    }
                    t += 1
                }
                j += 1
            }
            r += 1
        }

        var barLeft = [Double](repeating: 0, count: barCount), barRight = barLeft
        var g = 0
        while g < barCount {
            var lo = Double.infinity, hi = -Double.infinity
            var k = barStart[g]
            while k < barStart[g + 1] {
                let v = x[barMembers[k]]
                if v < lo { lo = v }
                if v > hi { hi = v }
                k += 1
            }
            barLeft[g] = lo
            barRight[g] = hi
            g += 1
        }

        // Descent, one parents' row at a time. Heights are dealt fewest
        // parents first, then left to right, each taking the first height no
        // overlapping bar dealt before it took (R5). A sibling bar of the row
        // below sits at 0.6 and a dipping couple line at its own depth; both
        // count as taken where they overlap, because a bar at the same height
        // would read as one line with them.
        var spanLeft = [Double](repeating: 0, count: unionCount), spanRight = spanLeft
        var hangOf = spanLeft, lowest = spanLeft, stemTop = spanLeft
        var deal = [Int](repeating: 0, count: unionCount)
        r = 0
        while r + 1 < rows {
            let us = rowUnionStart[r], count = rowUnionStart[r + 1] - us
            var q = 0
            while q < count {
                let u = rowUnions[us + q]
                var lo = Double.infinity, hi = -Double.infinity
                var k = unionChildStart[u]
                while k < unionChildStart[u + 1] {
                    let v = x[unionChildren[k]]
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                    k += 1
                }
                let ps = unionParentStart[u]
                if unionCouple[u] {
                    let a = unionParents[ps], b = unionParents[ps + 1]
                    let middle = (x[a] + x[b]) / 2
                    if middle < lo { lo = middle }
                    if middle > hi { hi = middle }
                    let sa = slot[a], sb = slot[b], base = blockStart[blockOf[a]]
                    if abs(sa - sb) > 1 {
                        let d = dip(base + min(sa, sb), base + max(sa, sb))
                        stemTop[u] = d
                        lowest[u] = d + 0.05
                    } else {
                        stemTop[u] = 0
                        lowest[u] = 0
                    }
                } else {
                    k = ps
                    while k < unionParentStart[u + 1] {
                        let v = x[unionParents[k]]
                        if v < lo { lo = v }
                        if v > hi { hi = v }
                        k += 1
                    }
                    lowest[u] = 0
                }
                spanLeft[u] = lo
                spanRight[u] = hi
                deal[q] = u
                q += 1
            }
            q = 1
            while q < count {
                let u = deal[q]
                var i = q - 1
                while i >= 0 && dealtAfter(deal[i], u, spanLeft, spanRight) {
                    deal[i + 1] = deal[i]
                    i -= 1
                }
                deal[i + 1] = u
                q += 1
            }
            q = 0
            while q < count {
                let u = deal[q]
                func free(_ h: Double) -> Bool {
                    var i = 0
                    while i < q {
                        let w = deal[i]
                        if hangOf[w] == h && spanLeft[u] <= spanRight[w] + 1e-9 && spanLeft[w] <= spanRight[u] + 1e-9 {
                            return false
                        }
                        i += 1
                    }
                    if abs(h - 0.6) < 1e-9 && r + 1 < rows {
                        var k = rowBarStart[r + 1]
                        while k < rowBarStart[r + 2] {
                            let bar = rowBars[k]
                            if spanLeft[u] <= barRight[bar] + 1e-9 && barLeft[bar] <= spanRight[u] + 1e-9 { return false }
                            k += 1
                        }
                    }
                    var k = 0
                    while k < dipRow.count {
                        if dipRow[k] == r && abs(dipDepth[k] - h) < 1e-9
                            && spanLeft[u] <= dipRight[k] + 1e-9 && dipLeft[k] <= spanRight[u] + 1e-9 {
                            return false
                        }
                        k += 1
                    }
                    return true
                }
                var h = -1.0
                var k = 0
                while k < hangs.count {
                    if hangs[k] >= lowest[u] - 1e-9 && free(hangs[k]) {
                        h = hangs[k]
                        break
                    }
                    k += 1
                }
                if h < 0 {
                    // Past every height between 0.5 and 0.7: only a row with
                    // more overlapping bars than the grid has heights gets here.
                    h = max(0.7, lowest[u]) + 0.0125
                    while !free(h) { h += 0.0125 }
                }
                hangOf[u] = h
                q += 1
            }

            let y = Double(r)
            q = 0
            while q < count {
                let u = deal[q]
                let h = hangOf[u], bar = y + h
                let ps = unionParentStart[u]
                if unionCouple[u] {
                    let middle = (x[unionParents[ps]] + x[unionParents[ps + 1]]) / 2 + shift
                    lines.append(Line(x1: middle, y1: y + stemTop[u], x2: middle, y2: bar, stroke: .descent))
                } else {
                    var k = ps
                    while k < unionParentStart[u + 1] {
                        let p = unionParents[k]
                        let top = y + min(depth[p], h)
                        if top < bar {
                            lines.append(Line(x1: x[p] + shift, y1: top, x2: x[p] + shift, y2: bar, stroke: .descent))
                        }
                        k += 1
                    }
                }
                if spanRight[u] > spanLeft[u] {
                    lines.append(Line(x1: spanLeft[u] + shift, y1: bar, x2: spanRight[u] + shift, y2: bar, stroke: .descent))
                }
                var k = unionChildStart[u]
                while k < unionChildStart[u + 1] {
                    let c = x[unionChildren[k]] + shift
                    lines.append(Line(x1: c, y1: bar, x2: c, y2: y + 1, stroke: .descent))
                    k += 1
                }
                q += 1
            }
            r += 1
        }

        // Sibling bars, row by row, left to right (R6).
        r = 0
        while r < rows {
            let bs = rowBarStart[r], count = rowBarStart[r + 1] - bs
            var sorted = [Int](repeating: 0, count: count)
            var q = 0
            while q < count {
                let bar = rowBars[bs + q]
                var i = q - 1
                while i >= 0 && barLeft[sorted[i]] > barLeft[bar] {
                    sorted[i + 1] = sorted[i]
                    i -= 1
                }
                sorted[i + 1] = bar
                q += 1
            }
            let y = Double(r) - 0.4
            q = 0
            while q < count {
                let bar = sorted[q]
                lines.append(Line(x1: barLeft[bar] + shift, y1: y, x2: barRight[bar] + shift, y2: y, stroke: .sibling))
                var k = barStart[bar]
                while k < barStart[bar + 1] {
                    let v = x[barMembers[k]] + shift
                    lines.append(Line(x1: v, y1: y, x2: v, y2: Double(r), stroke: .sibling))
                    k += 1
                }
                q += 1
            }
            r += 1
        }
    }

    /// Dealing order: fewest parents first, then left to right.
    private func dealtAfter(_ a: Int, _ b: Int, _ left: [Double], _ right: [Double]) -> Bool {
        let pa = unionParentStart[a + 1] - unionParentStart[a], pb = unionParentStart[b + 1] - unionParentStart[b]
        if pa != pb { return pa > pb }
        if left[a] != left[b] { return left[a] > left[b] }
        if right[a] != right[b] { return right[a] > right[b] }
        return unionChildren[unionChildStart[a]] > unionChildren[unionChildStart[b]]
    }
}
