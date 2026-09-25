import Foundation

/// The word on every card of the family tree, said from the phone owner's
/// point of view — `.parent`, `.sibling`, `.spousesParent`. Gender-neutral in
/// both languages by construction, because the archive stores no gender.
///
/// Written from zero on 25 Sep 2026 together with the tree, and deliberately
/// blind to it: a word is a statement about the ties, not about where a card
/// stands, so nothing here reads rows or places.
///
/// **A word only when it is exact; otherwise no word.** Rule 4 holds for a
/// word as much as for a line: a card that calls somebody's cousin's child a
/// cousin is the archive asserting a relationship nobody entered. So a
/// relationship the table does not name gets nothing rather than the nearest
/// word — a great-great-grandparent is not a great-grandparent, a step-sibling
/// (up, spouse, down) is not a sibling, a co-spouse is nobody — and when the
/// shortest path names nothing, no longer one is consulted.
///
/// **Shortest distance, every reading of that length, then table order.** A
/// person reached along several shortest paths has several readings, and more
/// than one can be true at once: two siblings married to two siblings are each
/// other's sibling's spouse and spouse's sibling. The fixed order picks one
/// without looking at the order the ties arrived in, so the same archive says
/// the same word on every phone and after every sync. The price, which no
/// priority over the same readings can avoid: such a pair calls each other by
/// the same word rather than by mirror-image ones.
///
/// **Contradicting ties are ordered, not detected.** A pair entered as each
/// other's parent reads `.parent` both ways, because up comes before down in
/// the table. The tree can keep the earlier link and name the other; the words
/// cannot pick a side that way, because they must not depend on the order of
/// `ties`.
///
/// **The input is trusted, and nothing else is.** The caller filters out
/// unconfirmed and deleted relations. A tie naming an id that is not in
/// `people` is ignored — so a parent whose card is not there makes nobody
/// anybody's sibling.
enum Kinship {
    enum Bond: Equatable { case parent /* from is the parent of to */, spouse, sibling, friend }

    struct Tie: Hashable {
        let from: String
        let to: String
        let bond: Bond
    }

    /// Every word the tree can say, from the root's point of view. The raw
    /// value is the Finnish word, which is the localisation key.
    enum Word: String, CaseIterable {
        case parent = "Vanhempasi"
        case grandparent = "Isovanhempasi"
        case greatGrandparent = "Isoisovanhempasi"
        case child = "Lapsesi"
        case grandchild = "Lapsenlapsesi"
        case greatGrandchild = "Lastenlastenlapsesi"
        case spouse = "Puolisosi"
        case sibling = "Sisaruksesi"
        case parentsSibling = "Vanhempasi sisarus"
        case cousin = "Serkkusi"
        case grandparentsSibling = "Isovanhempasi sisarus"
        case parentsCousin = "Vanhempasi serkku"
        case secondCousin = "Pikkuserkkusi"
        case siblingsChild = "Sisaruksesi lapsi"
        case siblingsGrandchild = "Sisaruksesi lapsenlapsi"
        case siblingsSpouse = "Sisaruksesi puoliso"
        case spousesParent = "Puolisosi vanhempi"
        case spousesSibling = "Puolisosi sisarus"
        case spousesChild = "Puolisosi lapsi"
        case childsSpouse = "Lapsesi puoliso"
        case parentsSpouse = "Vanhempasi puoliso"
        case friend = "Ystäväsi"

        /// The word as the phone shows it, looked up in the app's tables.
        ///
        /// One literal per case, never built from `rawValue`:
        /// `localisation-check.mjs` finds a key by reading the source for
        /// `String(localized:)` literals, and a key assembled at runtime is one
        /// it cannot see — the English table would never get it, and an
        /// English phone would read Finnish on every card.
        var label: String {
            switch self {
            case .parent: return String(localized: "Vanhempasi")
            case .grandparent: return String(localized: "Isovanhempasi")
            case .greatGrandparent: return String(localized: "Isoisovanhempasi")
            case .child: return String(localized: "Lapsesi")
            case .grandchild: return String(localized: "Lapsenlapsesi")
            case .greatGrandchild: return String(localized: "Lastenlastenlapsesi")
            case .spouse: return String(localized: "Puolisosi")
            case .sibling: return String(localized: "Sisaruksesi")
            case .parentsSibling: return String(localized: "Vanhempasi sisarus")
            case .cousin: return String(localized: "Serkkusi")
            case .grandparentsSibling: return String(localized: "Isovanhempasi sisarus")
            case .parentsCousin: return String(localized: "Vanhempasi serkku")
            case .secondCousin: return String(localized: "Pikkuserkkusi")
            case .siblingsChild: return String(localized: "Sisaruksesi lapsi")
            case .siblingsGrandchild: return String(localized: "Sisaruksesi lapsenlapsi")
            case .siblingsSpouse: return String(localized: "Sisaruksesi puoliso")
            case .spousesParent: return String(localized: "Puolisosi vanhempi")
            case .spousesSibling: return String(localized: "Puolisosi sisarus")
            case .spousesChild: return String(localized: "Puolisosi lapsi")
            case .childsSpouse: return String(localized: "Lapsesi puoliso")
            case .parentsSpouse: return String(localized: "Vanhempasi puoliso")
            case .friend: return String(localized: "Ystäväsi")
            }
        }
    }

