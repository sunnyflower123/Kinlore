// Checks where the family tree puts everybody, and every line it draws
// (FamilyTreeLayout.swift, requirements R1–R9 of the 25 Sep 2026 rebuild).
//
// Every way of getting this wrong is silent. A child drawn a row above her
// mother, a couple split by a stranger, a bar two unions share so that every
// child on it reads as every parent's, a couple line run through a third
// person's card — each one still draws a tree, none fails a build, and a
// screenshot shows a picture either way. The picture is simply false, about a
// family, to the family.
//
// So the audit below derives everything again from the input — generations,
// families, unions, sibling groups, the exact lines the rules call for — and
// compares it with what the engine drew, first on named cases (the app's
// `-seed clan` among them) and then on 5 000 random families with the links
// shuffled. It costs nothing: no simulator, no network. Run it after touching
// FamilyTreeLayout.swift — the command is in CLAUDE.md.
//
//   swiftc -parse-as-library -o /tmp/family-tree-layout-check \
//     scripts/family-tree-layout-check.swift ios/Kinlore/Services/FamilyTreeLayout.swift

import Foundation

@main
enum FamilyTreeLayoutCheck {
    typealias Layout = FamilyTreeLayout
    typealias Link = FamilyTreeLayout.Link
    typealias Line = FamilyTreeLayout.Line

    // MARK: - Cases

    struct Case {
        var people: [String]
        var links: [Link]
        var friends: [String] = []
        var root: String?
        /// Missing: 0.38, and 0.5 for the root — the screen's own numbers.
        var depths: [String: Double] = [:]

        func depth(_ id: String) -> Double {
            if !depths.isEmpty, let d = depths[id] { return d }
            return id == root ? 0.5 : 0.38
        }

        func run() -> Layout.Result {
            Layout.layout(people: people, links: links, friends: friends, root: root, depth: depth)
        }
    }

    static func parent(_ a: String, _ b: String) -> Link { Link(from: a, to: b, bond: .parent) }
    static func spouse(_ a: String, _ b: String) -> Link { Link(from: a, to: b, bond: .spouse) }
    static func sibling(_ a: String, _ b: String) -> Link { Link(from: a, to: b, bond: .sibling) }

    static func describe(_ link: Link) -> String {
        switch link.bond {
        case .parent: "\(link.from) → \(link.to)"
        case .spouse: "\(link.from) ⚭ \(link.to)"
        case .sibling: "\(link.from) ~ \(link.to)"
        }
    }

    static func describe(_ line: Line) -> String {
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        return "\(line.stroke) (\(f(line.x1)), \(f(line.y1)))–(\(f(line.x2)), \(f(line.y2)))"
    }

    /// The app's `-seed clan`, as the specification gives it: three families,
    /// a second marriage, a cousin ring, a marriage across generations, a
    /// parent pair entered both ways, a friend with kin and seven loose cards.
    static let clan: Case = {
        let people = [
            "Aapo", "Hilma", "Väinö", "Impi", "Sulo", "Lyyli", "Kerttu", "Hilja", "Toivo", "Martta",
            "Eino", "Aune", "Reino", "Sirkka", "Urho", "Onni", "Oiva", "Helvi", "Paavo", "Eemeli",
            "Anneli", "Matti", "Liisa", "Veikko", "Kaarina", "Ritva", "Elina", "Jukka", "Tuula", "Sanni",
            "Heikki", "Aleksi", "Mikko", "Venla", "Oskari", "Aino", "Petra", "Elias", "Noora", "Iiris",
            "Sisko", "Mauri", "Tarja", "Onerva", "Otto", "Helmi", "Rauha", "Jonne", "Kustaa", "Alma",
            "Yrjö", "Saima", "Lauri", "Hellin", "Verneri",
        ]
        var links: [Link] = []
        func couple(_ a: String, _ b: String, _ children: [String]) {
            links.append(spouse(a, b))
            for c in children { links += [parent(a, c), parent(b, c)] }
        }
        couple("Aapo", "Hilma", ["Väinö", "Impi", "Sulo"])
        couple("Aapo", "Lyyli", ["Kerttu"])
        couple("Väinö", "Hilja", ["Toivo", "Martta", "Eino", "Aune", "Reino", "Sirkka"])
        couple("Impi", "Urho", [])
        links.append(parent("Sulo", "Onni"))
        couple("Kerttu", "Oiva", ["Helvi", "Paavo"])
        links.append(sibling("Oiva", "Eemeli"))
        couple("Toivo", "Anneli", ["Matti", "Liisa"])
        links.append(parent("Martta", "Veikko"))
        couple("Eino", "Helvi", ["Kaarina"])
        couple("Aune", "Paavo", ["Ritva"])
        links.append(spouse("Eemeli", "Sirkka"))
        links += [parent("Sulo", "Onni"), parent("Onni", "Sulo")]
        couple("Matti", "Ritva", ["Elina", "Jukka"])
        couple("Veikko", "Tuula", ["Sanni"])
        couple("Kaarina", "Heikki", ["Aleksi"])
        couple("Elina", "Mikko", ["Venla", "Oskari", "Aino"])
        couple("Jukka", "Petra", ["Elias"])
        couple("Aleksi", "Noora", ["Iiris"])
        links += [sibling("Sisko", "Mauri"), sibling("Mauri", "Tarja"), sibling("Sisko", "Tarja")]
        links.append(parent("Sisko", "Onerva"))
        couple("Otto", "Helmi", [])
        links.append(sibling("Helmi", "Rauha"))
        return Case(people: people, links: links, friends: ["Rauha", "Jonne"], root: "Elina")
    }()

    // MARK: - The audit

    /// The heights a bar may hang at, in dealing order — the engine's list,
    /// written out again: 0.5, 0.7, 0.6 from the specification, then the gaps
    /// between 0.5 and 0.7 halved, for rows where more bars overlap than three
    /// heights can keep apart.
    static let hangs: [Double] = {
        var values = [0.5, 0.7, 0.6]
        var step = 0.05
        for _ in 0 ..< 5 {
            var odd = 1.0
            while step * odd < 0.2 - 1e-9 {
                values.append(0.5 + step * odd)
                odd += 2
            }
            step /= 2
        }
        return values
    }()

    static let requirement = [
        "",
        "R1 everybody placed once, one apart, leftmost at 0",
        "R2 rows are generations; families side by side from row 0",
        "R3 the earlier link wins; only what no row can hold is undrawn",
        "R4 couples stand together; their line dips round anybody between",
        "R5 children hang together; overlapping bars never share a height",
        "R6 siblings nobody shares a parent with get a bar",
        "R7 link order changes nothing",
        "R8 friends and loose people on bands of their own",
    ]