    /// The word for everybody who has one. `root` itself is never in the
    /// result. Ties may repeat or contradict; ids not in `people` are ignored.
    static func words(from root: String, people: [String], ties: [Tie]) -> [String: Word] {
        var slot: [String: Int] = [:]
        slot.reserveCapacity(people.count)
        var ids: [String] = []
        ids.reserveCapacity(people.count)
        for id in people where slot[id] == nil {
            slot[id] = ids.count
            ids.append(id)
        }
        guard let origin = slot[root] else { return [:] }

        // Everybody one step away, per person, one list per kind of step. A
        // tie entered twice is listed twice, which costs a repeat and changes
        // nothing: readings are a set, and a distance is settled the first
        // time somebody is reached.
        var parents = [[Int]](repeating: [], count: ids.count)
        var children = parents, spouses = parents, siblings = parents
        var friends: [Int] = []
        for tie in ties {
            guard let from = slot[tie.from], let to = slot[tie.to], from != to else { continue }
            switch tie.bond {
            case .parent:
                parents[to].append(from)
                children[from].append(to)
            case .spouse:
                spouses[from].append(to)
                spouses[to].append(from)
            case .sibling:
                siblings[from].append(to)
                siblings[to].append(from)
            case .friend:
                // Either way round, as `RelationKind.friendOf` is symmetric —
                // but only the root's own, because no path continues through
                // a friend: a friend's mother is nothing of yours.
                if from == origin { friends.append(to) }
                if to == origin { friends.append(from) }
            }
        }

        // Breadth first, one depth at a time, so that a person's readings are
        // exactly those of their shortest paths.
        let automaton = Self.automaton
        var distance = [Int](repeating: -1, count: ids.count)
        var readings = [UInt64](repeating: 0, count: ids.count)
        distance[origin] = 0
        readings[origin] = automaton.start
        var frontier = [origin], reached: [Int] = [], depth = 0

        /// One step from `person` to each of `others` but `person`, carrying
        /// `carried`. The first arrival settles a distance and every arrival
        /// at that distance adds its readings, so somebody reached at an
        /// earlier depth keeps what that depth gave them.
        func step(from person: Int, to others: [Int], carrying carried: UInt64) {
            for other in others where other != person {
                if distance[other] < 0 {
                    distance[other] = depth
                    reached.append(other)
                }
                if distance[other] == depth { readings[other] |= carried }
            }
        }
        while depth < automaton.reach, !frontier.isEmpty {
            depth += 1
            for person in frontier {
                let before = readings[person]
                step(from: person, to: parents[person], carrying: automaton.advance(before, by: .up))
                step(from: person, to: children[person], carrying: automaton.advance(before, by: .down))
                step(from: person, to: spouses[person], carrying: automaton.advance(before, by: .spouse))
                // A shared parent is a sibling step even when nobody entered
                // the tie, so half-siblings count: every child of a parent,
                // the person excepted. Two sibling steps are not one — a
                // half-sibling's half-sibling can be a stranger, and the table
                // has no row for them.
                let sideways = automaton.advance(before, by: .sibling)
                step(from: person, to: siblings[person], carrying: sideways)
                for parent in parents[person] {
                    step(from: person, to: children[parent], carrying: sideways)
                }
            }
            frontier = reached
            reached = []
        }

        var words: [String: Word] = [:]
        words.reserveCapacity(ids.count)
        for person in ids.indices where person != origin {
            let matched = readings[person] & automaton.rows
            if matched != 0 { words[ids[person]] = table[matched.trailingZeroBitCount].word }
        }
        // A friend is one step away whatever else they are, and the friend row
        // comes after every row of length one. So a relative one step away
        // keeps that word, and everybody else the root calls a friend is a
        // friend — a cousin included, because the shortest reading wins.
        for friend in friends where distance[friend] != 1 {
            words[ids[friend]] = .friend
        }
        return words
    }

    // MARK: - The table

    /// One step of a reading. A friendship is not one: it is only ever a whole
    /// path, handled at the end of `words`.
    private enum Step: Int, CaseIterable {
        case up, down, spouse, sibling

        /// `allCases.count`, once: `allCases` builds a new array on every
        /// access, and the search asks for this on every step it takes.
        static let count = allCases.count
    }

    /// The rows in priority order: a person with several shortest readings
    /// gets the first row any of them matches. `.friend` is the table's last
    /// row and is not here, for the reason `Step` gives.
    private static let table: [(steps: [Step], word: Word)] = [
        ([.up], .parent),
        ([.up, .up], .grandparent),
        ([.up, .up, .up], .greatGrandparent),
        ([.down], .child),
        ([.down, .down], .grandchild),
        ([.down, .down, .down], .greatGrandchild),
        ([.spouse], .spouse),
        ([.sibling], .sibling),
        ([.up, .sibling], .parentsSibling),
        ([.up, .sibling, .down], .cousin),
        ([.up, .up, .sibling], .grandparentsSibling),
        ([.up, .up, .sibling, .down], .parentsCousin),
        ([.up, .up, .sibling, .down, .down], .secondCousin),
        ([.sibling, .down], .siblingsChild),
        ([.sibling, .down, .down], .siblingsGrandchild),
        ([.sibling, .spouse], .siblingsSpouse),
        ([.spouse, .up], .spousesParent),
        ([.spouse, .sibling], .spousesSibling),
        ([.spouse, .down], .spousesChild),
        ([.down, .spouse], .childsSpouse),
        ([.up, .spouse], .parentsSpouse),
    ]

    /// A person's readings, carried as one bit per prefix of a row rather
    /// than as a list of paths. A reading that is no row's prefix can never
    /// become a row, so it is dropped the moment it stops being one; how many
    /// shortest paths lead somewhere stops mattering, and the first match in
    /// table order is the lowest bit set, because the rows come first.
    private struct Automaton {
        /// Prefix `i` extended by a step, at `i * Step.count + step.rawValue`,
        /// as another prefix's index, or -1 where the longer reading is
        /// nobody's prefix.
        let extend: [Int]
        let rows: UInt64
        let start: UInt64
        /// Nobody further away than the longest row can match one, so the
        /// search stops there: five steps, a second cousin.
        let reach: Int

        func advance(_ readings: UInt64, by step: Step) -> UInt64 {
            var left = readings
            var moved: UInt64 = 0
            while left != 0 {
                let target = extend[left.trailingZeroBitCount * Step.count + step.rawValue]
                if target >= 0 { moved |= UInt64(1) << UInt64(target) }
                left &= left - 1
            }
            return moved
        }
    }

    private static let automaton: Automaton = {
        // Every prefix of every row: the rows in table order, then any prefix
        // that is not itself a row (none today — every prefix of a row is a
        // row), including the empty one the root starts from.
        var prefixes = table.map(\.steps)
        for row in table {
            for length in 0 ..< row.steps.count {
                let prefix = Array(row.steps.prefix(length))
                if !prefixes.contains(prefix) { prefixes.append(prefix) }
            }
        }
        precondition(prefixes.count <= UInt64.bitWidth, "a reading is one bit of a UInt64")
        var extend = [Int](repeating: -1, count: prefixes.count * Step.count)
        for (index, prefix) in prefixes.enumerated() {
            for step in Step.allCases {
                extend[index * Step.count + step.rawValue] = prefixes.firstIndex(of: prefix + [step]) ?? -1
            }
        }
        return Automaton(
            extend: extend,
            rows: table.count == UInt64.bitWidth ? ~0 : (1 << UInt64(table.count)) - 1,
            start: prefixes.firstIndex(of: []).map { UInt64(1) << UInt64($0) } ?? 0,
            reach: table.map(\.steps.count).max() ?? 0
        )
    }()
}