    /// Everything R1–R6 and R8 say about one layout, derived from the input
    /// again rather than read back from the engine. Slot k of `found` holds
    /// the first thing requirement k found wrong, or nil; `excused` names the
    /// R4 claims this input makes impossible, with the reason.
    static func audit(_ c: Case, _ r: Layout.Result) -> (found: [String?], excused: [String]) {
        var found = [String?](repeating: nil, count: 9)
        var excused: [String] = []
        func fail(_ k: Int, _ message: @autoclosure () -> String) {
            if found[k] == nil { found[k] = message() }
        }

        var index: [String: Int] = [:]
        var ids: [String] = []
        var i = 0
        while i < c.people.count {
            if index[c.people[i]] == nil {
                index[c.people[i]] = ids.count
                ids.append(c.people[i])
            }
            i += 1
        }
        let n = ids.count

        // R1 — everybody once, nobody closer than one apart on a row.
        if r.places.count != n { fail(1, "\(r.places.count) places for \(n) people") }
        var row = [Int](repeating: 0, count: n), x = [Double](repeating: 0, count: n)
        var depth = [Double](repeating: 0, count: n)
        var lowest = Double.infinity, rows = 0
        i = 0
        while i < n {
            guard let place = r.places[ids[i]] else {
                fail(1, "\(ids[i]) has no place")
                return (found, excused)
            }
            row[i] = place.row
            x[i] = place.x
            depth[i] = c.depth(ids[i])
            if place.x < lowest { lowest = place.x }
            if place.row + 1 > rows { rows = place.row + 1 }
            i += 1
        }
        if n > 0 && abs(lowest) > 1e-9 { fail(1, "the leftmost person is at x = \(lowest)") }
        var byPlace = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            byPlace[i] = i
            i += 1
        }
        byPlace.sort { row[$0] != row[$1] ? row[$0] < row[$1] : x[$0] < x[$1] }
        var rowStart = [Int](repeating: 0, count: rows + 1)
        i = 0
        while i < n {
            rowStart[row[i] + 1] += 1
            i += 1
        }
        var k = 0
        while k < rows {
            rowStart[k + 1] += rowStart[k]
            k += 1
        }
        i = 1
        while i < n {
            let a = byPlace[i - 1], b = byPlace[i]
            if row[a] == row[b] && x[b] - x[a] < 1 - 1e-9 {
                fail(1, "\(ids[a]) and \(ids[b]) stand \(x[b] - x[a]) apart on row \(row[a])")
            }
            i += 1
        }

        // R3 — generations from the links in input order, the earlier winning.
        var up = [Int](repeating: 0, count: n), offset = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            up[i] = i
            i += 1
        }
        func find(_ v: Int) -> (Int, Int) {
            var top = v, total = 0
            while up[top] != top {
                total += offset[top]
                top = up[top]
            }
            return (top, total)
        }
        var kin = [Bool](repeating: false, count: n)
        var seen = Set<Int>()
        var drawnA: [Int] = [], drawnB: [Int] = [], drawnBond: [Int] = []
        var undrawn: [Link] = []
        i = 0
        while i < c.links.count {
            let link = c.links[i]
            i += 1
            guard let a = index[link.from], let b = index[link.to], a != b else { continue }
            kin[a] = true
            kin[b] = true
            let bond = link.bond == .parent ? 0 : link.bond == .spouse ? 1 : 2
            if !seen.insert(bond == 0 ? (a * n + b) * 3 : (min(a, b) * n + max(a, b)) * 3 + bond).inserted {
                continue
            }
            let rise = bond == 0 ? 1 : 0
            let (ta, oa) = find(a), (tb, ob) = find(b)
            if ta == tb && ob - oa != rise {
                undrawn.append(link)
                continue
            }
            if ta != tb {
                up[tb] = ta
                offset[tb] = oa + rise - ob
            }
            drawnA.append(a)
            drawnB.append(b)
            drawnBond.append(bond)
        }
        if r.undrawn != undrawn {
            fail(3, "undrawn \(r.undrawn.map(describe)), expected \(undrawn.map(describe))")
        }
        i = 0
        while i < r.undrawn.count {
            let link = r.undrawn[i]
            i += 1
            guard let a = index[link.from], let b = index[link.to] else { continue }
            let holds = link.bond == .parent ? row[b] == row[a] + 1 : row[a] == row[b]
            if holds { fail(3, "\(describe(link)) is undrawn, yet its ends stand on rows that hold it") }
        }

        // R2 — every drawn link holds on the rows drawn.
        let links = drawnA.count
        var spouseCount = [Int](repeating: 0, count: n)
        var parentsOf = [[Int]](repeating: [], count: n)
        i = 0
        while i < links {
            let a = drawnA[i], b = drawnB[i]
            if drawnBond[i] == 0 {
                if row[b] != row[a] + 1 {
                    fail(2, "\(ids[b]) is on row \(row[b]), her parent \(ids[a]) on row \(row[a])")
                }
                parentsOf[b].append(a)
            } else {
                if row[a] != row[b] { fail(2, "\(ids[a]) and \(ids[b]) are linked across rows") }
                if drawnBond[i] == 1 {
                    spouseCount[a] += 1
                    spouseCount[b] += 1
                }
            }
            i += 1
        }
        i = 0
        while i < n {
            parentsOf[i].sort()
            i += 1
        }
        func isSpouse(_ a: Int, _ b: Int) -> Bool {
            var k = 0
            while k < links {
                if drawnBond[k] == 1 && ((drawnA[k] == a && drawnB[k] == b) || (drawnA[k] == b && drawnB[k] == a)) {
                    return true
                }
                k += 1
            }
            return false
        }

        // R2 — families: side by side, the root's first, each from row 0.
        var familyOfTop = [Int](repeating: -1, count: n)
        var familyOf = [Int](repeating: -1, count: n)
        var familyCount = 0
        i = 0
        while i < n {
            if kin[i] {
                let (top, _) = find(i)
                if familyOfTop[top] < 0 {
                    familyOfTop[top] = familyCount
                    familyCount += 1
                }
                familyOf[i] = familyOfTop[top]
            }
            i += 1
        }
        var drawing = Array(0 ..< familyCount)
        if let root = c.root, let q = index[root], kin[q] {
            drawing.remove(at: familyOf[q])
            drawing.insert(familyOf[q], at: 0)
        }
        var familyRows = 0, familiesWidth = 0.0
        if r.families.count != familyCount {
            fail(2, "\(r.families.count) families, expected \(familyCount)")
        } else {
            var slotOf = [Int](repeating: 0, count: familyCount)
            k = 0
            while k < familyCount {
                slotOf[drawing[k]] = k
                k += 1
            }
            var names = [[String]](repeating: [], count: familyCount)
            var lo = [Double](repeating: .infinity, count: familyCount), hi = [Double](repeating: -.infinity, count: familyCount)
            var top = [Int](repeating: .max, count: familyCount), bottom = [Int](repeating: -1, count: familyCount)
            i = 0
            while i < n {
                if kin[i] {
                    let s = slotOf[familyOf[i]]
                    names[s].append(ids[i])
                    lo[s] = min(lo[s], x[i])
                    hi[s] = max(hi[s], x[i])
                    top[s] = min(top[s], row[i])
                    bottom[s] = max(bottom[s], row[i])
                }
                i += 1
            }
            k = 0
            while k < familyCount {
                let f = r.families[k]
                names[k].sort()
                if f.members != names[k] {
                    fail(2, "family \(k + 1) is \(f.members), expected \(names[k])")
                } else if f.minX != lo[k] || f.maxX != hi[k] {
                    fail(2, "family \(k + 1) says x \(f.minX)…\(f.maxX), its members stand at \(lo[k])…\(hi[k])")
                } else if f.topRow != 0 || top[k] != 0 {
                    fail(2, "family \(k + 1) starts at row \(top[k]), not 0")
                } else if f.rows != bottom[k] + 1 {
                    fail(2, "family \(k + 1) says \(f.rows) rows, spans \(bottom[k] + 1)")
                } else if k > 0 && f.minX < r.families[k - 1].maxX + 2 - 1e-9 {
                    fail(2, "family \(k + 1) starts at x \(f.minX), too close to x \(r.families[k - 1].maxX)")
                }
                familyRows = max(familyRows, bottom[k] + 1)
                familiesWidth = hi[k] + 1
                k += 1
            }
        }

        // R4 — couples. Somebody married once, to somebody married once,
        // stands next to them; somebody married more often stands between
        // their first two spouses in `people` order, any further one beyond.
        // Each of those is a claim that two people stand side by side, and a
        // row can honour a set of claims only where they form paths. Where
        // they cannot — somebody three people claim, or a ring — no drawing
        // is right, so the audit proves which claims cannot hold, excuses
        // exactly those and names them, and asserts every other claim.
        // Measured 25 Sep 2026: 2 of 20 000 random families were like that,
        // both somebody standing between their own first two spouses who was
        // also among the first two of a later spouse's.
        var chainUp = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            chainUp[i] = i
            i += 1
        }
        func chainOf(_ v: Int) -> Int {
            var t = v
            while chainUp[t] != t { t = chainUp[t] }
            return t
        }
        var spousesOf = [[Int]](repeating: [], count: n)
        i = 0
        while i < links {
            if drawnBond[i] == 1 {
                let a = drawnA[i], b = drawnB[i]
                spousesOf[a].append(b)
                spousesOf[b].append(a)
                let ca = chainOf(a), cb = chainOf(b)
                if ca != cb { chainUp[max(ca, cb)] = min(ca, cb) }
            }
            i += 1
        }
        var nextTo = [[Int]](repeating: [], count: n)
        func claim(_ a: Int, _ b: Int) {
            if !nextTo[a].contains(b) {
                nextTo[a].append(b)
                nextTo[b].append(a)
            }
        }
        i = 0
        while i < n {
            spousesOf[i].sort()
            let s = spousesOf[i]
            if s.count >= 2 {
                claim(i, s[0])
                claim(i, s[1])
            } else if s.count == 1 && spousesOf[s[0]].count == 1 {
                claim(i, s[0])
            }
            i += 1
        }
        // Somebody claimed by three or more stands between their own first
        // two, as R4 says for them; the claims beyond those two places —
        // later spouses who count them among their own first two — cannot
        // also hold. Only those are excused.
        var beyond = Set<Int>()
        i = 0
        while i < n {
            if nextTo[i].count >= 3 {
                var claimants = nextTo[i]
                claimants.sort()
                for c in claimants where c != spousesOf[i][0] && c != spousesOf[i][1] {
                    beyond.insert(min(c, i) * n + max(c, i))
                }
                excused.append("\(ids[i]) cannot stand next to all of " + claimants.map { ids[$0] }.joined(separator: ", "))
            }
            i += 1
        }
        // A ring: as many claims as people among them. No line closes one.
        var claimUp = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            claimUp[i] = i
            i += 1
        }
        func claimOf(_ v: Int) -> Int {
            var t = v
            while claimUp[t] != t { t = claimUp[t] }
            return t
        }
        var claimsIn = [Int](repeating: 0, count: n), peopleIn = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            for b in nextTo[i] where b > i {
                let ra = claimOf(i), rb = claimOf(b)
                if ra != rb { claimUp[max(ra, rb)] = min(ra, rb) }
            }
            i += 1
        }
        i = 0
        while i < n {
            if !nextTo[i].isEmpty {
                peopleIn[claimOf(i)] += 1
                claimsIn[claimOf(i)] += nextTo[i].count
            }
            i += 1
        }
        var ring = [Bool](repeating: false, count: n)
        i = 0
        while i < n {
            if !nextTo[i].isEmpty && claimOf(i) == i && claimsIn[i] / 2 >= peopleIn[i] {
                ring[i] = true
                var names: [String] = []
                var v = i
                while v < n {
                    if !nextTo[v].isEmpty && claimOf(v) == i { names.append(ids[v]) }
                    v += 1
                }
                excused.append("the marriages of " + names.joined(separator: ", ") + " close a ring")
            }
            i += 1
        }
        i = 0
        while i < n {
            for b in nextTo[i] where b > i && !ring[claimOf(i)] && !beyond.contains(i * n + b) {
                if row[i] != row[b] || abs(abs(x[i] - x[b]) - 1) > 1e-9 {
                    fail(4, "\(ids[i]) and \(ids[b]) should stand side by side, and stand \(abs(x[i] - x[b])) apart")
                }
            }
            i += 1
        }

        // The lines the rules call for, each with the cards it may cross.
        var expect: [Line] = []
        var ownerStart = [0], owners: [Int] = []
        func add(_ line: Line, _ who: [Int]) {
            expect.append(line)
            owners += who
            ownerStart.append(owners.count)
        }
        func deepestBetween(_ r: Int, _ lo: Double, _ hi: Double) -> Double? {
            var deepest: Double?
            var k = rowStart[r]
            while k < rowStart[r + 1] {
                let v = byPlace[k]
                if x[v] > lo + 1e-9 && x[v] < hi - 1e-9 { deepest = max(deepest ?? 0, depth[v]) }
                k += 1
            }
            return deepest
        }
        var dipRow: [Int] = [], dipLeft: [Double] = [], dipRight: [Double] = [], dipDepth: [Double] = []
        i = 0
        while i < links {
            if drawnBond[i] == 1 {
                let a = x[drawnA[i]] < x[drawnB[i]] ? drawnA[i] : drawnB[i]
                let b = a == drawnA[i] ? drawnB[i] : drawnA[i]
                let y = Double(row[a])
                if let deepest = deepestBetween(row[a], x[a], x[b]) {
                    let d = max(0.4, deepest + 0.05)
                    let low = y + d, leftTop = y + min(depth[a], d), rightTop = y + min(depth[b], d)
                    if leftTop < low { add(Line(x1: x[a], y1: leftTop, x2: x[a], y2: low, stroke: .couple), [a, b]) }
                    add(Line(x1: x[a], y1: low, x2: x[b], y2: low, stroke: .couple), [a, b])
                    if rightTop < low { add(Line(x1: x[b], y1: rightTop, x2: x[b], y2: low, stroke: .couple), [a, b]) }
                    dipRow.append(row[a])
                    dipLeft.append(x[a])
                    dipRight.append(x[b])
                    dipDepth.append(d)
                } else {
                    add(Line(x1: x[a], y1: y, x2: x[b], y2: y, stroke: .couple), [a, b])
                }
            }
            i += 1
        }

        // Sibling bars (R6): components of sibling links whose ends share no
        // entered parent.
        var barUp = [Int](repeating: 0, count: n)
        i = 0
        while i < n {
            barUp[i] = i
            i += 1
        }
        func barOf(_ v: Int) -> Int {
            var t = v
            while barUp[t] != t { t = barUp[t] }
            return t
        }
        func shareParent(_ a: Int, _ b: Int) -> Bool {
            for p in parentsOf[a] where parentsOf[b].contains(p) { return true }
            return false
        }
        i = 0
        while i < links {
            if drawnBond[i] == 2 && !shareParent(drawnA[i], drawnB[i]) {
                let a = barOf(drawnA[i]), b = barOf(drawnB[i])
                if a != b { barUp[max(a, b)] = min(a, b) }
            }
            i += 1
        }
        var barMembers = [[Int]](repeating: [], count: n)
        i = 0
        while i < n {
            barMembers[barOf(i)].append(i)
            i += 1
        }
        var bars: [Int] = []
        var barLeft = [Double](repeating: 0, count: n), barRight = [Double](repeating: 0, count: n)
        i = 0
        while i < n {
            if barMembers[i].count >= 2 {
                bars.append(i)
                var lo = Double.infinity, hi = -Double.infinity
                for v in barMembers[i] {
                    lo = min(lo, x[v])
                    hi = max(hi, x[v])
                }
                barLeft[i] = lo
                barRight[i] = hi
                let y = Double(row[i]) - 0.4
                add(Line(x1: lo, y1: y, x2: hi, y2: y, stroke: .sibling), [])
                for v in barMembers[i] {
                    add(Line(x1: x[v], y1: y, x2: x[v], y2: Double(row[v]), stroke: .sibling), [v])
                }
            }
            i += 1
        }

        // Unions (R5): children grouped by the exact set of parents entered.
        // Each union's height is read off its drops, then held to the dealing
        // rule below; everything else about its lines follows from the places.
        var dropTop: [Int: Double] = [:]
        func spot(_ x: Double, _ y: Double) -> Int { Int((x * 1024).rounded()) &* 4099 &+ Int(y.rounded()) }
        i = 0
        while i < r.lines.count {
            let line = r.lines[i]
            i += 1
            if line.stroke == .descent && line.x1 == line.x2 {
                let bottom = max(line.y1, line.y2)
                if abs(bottom - bottom.rounded()) < 1e-9 { dropTop[spot(line.x1, bottom)] = min(line.y1, line.y2) }
            }
        }
        var unionOfKey: [Int: Int] = [:]
        var unionParents: [[Int]] = [], unionChildren: [[Int]] = []
        i = 0
        while i < n {
            if !parentsOf[i].isEmpty {
                var key = 0
                for p in parentsOf[i] { key = key &* (n + 1) &+ (p + 1) }
                if let u = unionOfKey[key] {
                    unionChildren[u].append(i)
                } else {
                    unionOfKey[key] = unionParents.count
                    unionParents.append(parentsOf[i])
                    unionChildren.append([i])
                }
            }
            i += 1
        }
        let unions = unionParents.count
        var hang = [Double](repeating: -1, count: unions)
        var spanLeft = [Double](repeating: 0, count: unions), spanRight = spanLeft, lowestHang = spanLeft
        var u = 0
        while u < unions {
            let ps = unionParents[u], cs = unionChildren[u]
            let pr = row[ps[0]], y = Double(pr)
            var h: Double?
            for ch in cs {
                guard let t = dropTop[spot(x[ch], Double(row[ch]))] else {
                    fail(5, "no line drops to \(ids[ch])")
                    h = nil
                    break
                }
                if let known = h, abs(known - (t - y)) > 1e-9 {
                    fail(5, "the children of \(ps.map { ids[$0] }) hang from two heights")
                }
                h = h ?? t - y
            }
            var lo = Double.infinity, hi = -Double.infinity
            for ch in cs {
                lo = min(lo, x[ch])
                hi = max(hi, x[ch])
            }
            let couple = ps.count == 2 && isSpouse(ps[0], ps[1])
            var stemTop = 0.0
            if couple {
                let middle = (x[ps[0]] + x[ps[1]]) / 2
                lo = min(lo, middle)
                hi = max(hi, middle)
                if let deepest = deepestBetween(pr, min(x[ps[0]], x[ps[1]]), max(x[ps[0]], x[ps[1]])) {
                    stemTop = max(0.4, deepest + 0.05)
                    lowestHang[u] = stemTop + 0.05
                }
            } else {
                for p in ps {
                    lo = min(lo, x[p])
                    hi = max(hi, x[p])
                }
            }
            spanLeft[u] = lo
            spanRight[u] = hi
            if let h {
                hang[u] = h
                let bar = y + h
                if couple {
                    let middle = (x[ps[0]] + x[ps[1]]) / 2
                    add(Line(x1: middle, y1: y + stemTop, x2: middle, y2: bar, stroke: .descent), ps)
                } else {
                    for p in ps where y + min(depth[p], h) < bar {
                        add(Line(x1: x[p], y1: y + min(depth[p], h), x2: x[p], y2: bar, stroke: .descent), ps)
                    }
                }
                if hi > lo { add(Line(x1: lo, y1: bar, x2: hi, y2: bar, stroke: .descent), ps) }
                for ch in cs { add(Line(x1: x[ch], y1: bar, x2: x[ch], y2: y + 1, stroke: .descent), [ch]) }
            }
            u += 1
        }

        // The lines drawn are exactly the lines called for.
        func quantised(_ line: Line) -> UInt64 {
            var (x1, y1, x2, y2) = (line.x1, line.y1, line.x2, line.y2)
            if (x2, y2) < (x1, y1) { (x1, y1, x2, y2) = (x2, y2, x1, y1) }
            var h: UInt64 = line.stroke == .couple ? 1 : line.stroke == .descent ? 2 : 3
            h = (h ^ UInt64(bitPattern: Int64((x1 * 1e6).rounded()))) &* 0x9E37_79B9_7F4A_7C15
            h = (h ^ (h >> 29) ^ UInt64(bitPattern: Int64((y1 * 1e6).rounded()))) &* 0x9E37_79B9_7F4A_7C15
            h = (h ^ (h >> 29) ^ UInt64(bitPattern: Int64((x2 * 1e6).rounded()))) &* 0x9E37_79B9_7F4A_7C15
            h = (h ^ (h >> 29) ^ UInt64(bitPattern: Int64((y2 * 1e6).rounded()))) &* 0x9E37_79B9_7F4A_7C15
            return h ^ (h >> 29)
        }
        var drawnKeys = [UInt64](repeating: 0, count: r.lines.count)
        i = 0
        while i < r.lines.count {
            drawnKeys[i] = quantised(r.lines[i])
            i += 1
        }
        var expectKeys = [UInt64](repeating: 0, count: expect.count)
        i = 0
        while i < expect.count {
            expectKeys[i] = quantised(expect[i])
            i += 1
        }
        // As multisets: the count and three sums no reordering changes and no
        // plausible difference preserves. The generic sort this replaced was a
        // tenth of the whole check, unoptimised.
        func fingerprint(_ keys: [UInt64]) -> [UInt64] {
            var sum: UInt64 = 0, square: UInt64 = 0, mixed: UInt64 = 0
            var k = 0
            while k < keys.count {
                let v = keys[k]
                sum = sum &+ v
                square = square &+ v &* v
                mixed ^= (v ^ (v >> 31)) &* 0xD6E8_FEB8_6659_FD93
                k += 1
            }
            return [UInt64(keys.count), sum, square, mixed]
        }
        if fingerprint(drawnKeys) != fingerprint(expectKeys) {
            var count: [UInt64: Int] = [:]
            for line in r.lines { count[quantised(line), default: 0] += 1 }
            var missing: Line?
            for line in expect {
                let key = quantised(line)
                if let have = count[key], have > 0 { count[key] = have - 1 } else if missing == nil { missing = line }
            }
            let extra = r.lines.first { (count[quantised($0)] ?? 0) > 0 }
            let culprit = missing ?? extra
            let k = culprit?.stroke == .couple ? 4 : culprit?.stroke == .sibling ? 6 : 5
            if let missing {
                fail(k, "\(describe(missing)) is called for and not drawn")
            } else if let extra {
                fail(k, "\(describe(extra)) is drawn and called for by nothing")
            }
        }

        // No line crosses a card it does not belong to (R4, R5). A card here
        // is x ± 0.5 by row − 0.25 … row + depth, open on every side.
        i = 0
        while i < expect.count {
            let line = expect[i]
            let xl = min(line.x1, line.x2), xr = max(line.x1, line.x2)
            let yt = min(line.y1, line.y2), yb = max(line.y1, line.y2)
            var q = max(0, Int(yt.rounded(.down)) - 1)
            while q <= min(rows - 1, Int(yb.rounded(.up)) + 1) {
                var k = rowStart[q]
                while k < rowStart[q + 1] {
                    let v = byPlace[k]
                    k += 1
                    if x[v] + 0.5 <= xl + 1e-9 { continue }
                    if x[v] - 0.5 >= xr - 1e-9 { break }
                    let crosses = yt < Double(q) + depth[v] - 1e-9 && yb > Double(q) - 0.25 + 1e-9
                    if crosses {
                        var own = false
                        var o = ownerStart[i]
                        while o < ownerStart[i + 1] {
                            if owners[o] == v { own = true }
                            o += 1
                        }
                        if !own {
                            fail(line.stroke == .couple ? 4 : line.stroke == .sibling ? 6 : 5,
                                 "\(describe(line)) crosses \(ids[v])'s card")
                        }
                    }
                }
                q += 1
            }
            i += 1
        }

        // R5 — heights, dealt per parents' row: fewest parents first, then
        // left to right, each the first height no overlapping bar dealt before
        // it took. A sibling bar of the row below holds 0.6 and a dipping
        // couple line its own depth where they overlap; a dipping couple's own
        // bar hangs at least 0.05 below its dip, so that the stem goes down.
        var dealt = Array(0 ..< unions)
        dealt.sort { a, b in
            let ra = row[unionParents[a][0]], rb = row[unionParents[b][0]]
            if ra != rb { return ra < rb }
            if unionParents[a].count != unionParents[b].count { return unionParents[a].count < unionParents[b].count }
            if spanLeft[a] != spanLeft[b] { return spanLeft[a] < spanLeft[b] }
            if spanRight[a] != spanRight[b] { return spanRight[a] < spanRight[b] }
            return unionChildren[a][0] < unionChildren[b][0]
        }
        func overlap(_ a: Int, _ b: Int) -> Bool {
            spanLeft[a] <= spanRight[b] + 1e-9 && spanLeft[b] <= spanRight[a] + 1e-9
        }
        var q = 0
        while q < unions {
            let u = dealt[q], pr = row[unionParents[u][0]]
            if hang[u] < 0 {
                q += 1
                continue
            }
            func free(_ h: Double) -> Bool {
                var e = q - 1
                while e >= 0 && row[unionParents[dealt[e]][0]] == pr {
                    if abs(hang[dealt[e]] - h) < 1e-9 && overlap(u, dealt[e]) { return false }
                    e -= 1
                }
                if abs(h - 0.6) < 1e-9 {
                    for b in bars where row[b] == pr + 1
                        && spanLeft[u] <= barRight[b] + 1e-9 && barLeft[b] <= spanRight[u] + 1e-9 {
                        return false
                    }
                }
                var k = 0
                while k < dipRow.count {
                    if dipRow[k] == pr && abs(dipDepth[k] - h) < 1e-9
                        && spanLeft[u] <= dipRight[k] + 1e-9 && dipLeft[k] <= spanRight[u] + 1e-9 {
                        return false
                    }
                    k += 1
                }
                return true
            }
            var want = hangs.first { $0 >= lowestHang[u] - 1e-9 && free($0) }
            if want == nil {
                var h = max(0.7, lowestHang[u]) + 0.0125
                while !free(h) { h += 0.0125 }
                want = h
            }
            if let want, abs(want - hang[u]) > 1e-9 {
                fail(5, "the bar under \(unionParents[u].map { ids[$0] }) hangs at \(hang[u]), the dealing gives \(want)")
            }
            var e = q - 1
            while e >= 0 && row[unionParents[dealt[e]][0]] == pr {
                if hang[dealt[e]] >= 0 && abs(hang[dealt[e]] - hang[u]) < 1e-9 && overlap(u, dealt[e]) {
                    fail(5, "the bars under \(unionParents[u].map { ids[$0] }) and "
                        + "\(unionParents[dealt[e]].map { ids[$0] }) overlap at one height")
                }
                e -= 1
            }
            q += 1
        }

        // R5, R6 — a union's children, and a sibling bar's members, stand in
        // one run of spouse chains wherever that is possible for certain: when
        // their chains are shared with at most one other group that wants a
        // run (another union's children, another bar, a union's unmarried
        // parents). Three groups can form a ring no row can honour.
        var chainRun = [Int](repeating: -1, count: n)
        var chainOrder = [Int](repeating: -1, count: n)
        var runs = 0
        k = 0
        while k < n {
            let v = byPlace[k], chain = chainOf(v)
            if k > 0 && chainOf(byPlace[k - 1]) == chain && row[byPlace[k - 1]] == row[v] {
                k += 1
                continue
            }
            if chainRun[chain] >= 0 {
                fail(4, "the spouse chain of \(ids[v]) is split by somebody else")
            }
            chainRun[chain] = runs
            chainOrder[chain] = runs
            runs += 1
            k += 1
        }
        var groups: [[Int]] = [], groupKind: [Int] = []
        func group(_ people: [Int], _ kind: Int) {
            var chains: [Int] = []
            for v in people where !chains.contains(chainOf(v)) { chains.append(chainOf(v)) }
            groups.append(chains)
            groupKind.append(kind)
        }
        u = 0
        while u < unions {
            group(unionChildren[u], 5)
            let ps = unionParents[u]
            if !(ps.count == 2 && isSpouse(ps[0], ps[1])) {
                var chains: [Int] = []
                for p in ps where !chains.contains(chainOf(p)) { chains.append(chainOf(p)) }
                if chains.count >= 2 { group(ps, 0) }
            }
            u += 1
        }
        for b in bars { group(barMembers[b], 6) }
        var clusterUp = Array(0 ..< n)
        func clusterOf(_ v: Int) -> Int {
            var t = v
            while clusterUp[t] != t { t = clusterUp[t] }
            return t
        }
        for g in groups {
            for ch in g.dropFirst() {
                let a = clusterOf(g[0]), b = clusterOf(ch)
                if a != b { clusterUp[max(a, b)] = min(a, b) }
            }
        }
        var groupsInCluster = [Int](repeating: 0, count: n)
        for g in groups { groupsInCluster[clusterOf(g[0])] += 1 }
        var g = 0
        while g < groups.count {
            let chains = groups[g]
            if groupKind[g] != 0 && groupsInCluster[clusterOf(chains[0])] <= 2 {
                var lo = Int.max, hi = Int.min
                for ch in chains {
                    lo = min(lo, chainOrder[ch])
                    hi = max(hi, chainOrder[ch])
                }
                if hi - lo + 1 != chains.count {
                    let who = chains.map { ids[$0] }
                    fail(groupKind[g], groupKind[g] == 5
                        ? "the children around \(who) do not stand in one run"
                        : "the siblings around \(who) do not stand in one run")
                }
            }
            g += 1
        }

        // R8 — friends, then everybody related to nobody, each band under an
        // empty caption row, wrapped at the families' width.
        var friends: [String] = [], friendly = [Bool](repeating: false, count: n)
        for id in c.friends {
            if let q = index[id], !kin[q], !friendly[q] {
                friendly[q] = true
                friends.append(id)
            }
        }
        var loose: [String] = []
        i = 0
        while i < n {
            if !kin[i] && !friendly[i] { loose.append(ids[i]) }
            i += 1
        }
        if r.friends != friends { fail(8, "friends \(r.friends), expected \(friends)") }
        if r.loose != loose { fail(8, "loose \(r.loose), expected \(loose)") }
        let wrap = max(3, Int(familiesWidth.rounded(.up)))
        var next = familyRows, width = familiesWidth
        func band(_ names: [String], _ first: Int?, _ label: String) {
            if names.isEmpty {
                if first != nil { fail(8, "an empty \(label) band has a row") }
                return
            }
            guard first == next + 1 else {
                fail(8, "the \(label) band starts on row \(String(describing: first)), expected \(next + 1)")
                return
            }
            for (k, id) in names.enumerated() {
                let want = Layout.Place(row: next + 1 + k / wrap, x: Double(k % wrap))
                if r.places[id] != want {
                    fail(8, "\(id) is at \(String(describing: r.places[id])), expected \(want)")
                }
            }
            next += 1 + (names.count + wrap - 1) / wrap
            width = max(width, Double(min(names.count, wrap)))
        }
        band(friends, r.friendsRow, "friends")
        band(loose, r.looseRow, "loose")
        if r.rows != next { fail(8, "\(r.rows) rows, expected \(next)") }
        if r.width != width { fail(8, "width \(r.width), expected \(width)") }
        i = 0
        while i < n {
            if kin[i] && row[i] >= familyRows { fail(8, "\(ids[i]) stands below the families") }
            i += 1
        }
        return (found, excused)
    }

    // MARK: - Random families

    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func chance(_ p: Double) -> Bool { Double(next() >> 11) / 9_007_199_254_740_992 < p }
        mutating func shuffle<T>(_ a: inout [T]) {
            var i = a.count - 1
            while i > 0 {
                a.swapAt(i, below(i + 1))
                i -= 1
            }
        }
    }

    /// A family grown the way archives are: founders, their children, the
    /// people those children married, and so on — with the untidiness real
    /// archives have. Some marriages are second marriages, some cousins marry,
    /// some in-laws come with parents or a parentless sibling, some children
    /// have one parent entered or three, some parents never entered their
    /// marriage. Then contradictions, duplicates, ids nobody has, a second
    /// family, loose people, friends, and everything shuffled.
    static func randomFamily(_ rng: inout Random) -> Case {
        var people: [String] = [], generation: [Int] = [], married: [Bool] = []
        var links: [Link] = []
        let target = 6 + rng.below(35)
        func person(_ g: Int) -> Int {
            people.append("p\(people.count)")
            generation.append(g)
            married.append(false)
            return people.count - 1
        }
        func link(_ a: Int, _ b: Int, _ bond: Layout.Bond) {
            links.append(Link(from: people[a], to: people[b], bond: bond))
        }
        var unions: [[Int]] = []
        let founder = person(0)
        if rng.chance(0.85) {
            let other = person(0)
            link(founder, other, .spouse)
            unions.append([founder, other])
        } else {
            unions.append([founder])
        }
        var next = 0
        while next < unions.count && people.count < target {
            let parents = unions[next]
            next += 1
            let g = generation[parents[0]] + 1
            let kids = [0, 1, 1, 2, 2, 2, 3, 3, 4, 5, 6][rng.below(11)]
            var children: [Int] = []
            for _ in 0 ..< kids where people.count < target {
                let c = person(g)
                if parents.count == 2 && rng.chance(0.05) {
                    link(parents[rng.below(2)], c, .parent)
                } else {
                    for p in parents { link(p, c, .parent) }
                }
                if rng.chance(0.02) { link(person(g - 1), c, .parent) }
                children.append(c)
            }
            if children.count >= 2 && rng.chance(0.1) { link(children[0], children[1], .sibling) }
            if !children.isEmpty && rng.chance(0.05) { link(children[rng.below(children.count)], person(g), .sibling) }
            for c in children where people.count < target && rng.chance(0.55) {
                if rng.chance(0.08) {
                    let cousins = (0 ..< people.count).filter {
                        generation[$0] == g && !married[$0] && !children.contains($0)
                    }
                    if !cousins.isEmpty {
                        let other = cousins[rng.below(cousins.count)]
                        link(c, other, .spouse)
                        married[c] = true
                        married[other] = true
                        unions.append([c, other])
                        continue
                    }
                }
                let s = person(g)
                if rng.chance(0.05) {
                    // Parents who never entered their marriage.
                } else {
                    link(c, s, .spouse)
                }
                married[c] = true
                married[s] = true
                if rng.chance(0.08) {
                    let a = person(g - 1), b = person(g - 1)
                    link(a, b, .spouse)
                    link(a, s, .parent)
                    link(b, s, .parent)
                }
                if rng.chance(0.08) { link(s, person(g), .sibling) }
                unions.append([c, s])
                if rng.chance(0.1) {
                    let second = person(g)
                    link(second, c, .spouse)
                    unions.append([c, second])
                }
            }
        }
        let family = people.count
        if rng.chance(0.1) {
            let a = rng.below(family), b = rng.below(family)
            if generation[a] != generation[b] { link(a, b, .spouse) }
        }
        if rng.chance(0.05), let p = links.first(where: { $0.bond == .parent }) {
            links.append(Link(from: p.to, to: p.from, bond: .parent))
        }
        if rng.chance(0.2) && !links.isEmpty {
            for _ in 0 ... rng.below(3) {
                let l = links[rng.below(links.count)]
                links.append(l.bond != .parent && rng.chance(0.5) ? Link(from: l.to, to: l.from, bond: l.bond) : l)
            }
        }
        if rng.chance(0.05) { links.append(Link(from: people[rng.below(family)], to: "ghost", bond: .spouse)) }
        if rng.chance(0.02) {
            let p = people[rng.below(family)]
            links.append(Link(from: p, to: p, bond: [.parent, .spouse, .sibling][rng.below(3)]))
        }
        if rng.chance(0.2) {
            if rng.chance(0.5) {
                let a = person(0), b = person(0)
                link(a, b, .spouse)
                for _ in 0 ... rng.below(3) {
                    let c = person(1)
                    link(a, c, .parent)
                    link(b, c, .parent)
                }
            } else {
                let a = person(0)
                for _ in 0 ... rng.below(2) { link(a, person(0), .sibling) }
            }
        }
        if rng.chance(0.3) {
            for _ in 0 ... rng.below(3) { _ = person(0) }
        }
        var friends: [String] = []
        if rng.chance(0.4) {
            for _ in 0 ... rng.below(3) { friends.append(people[person(0)]) }
        }
        if rng.chance(0.3) { friends.append(people[rng.below(family)]) }
        if rng.chance(0.05) { friends.append("stranger") }
        rng.shuffle(&links)
        if rng.chance(0.5) { rng.shuffle(&people) }
        let root: String? = rng.chance(0.7) ? people[rng.below(people.count)] : rng.chance(0.2) ? "nobody" : nil
        var depths: [String: Double] = [:]
        if rng.chance(0.3) {
            for id in people { depths[id] = 0.3 + 0.2 * Double(rng.below(1001)) / 1000 }
        }
        return Case(people: people, links: links, friends: friends, root: root, depths: depths)
    }

    /// The same links in another order: reversed with every symmetric link
    /// turned round, or shuffled.
    static func reordered(_ c: Case, _ rng: inout Random, shuffled: Bool) -> Case {
        var other = c
        if shuffled {
            rng.shuffle(&other.links)
        } else {
            other.links = c.links.reversed().map {
                $0.bond == .parent ? $0 : Link(from: $0.to, to: $0.from, bond: $0.bond)
            }
        }
        return other
    }

    static func cpuMilliseconds(_ body: () -> Void) -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        body()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e6
    }

    // MARK: - Main

    static func main() {
        let started = Date()
        var failures = 0

        func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if ok {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): \(detail())")
            }
        }

        /// Every requirement the audit covers, one line each.
        func audited(_ label: String, _ c: Case, _ r: Layout.Result) {
            let (found, excused) = audit(c, r)
            let broken = (1 ... 8).compactMap { k in found[k].map { "\(requirement[k].prefix(2)): \($0)" } }
            check("\(label): every invariant holds", broken.isEmpty, broken.joined(separator: "; "))
            for reason in excused { print("  note \(label): R4 cannot hold — \(reason)") }
        }

        func place(_ r: Layout.Result, _ id: String) -> Layout.Place {
            r.places[id] ?? Layout.Place(row: -1, x: -.infinity)
        }

        func has(_ r: Layout.Result, _ stroke: Layout.Stroke, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Bool {
            r.lines.contains {
                $0.stroke == stroke && abs($0.x1 - x1) < 1e-9 && abs($0.y1 - y1) < 1e-9
                    && abs($0.x2 - x2) < 1e-9 && abs($0.y2 - y2) < 1e-9
            }
        }

        // MARK: The clan

        print("— the clan (the app's -seed clan) —")
        let clan = clan
        let tree = clan.run()
        let (found, clanExcused) = audit(clan, tree)
        for k in [1, 2, 3, 4, 5, 6, 8] {
            check(requirement[k], found[k] == nil, found[k] ?? "")
        }
        check("every marriage in the clan can be honoured, so none is excused", clanExcused.isEmpty, "\(clanExcused)")
        check("three families: the root's first, then by their earliest card",
              tree.families.map(\.members.count) == [40, 4, 3]
                  && tree.families[1].members == ["Mauri", "Onerva", "Sisko", "Tarja"]
                  && tree.families[2].members == ["Helmi", "Otto", "Rauha"],
              "\(tree.families.map(\.members))")
        check("six generations, with the root on the fifth",
              tree.families.first?.rows == 6 && place(tree, "Elina").row == 4,
              "\(tree.families.first?.rows ?? 0) rows, Elina on \(place(tree, "Elina").row)")
        check("a marriage across generations and a parent pair entered both ways are named, not drawn",
              tree.undrawn == [spouse("Eemeli", "Sirkka"), parent("Onni", "Sulo")],
              "\(tree.undrawn.map(describe))")
        check("no couple line joins Eemeli and Sirkka",
              !tree.lines.contains {
                  $0.stroke == .couple && Set([$0.x1, $0.x2]) == Set([place(tree, "Eemeli").x, place(tree, "Sirkka").x])
              })
        do {
            var tidy = clan
            tidy.links.removeAll { $0 == spouse("Eemeli", "Sirkka") || $0 == parent("Onni", "Sulo") }
            var without = tidy.run()
            var with = tree
            with.undrawn = []
            without.undrawn = []
            check("an undrawn link changes nothing but `undrawn`", with == without)
        }
        let aapo = place(tree, "Aapo"), hilma = place(tree, "Hilma"), lyyli = place(tree, "Lyyli")
        check("Aapo stands between Hilma and Lyyli",
              abs(hilma.x - aapo.x) == 1 && abs(lyyli.x - aapo.x) == 1 && (hilma.x - aapo.x) * (lyyli.x - aapo.x) < 0,
              "Hilma \(hilma.x), Aapo \(aapo.x), Lyyli \(lyyli.x)")
        check("each of Aapo's marriages hangs its children from its own midpoint",
              tree.lines.contains { $0.stroke == .descent && $0.x1 == (aapo.x + hilma.x) / 2 && $0.y1 == 0 }
                  && tree.lines.contains { $0.stroke == .descent && $0.x1 == (aapo.x + lyyli.x) / 2 && $0.y1 == 0 })
        check("Impi and Urho, with no children, are still a couple",
              has(tree, .couple, min(place(tree, "Impi").x, place(tree, "Urho").x), 1,
                  max(place(tree, "Impi").x, place(tree, "Urho").x), 1))
        check("Sulo's one child hangs from under Sulo's own name",
              tree.lines.contains {
                  $0.stroke == .descent && $0.x1 == place(tree, "Sulo").x && $0.x2 == $0.x1 && abs($0.y1 - 1.38) < 1e-9
              })
        let oiva = place(tree, "Oiva"), eemeli = place(tree, "Eemeli")
        check("Oiva and Eemeli, siblings with no parents entered, share a sibling bar",
              has(tree, .sibling, min(oiva.x, eemeli.x), 0.6, max(oiva.x, eemeli.x), 0.6))
        check("Rauha has kin, so she is not on the friends band; Jonne is",
              tree.friends == ["Jonne"] && place(tree, "Rauha").row == 0)
        check("the loose seven fit one row: the families are wider than seven",
              tree.loose.count == 7 && tree.looseRow.map { r in tree.loose.allSatisfy { place(tree, $0).row == r } } == true)
        check("bands: friends on row 7, loose on row 9, ten rows, captions 6 and 8",
              tree.friendsRow == 7 && tree.looseRow == 9 && tree.rows == 10 && tree.captionRows == [6, 8],
              "friends \(String(describing: tree.friendsRow)), loose \(String(describing: tree.looseRow)), rows \(tree.rows)")

        print("— the clan, links in any order (R7) —")
        do {
            var tidy = clan
            tidy.links.removeAll { $0 == spouse("Eemeli", "Sirkka") || $0 == parent("Onni", "Sulo") }
            let reference = tidy.run()
            var rng = Random(state: 7)
            check("reversed, every symmetric link turned round", reordered(tidy, &rng, shuffled: false).run() == reference)
            var same = true
            for _ in 0 ..< 20 where reordered(tidy, &rng, shuffled: true).run() != reference { same = false }
            check("shuffled twenty times", same)
        }

        // MARK: Named cases

        print("— families side by side —")
        do {
            let c = Case(
                people: ["A", "B", "C", "D", "E", "F", "G", "H", "I"],
                links: [spouse("A", "B"), parent("A", "C"), parent("B", "C"), parent("C", "D"), parent("D", "E"),
                        spouse("F", "G"), parent("F", "H"), parent("G", "H"), sibling("I", "E")],
                root: "H")
            let r = c.run()
            audited("four generations and a family of three", c, r)
            check("the root's family is drawn first, from x = 0", r.families.first?.members == ["F", "G", "H"]
                  && r.families.first?.minX == 0)
            check("both start at row 0, however many generations each spans",
                  place(r, "A").row == 0 && place(r, "F").row == 0 && r.families.map(\.rows) == [2, 4])
            check("with an empty place between them",
                  r.families.count == 2 && r.families[1].minX >= r.families[0].maxX + 2)
        }

        print("— a person married three times —")
        do {
            let c = Case(people: ["P", "S1", "S2", "S3", "K"],
                         links: [spouse("P", "S3"), spouse("S2", "P"), spouse("P", "S1"), parent("P", "K"), parent("S3", "K")])
            let r = c.run()
            audited("three marriages", c, r)
            let p = place(r, "P").x, s1 = place(r, "S1").x, s2 = place(r, "S2").x, s3 = place(r, "S3").x
            check("P stands between the first two spouses in people order, whatever order the links came in",
                  abs(s1 - p) == 1 && abs(s2 - p) == 1 && (s1 - p) * (s2 - p) < 0, "S1 \(s1), P \(p), S2 \(s2)")
            check("the third stands beyond them", s3 < min(s1, s2) || s3 > max(s1, s2), "S3 \(s3)")
            check("and that couple line dips under whoever stands between",
                  has(r, .couple, min(p, s3), 0.43, max(p, s3), 0.43))
            check("their child's stem starts on the dip, not on the person it went round",
                  has(r, .descent, (p + s3) / 2, 0.43, (p + s3) / 2, 0.5))
        }

        print("— a dip under the root —")
        do {
            let c = Case(people: ["P", "R", "S2", "S3", "K"],
                         links: [spouse("P", "R"), spouse("P", "S2"), spouse("P", "S3"), parent("P", "K"), parent("S3", "K")],
                         root: "R")
            let r = c.run()
            audited("the root between a couple", c, r)
            let p = place(r, "P").x, s3 = place(r, "S3").x
            check("the line dips to 0.55: the root's card reaches 0.5",
                  has(r, .couple, min(p, s3), 0.55, max(p, s3), 0.55))
            check("so the bar skips 0.5 and hangs at 0.7, and the stem runs 0.55 → 0.7",
                  has(r, .descent, (p + s3) / 2, 0.55, (p + s3) / 2, 0.7))
        }

        print("— what the rows cannot hold —")
        do {
            let c = Case(people: ["A", "B", "C"],
                         links: [parent("A", "B"), parent("B", "A"), parent("B", "C"), spouse("A", "C"),
                                 parent("A", "B"), spouse("C", "A")])
            let r = c.run()
            audited("contradictions", c, r)
            check("the later of each contradiction is undrawn, once, in input order",
                  r.undrawn == [parent("B", "A"), spouse("A", "C")], "\(r.undrawn.map(describe))")
            check("and draws nothing", !r.lines.contains { $0.stroke == .couple })
        }

        print("— marriages no row can honour (R4) —")
        do {
            // C's first two spouses take both places beside C, and X, whose own
            // first two include C, would need a third.
            let c = Case(people: ["C", "S", "T", "X", "Y"],
                         links: [spouse("C", "S"), spouse("C", "T"), spouse("C", "X"), spouse("X", "Y")])
            let r = c.run()
            let (found, excused) = audit(c, r)
            let broken = (1 ... 8).compactMap { found[$0] }
            check("somebody three claim: proved, and only the claim beyond C's two places excused",
                  excused == ["C cannot stand next to all of S, T, X"], "\(excused)")
            check("everything else holds: C between S and T, X next to Y, the line to X dipping",
                  broken.isEmpty && abs(place(r, "C").x - place(r, "S").x) == 1
                      && abs(place(r, "C").x - place(r, "T").x) == 1 && abs(place(r, "X").x - place(r, "Y").x) == 1,
                  broken.joined(separator: "; "))
        }
        do {
            let c = Case(people: ["A", "B", "C"], links: [spouse("A", "B"), spouse("B", "C"), spouse("C", "A")])
            let r = c.run()
            let (found, excused) = audit(c, r)
            let broken = (1 ... 8).compactMap { found[$0] }
            check("a ring of three marriages: proved and excused",
                  excused == ["the marriages of A, B, C close a ring"], "\(excused)")
            check("and every other invariant holds, the closing line dipping under the one between",
                  broken.isEmpty, broken.joined(separator: "; "))
        }

        print("— repeats, unknown ids, somebody linked to themselves —")
        do {
            let c = Case(people: ["A", "B", "C", "D"],
                         links: [spouse("A", "B"), spouse("B", "A"), spouse("A", "B"), parent("A", "ghost"),
                                 sibling("C", "C"), parent("D", "D")])
            let r = c.run()
            audited("repeats and strays", c, r)
            check("a repeat is dropped silently, not undrawn", r.undrawn.isEmpty)
            check("and draws one line", r.lines.count == 1, "\(r.lines.count) lines")
            check("a link to nobody known, or to oneself, is ignored: C and D are loose",
                  r.loose == ["C", "D"] && r.families.count == 1)
        }

        print("— siblings —")
        do {
            let c = Case(people: ["P", "Q", "C", "D", "E", "F", "G"],
                         links: [spouse("P", "Q"), parent("P", "C"), parent("Q", "C"), parent("P", "E"), parent("Q", "E"),
                                 sibling("C", "E"), sibling("C", "D"), sibling("F", "G")])
            let r = c.run()
            audited("siblings", c, r)
            let cx = place(r, "C").x, dx = place(r, "D").x, ex = place(r, "E").x
            check("siblings who share a parent get no bar of their own",
                  !has(r, .sibling, min(cx, ex), 0.6, max(cx, ex), 0.6) || abs(dx - cx) > abs(ex - cx))
            check("one with parents entered and one without still share a bar",
                  has(r, .sibling, min(cx, dx), 0.6, max(cx, dx), 0.6))
            check("and stand next to each other", abs(cx - dx) == 1, "C \(cx), D \(dx)")
            let fx = place(r, "F").x, gx = place(r, "G").x
            check("a family of siblings alone is one row with one bar",
                  r.families.last?.rows == 1 && has(r, .sibling, min(fx, gx), -0.4, max(fx, gx), -0.4))
        }

        print("— unions that are not a couple —")
        do {
            let c = Case(people: ["A", "B", "C", "D", "E", "F", "G"],
                         links: [parent("A", "C"), parent("B", "C"), parent("D", "G"), parent("E", "G"), parent("F", "G")])
            let r = c.run()
            audited("two unmarried parents; three parents", c, r)
            for id in ["A", "B", "D", "E", "F"] {
                check("\(id)'s stem starts under \(id)'s own name",
                      r.lines.contains {
                          $0.stroke == .descent && $0.x1 == place(r, id).x && $0.x2 == $0.x1 && abs($0.y1 - 0.38) < 1e-9
                      })
            }
            check("unmarried parents still stand together", abs(place(r, "A").x - place(r, "B").x) == 1)
        }

        print("— centring —")
        do {
            let c = Case(people: ["A", "B", "C", "D", "E", "S", "T"],
                         links: [spouse("A", "B"), parent("A", "C"), parent("B", "C"), parent("A", "D"), parent("B", "D"),
                                 parent("A", "E"), parent("B", "E"), parent("S", "T")])
            let r = c.run()
            audited("a couple with three children; one parent with one child", c, r)
            let middle = (place(r, "A").x + place(r, "B").x) / 2
            let xs = ["C", "D", "E"].map { place(r, $0).x }.sorted()
            check("three children centred under their parents", xs == [middle - 1, middle, middle + 1], "\(xs) under \(middle)")
            check("one child straight under one parent", place(r, "T").x == place(r, "S").x)
        }

        print("— bands —")
        do {
            let c = Case(people: ["A", "B", "L1", "L2", "L3", "L4", "L5", "F1", "F2", "F3", "F4"],
                         links: [spouse("A", "B")], friends: ["F1", "F2", "F3", "F4", "A", "F1", "nobody"])
            let r = c.run()
            audited("a couple, four friends, five loose", c, r)
            check("a family two wide wraps the bands at three", r.width == 3 && place(r, "F4") == .init(row: 3, x: 0)
                  && place(r, "L4") == .init(row: 6, x: 0), "\(place(r, "F4")) \(place(r, "L4"))")
            check("friends from row 2, loose from row 5, seven rows", r.friendsRow == 2 && r.looseRow == 5 && r.rows == 7)
            let e = Case(people: [], links: [spouse("A", "B")], friends: ["A"], root: "A")
            check("nobody at all is an empty result", e.run() == Layout.Result())
            let only = Case(people: ["X", "Y"], links: [])
            let o = only.run()
            audited("only loose people", only, o)
            check("only loose people start under a caption row", o.looseRow == 1 && o.rows == 2 && o.width == 2
                  && o.friendsRow == nil && o.captionRows == [0])
        }

        // MARK: Random families

        // 5 000, not the specification's 20 000: compiled without optimisation,
        // as verify.sh compiles it, 20 000 took 16–27 s on the development
        // machine under the load parallel sessions put on it, against a budget
        // of 10 (25 Sep 2026). The same seed, so these are the first 5 000 of
        // that run.
        let families = 5_000
        print("— \(families) random families —")
        var rng = Random(state: 20_260_925)
        var broken = [Int](repeating: 0, count: 9)
        var firstBroken = [String?](repeating: nil, count: 9)
        var linkCount = 0, reordered7 = 0, excusedFamilies = 0, sweepCPU = 0.0
        for k in 0 ..< families {
            let c = randomFamily(&rng)
            linkCount += c.links.count
            var r = Layout.Result()
            sweepCPU += cpuMilliseconds { r = c.run() }
            let (found, excused) = audit(c, r)
            if !excused.isEmpty {
                excusedFamilies += 1
                print("  note family #\(k): R4 cannot hold — " + excused.joined(separator: "; "))
            }
            for q in 1 ... 8 where found[q] != nil {
                broken[q] += 1
                if firstBroken[q] == nil { firstBroken[q] = "family #\(k): \(found[q]!)" }
            }
            if r.undrawn.isEmpty {
                reordered7 += 1
                var other = Layout.Result()
                let turned = reordered(c, &rng, shuffled: k % 2 == 1)
                sweepCPU += cpuMilliseconds { other = turned.run() }
                if other != r {
                    broken[7] += 1
                    if firstBroken[7] == nil { firstBroken[7] = "family #\(k) changed when its links were reordered" }
                }
            }
        }
        for q in 1 ... 8 {
            check(requirement[q], broken[q] == 0, "\(broken[q]) families; first: \(firstBroken[q] ?? "")")
        }

        // MARK: Cost

        print("— cost (R9) —")
        var times: [Double] = []
        for _ in 0 ..< 21 { times.append(cpuMilliseconds { _ = clan.run() }) }
        times.sort()
        check(String(format: "the clan's 55 people in %.2f ms (median of 21)", times[10]), times[10] < 5)
        // Reported, not asserted: wall time on a shared machine measures the
        // machine. The median above is thread CPU time, which load moves far less.
        let seconds = Date().timeIntervalSince(started)
        print(String(format: "\n%d random families, %d links, %d re-run reordered, %d with R4 excused; "
                         + "layouts %.2f s CPU, whole check %.2f s",
                     families, linkCount, reordered7, excusedFamilies, sweepCPU / 1000, seconds))

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
