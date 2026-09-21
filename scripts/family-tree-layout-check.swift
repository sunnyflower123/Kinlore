// Checks where the family tree puts people, and the lines it draws between them.
//
// The drawing is the part a screenshot can check. Where somebody lands is the
// part it cannot: a child one row above her mother still draws, a couple split
// by a stranger still draws, and a brother drawn with no line reads as a
// guest. Every one of those is silent, and every one of them is a wrong fact
// about a family, which is the thing rule 4 exists to prevent.
//
// Costs nothing: no simulator, no store, no network. Run it after touching
// FamilyTreeLayout.swift — the command is in CLAUDE.md.
//
//   swiftc -parse-as-library -o /tmp/family-tree-layout-check \
//     scripts/family-tree-layout-check.swift ios/Kinlore/Services/FamilyTreeLayout.swift

import Foundation

@main
enum FamilyTreeLayoutCheck {
    static func main() {
        var failures = 0

        func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if ok {
                print("  ok   \(label)")
            } else {
                failures += 1
                let why = detail()
                print("  FAIL \(label)\(why.isEmpty ? "" : ": \(why)")")
            }
        }

        typealias L = FamilyTreeLayout.Link
        func parent(_ p: String, _ c: String) -> L { L(from: p, to: c, kind: .parent) }
        func spouse(_ a: String, _ b: String) -> L { L(from: a, to: b, kind: .spouse) }
        func sibling(_ a: String, _ b: String) -> L { L(from: a, to: b, kind: .sibling) }

        /// Nobody shares a place, in any layout — the one property every other
        /// check would otherwise have to repeat.
        func noOverlap(_ r: FamilyTreeLayout.Result) -> Bool {
            let places = r.placements.values.map { "\($0.row):\($0.x)" }
            return Set(places).count == places.count
        }

        /// No line is drawn over somebody it is not about, which is the one
        /// way this drawing can state a relationship the archive does not
        /// contain. Two shapes do it and both come from a second marriage:
        /// the line to the second wife drawn straight through the first, and
        /// the drop to that marriage's children, which starts from between
        /// the two and — with a wife on each side of him — starts on her.
        func throughSomebody(_ r: FamilyTreeLayout.Result, _ links: [L]) -> [String] {
            var wrong: [String] = []
            let place = r.placements.sorted { $0.key < $1.key }

            for line in r.segments where line.kind == .couple && line.y1 == line.y2 {
                for (id, p) in place
                where Double(p.row) == line.y1 && line.x1 < p.x && p.x < line.x2 {
                    wrong.append("a marriage is drawn through \(id)")
                }
            }

            var folksOf: [String: Set<String>] = [:]
            for link in links where link.kind == .parent {
                guard let up = r.placements[link.from], let down = r.placements[link.to],
                      down.row == up.row + 1 else { continue }
                folksOf[link.to, default: []].insert(link.from)
            }
            for folks in Set(folksOf.values.map { $0.sorted() }).sorted(by: { $0.joined() < $1.joined() }) {
                let places = folks.compactMap { r.placements[$0] }
                guard places.count == folks.count, let row = places.first?.row else { continue }
                let anchor = places.map(\.x).reduce(0, +) / Double(places.count)
                let fromTheirOwnRow = r.segments.contains {
                    $0.kind == .descent && $0.x1 == anchor && $0.x2 == anchor && $0.y1 == Double(row)
                }
                guard fromTheirOwnRow else { continue }
                for (id, p) in place where p.row == row && p.x == anchor && !folks.contains(id) {
                    wrong.append("the children of \(folks.joined(separator: " and ")) hang from \(id)")
                }
            }
            return wrong
        }

        print("— a parent is above the child —")
        do {
            let r = FamilyTreeLayout.layout(people: ["Aino", "Toivo"], links: [parent("Aino", "Toivo")])
            check("the child is one row below", r.placements["Toivo"]?.row == (r.placements["Aino"]?.row ?? -9) + 1)
            check("the parent is on the top row", r.placements["Aino"]?.row == 0)
            // The tree grows from whoever came first in the list, and the child
            // coming first must not put her above her mother.
            let reversed = FamilyTreeLayout.layout(people: ["Toivo", "Aino"], links: [parent("Aino", "Toivo")])
            check("and it does not depend on who is listed first", reversed.placements["Aino"]?.row == 0 && reversed.placements["Toivo"]?.row == 1)
            check("two rows", r.rows == 2)
        }

        print("— a couple sits side by side —")
        do {
            let r = FamilyTreeLayout.layout(people: ["Eeva", "Kalle"], links: [spouse("Eeva", "Kalle")])
            let a = r.placements["Eeva"], b = r.placements["Kalle"]
            check("on one row", a?.row == b?.row)
            check("one place apart", abs((a?.x ?? 0) - (b?.x ?? 9)) == 1)
            check("with a line between them", r.segments.contains { $0.y1 == $0.y2 && $0.y1 == Double(a?.row ?? -1) })
        }

        print("— children sit under their parents, together —")
        do {
            let people = ["Mummo", "Vaari", "Liisa", "Matti", "Sanni"]
            let links = [
                spouse("Mummo", "Vaari"),
                parent("Mummo", "Liisa"), parent("Vaari", "Liisa"),
                parent("Mummo", "Matti"), parent("Vaari", "Matti"),
                parent("Mummo", "Sanni"), parent("Vaari", "Sanni"),
            ]
            let r = FamilyTreeLayout.layout(people: people, links: links)
            let p = r.placements
            check("parents on row 0", p["Mummo"]?.row == 0 && p["Vaari"]?.row == 0)
            check("children on row 1", ["Liisa", "Matti", "Sanni"].allSatisfy { p[$0]?.row == 1 })
            check("nobody shares a place", noOverlap(r))
            let children = ["Liisa", "Matti", "Sanni"].compactMap { p[$0]?.x }
            let xs = children.sorted()
            check("the children are adjacent", zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 == 1 }, "\(xs)")
            let parentMiddle = ((p["Mummo"]?.x ?? 0) + (p["Vaari"]?.x ?? 0)) / 2
            let childMiddle = children.reduce(0, +) / Double(children.count)
            check("and centred under the couple", abs(parentMiddle - childMiddle) <= 1, "parents \(parentMiddle), children \(childMiddle)")
            // One bracket: a vertical from between the parents, a bar, and one
            // drop to each child.
            let drops = r.segments.filter { $0.x1 == $0.x2 && $0.y2 == 1 }
            check("a line drops to every child", Set(drops.map(\.x1)) == Set(children), "\(drops)")
            check("from between the parents", r.segments.contains { $0.x1 == parentMiddle && $0.x2 == parentMiddle && $0.y1 == 0 })
        }

        print("— somebody who married in stays beside their spouse —")
        do {
            // Liisa is the family's; Pekka married in and has no parents here.
            let people = ["Mummo", "Liisa", "Pekka", "Helmi"]
            let links = [
                parent("Mummo", "Liisa"),
                spouse("Liisa", "Pekka"),
                parent("Liisa", "Helmi"), parent("Pekka", "Helmi"),
            ]
            let r = FamilyTreeLayout.layout(people: people, links: links)
            let p = r.placements
            check("three generations", r.rows == 3)
            check("Pekka is on Liisa's row", p["Pekka"]?.row == p["Liisa"]?.row)
            check("beside her", abs((p["Pekka"]?.x ?? 0) - (p["Liisa"]?.x ?? 9)) == 1)
            check("their daughter is below both", p["Helmi"]?.row == 2)
            check("nobody shares a place", noOverlap(r))
        }

        print("— siblings with no parents entered still belong together —")
        do {
            let r = FamilyTreeLayout.layout(people: ["Eero", "Liisa"], links: [sibling("Eero", "Liisa")])
            let a = r.placements["Eero"], b = r.placements["Liisa"]
            check("one row", a?.row == b?.row)
            check("a bar joins them", r.segments.contains { $0.y1 == $0.y2 && $0.y1 < Double(a?.row ?? 0) })
        }

        // A person is of one generation, so some bond somebody entered may have
        // nowhere to go. Which one goes is not for the walk to decide by
        // accident, and which ones went is not a secret.
        print("— a generation comes from blood, and what will not fit is named —")
        do {
            // Eemeli is Oiva's brother and Sirkka's husband, and Sirkka is
            // Oiva's daughter. One of those two bonds cannot be drawn, and
            // the marriage is the one that says nothing about a generation.
            // The order matters: the walk starts at Sirkka and meets the
            // marriage one step before the brotherhood, which is exactly the
            // shape that used to answer wrong.
            let r = FamilyTreeLayout.layout(
                people: ["Sirkka", "Eemeli", "Oiva"],
                links: [spouse("Eemeli", "Sirkka"), parent("Oiva", "Sirkka"), sibling("Oiva", "Eemeli")]
            )
            check("the brother keeps his brother's generation",
                  r.placements["Eemeli"]?.row == r.placements["Oiva"]?.row,
                  "Eemeli \(String(describing: r.placements["Eemeli"])), Oiva \(String(describing: r.placements["Oiva"]))")
            check("the daughter is a generation below both",
                  r.placements["Sirkka"]?.row == (r.placements["Oiva"]?.row ?? -9) + 1)
            check("the marriage is what cannot be drawn",
                  r.undrawn == [spouse("Eemeli", "Sirkka")], "\(r.undrawn)")
            check("and no couple's line is drawn for it",
                  !r.segments.contains { $0.kind == .couple }, "\(r.segments)")
            check("nobody shares a place", noOverlap(r))

            // Which is an order and not a ban: whoever married in has no
            // blood relative in the tree at all, and their spouse is the only
            // answer there is for them.
            let wed = FamilyTreeLayout.layout(
                people: ["Aino", "Toivo", "Kaisa"],
                links: [parent("Aino", "Toivo"), spouse("Toivo", "Kaisa")]
            )
            check("somebody who married in still has a generation", wed.placements["Kaisa"]?.row == 1)
            check("beside their spouse",
                  abs((wed.placements["Kaisa"]?.x ?? 0) - (wed.placements["Toivo"]?.x ?? 9)) == 1)
            check("and a family that fits reports nothing undrawn", wed.undrawn.isEmpty, "\(wed.undrawn)")
        }

        // Entered twice and then backwards, which is what a proposal confirmed
        // from both ends looks like in the archive.
        print("— a pair each entered as the other's parent keeps one line and names the other —")
        do {
            let r = FamilyTreeLayout.layout(
                people: ["Sulo", "Onni"],
                links: [parent("Sulo", "Onni"), parent("Onni", "Sulo")]
            )
            check("the first answer stands", r.placements["Sulo"]?.row == 0 && r.placements["Onni"]?.row == 1)
            check("the second is named rather than drawn", r.undrawn == [parent("Onni", "Sulo")], "\(r.undrawn)")
            check("two rows and not a loop", r.rows == 2)
            // A descent is drawn in two pieces, down to the bracket and down
            // from it, so what is asserted is that every piece runs downwards.
            check("the line runs down to the child and none back up",
                  r.segments.allSatisfy { $0.kind == .descent && $0.y1 <= $0.y2 }, "\(r.segments)")
        }

        // Since 13 Sep 2026 they are in the picture rather than in a list under
        // it: a family is as big as everybody in it, related yet or not.
        print("— people nobody is related to are drawn below the tree, apart —")
        do {
            let r = FamilyTreeLayout.layout(people: ["Aino", "Toivo", "Kaarina"], links: [parent("Aino", "Toivo")])
            let k = r.placements["Kaarina"]
            check("Kaarina is known as related to nobody", r.unconnected == ["Kaarina"])
            check("and placed", k != nil)
            check("below every generation, with a row between", k?.row == 3 && r.looseRow == 3, "\(String(describing: k)), looseRow \(String(describing: r.looseRow))")
            check("the row between is empty, for the caption", !r.placements.values.contains { $0.row == 2 })
            check("the rows count her", r.rows == 4)
            check("no line reaches her", !r.segments.contains { $0.y1 >= 2 || $0.y2 >= 2 }, "\(r.segments)")
            check("nobody shares a place", noOverlap(r))

            // As many to a row as the tree is wide, never fewer than three.
            let many = FamilyTreeLayout.layout(people: ["Eeva", "Kalle", "A", "B", "C", "D"], links: [spouse("Eeva", "Kalle")])
            let loose = ["A", "B", "C", "D"].compactMap { many.placements[$0] }
            check("four people related to nobody are all placed", loose.count == 4)
            check("three to a row under a couple", loose.filter { $0.row == many.looseRow }.count == 3, "\(loose)")
            check("and the fourth on the row below", many.placements["D"]?.row == (many.looseRow ?? -9) + 1)
            check("in the order given", many.placements["A"]?.x == 0 && many.placements["C"]?.x == 2 && many.placements["D"]?.x == 0)
            check("the width covers them", many.width >= 3)
            check("nobody shares a place", noOverlap(many))

            // With nobody related yet the caption still has its row, at the top.
            let alone = FamilyTreeLayout.layout(people: ["Aino", "Toivo"], links: [])
            check("nobody related sits under an empty top row", alone.looseRow == 1 && alone.placements["Aino"]?.row == 1 && alone.placements["Toivo"]?.row == 1)
            check("side by side", alone.placements["Aino"]?.x == 0 && alone.placements["Toivo"]?.x == 1)
            check("with no lines", alone.segments.isEmpty)
            check("two rows, the first empty", alone.rows == 2 && !alone.placements.values.contains { $0.row == 0 })

            let related = FamilyTreeLayout.layout(people: ["Eeva", "Kalle"], links: [spouse("Eeva", "Kalle")])
            check("everybody related leaves nobody apart", related.looseRow == nil && related.unconnected.isEmpty)

            let empty = FamilyTreeLayout.layout(people: [], links: [])
            check("and no people is no tree", empty == FamilyTreeLayout.Result())
        }

        // A friend is not a generation (21 Sep 2026): somebody joined to the
        // family by friendship alone is drawn apart, on a band of their own
        // above the people related to nobody, with no line — a line would
        // read as descent. The layout never sees the friendship itself; the
        // screen names who is joined by one alone.
        print("— a friend is drawn apart, above the people related to nobody —")
        do {
            let r = FamilyTreeLayout.layout(
                people: ["Aino", "Toivo", "Jonne", "Kustaa"],
                links: [parent("Aino", "Toivo")],
                aside: ["Jonne"]
            )
            check("Jonne is known as a friend and Kustaa as related to nobody", r.aside == ["Jonne"] && r.unconnected == ["Kustaa"])
            check("the friend is below every generation, with a row between",
                  r.placements["Jonne"]?.row == 3 && r.asideRow == 3,
                  "\(String(describing: r.placements["Jonne"])), asideRow \(String(describing: r.asideRow))")
            check("and Kustaa below the friends, with a row between",
                  r.placements["Kustaa"]?.row == 5 && r.looseRow == 5,
                  "\(String(describing: r.placements["Kustaa"])), looseRow \(String(describing: r.looseRow))")
            check("both rows between are empty, for the captions",
                  r.captionRows == [2, 4] && !r.placements.values.contains { $0.row == 2 || $0.row == 4 })
            check("the generations end at the first caption", r.bandStart == 2)
            check("the rows count them all", r.rows == 6)
            check("no line reaches either", !r.segments.contains { $0.y1 >= 2 || $0.y2 >= 2 }, "\(r.segments)")
            check("nobody shares a place", noOverlap(r))

            // Kin as well as a friend: the kinship places her, the band does not.
            let both = FamilyTreeLayout.layout(
                people: ["Aino", "Toivo", "Rauha"],
                links: [parent("Aino", "Toivo"), sibling("Toivo", "Rauha")],
                aside: ["Rauha"]
            )
            check("somebody's kin is placed by the kinship, friend or not",
                  both.placements["Rauha"]?.row == 1 && both.aside.isEmpty && both.asideRow == nil,
                  "\(String(describing: both.placements["Rauha"]))")

            // Friends and nobody else apart: one band, one caption row.
            let friendsOnly = FamilyTreeLayout.layout(people: ["Aino", "Toivo", "Jonne"], links: [parent("Aino", "Toivo")], aside: ["Jonne"])
            check("friends alone leave no row for the other caption",
                  friendsOnly.looseRow == nil && friendsOnly.captionRows == [2] && friendsOnly.rows == 4)

            // Both bands full: four friends over three to a row, and somebody
            // related to nobody under them.
            let full = FamilyTreeLayout.layout(people: ["A", "B", "C", "D", "E", "F", "G"], links: [spouse("A", "B")], aside: ["C", "D", "E", "F"])
            check("four friends take two rows and the rest start below them",
                  full.asideRow == 2 && full.placements["F"]?.row == 3 && full.looseRow == 5 && full.placements["G"]?.row == 5,
                  "\(full.placements)")
            check("with both bands full, nobody shares a place", noOverlap(full))

            // No tree at all: two friends of each other sit under an empty
            // top row, and nothing is a generation.
            let pair = FamilyTreeLayout.layout(people: ["Elina", "Jonne"], links: [], aside: ["Elina", "Jonne"])
            check("two friends and no family sit under an empty top row",
                  pair.asideRow == 1 && pair.looseRow == nil && pair.bandStart == 0
                      && pair.placements["Elina"]?.x == 0 && pair.placements["Jonne"]?.x == 1)
        }

        print("— what does not belong is ignored, not drawn —")
        do {
            let r = FamilyTreeLayout.layout(
                people: ["Aino", "Toivo", "Aino"],
                links: [parent("Aino", "Toivo"), parent("Aino", "Toivo"), parent("Aino", "Ghost"), spouse("Aino", "Aino")]
            )
            check("a person listed twice is placed once", r.placements.count == 2)
            check("a link to somebody not in the tree is dropped", r.placements["Ghost"] == nil && !r.unconnected.contains("Ghost"))
            check("the same link twice draws one bracket", r.segments.filter { $0.x1 == $0.x2 && $0.y2 == 1 }.count == 1, "\(r.segments)")
        }

        print("— data that contradicts itself still places everybody —")
        do {
            let r = FamilyTreeLayout.layout(people: ["A", "B"], links: [parent("A", "B"), parent("B", "A")])
            check("both are placed", r.placements.count == 2)
            check("on different rows", r.placements["A"]?.row != r.placements["B"]?.row)
            check("nobody shares a place", noOverlap(r))
        }

        print("— two families that share nobody do not overlap —")
        do {
            let r = FamilyTreeLayout.layout(
                people: ["A", "B", "C", "D"],
                links: [spouse("A", "B"), spouse("C", "D")]
            )
            let first = [r.placements["A"]!.x, r.placements["B"]!.x]
            let second = [r.placements["C"]!.x, r.placements["D"]!.x]
            check("the second family starts after the first ends", second.min()! > first.max()!, "\(first) \(second)")
            check("with an empty place between them", second.min()! - first.max()! >= 2)
            check("the width covers both", r.width >= second.max()! + 1)
        }

        print("— the same family is always the same drawing —")
        do {
            let people = ["Mummo", "Vaari", "Liisa", "Pekka", "Helmi", "Eero"]
            let links = [
                spouse("Mummo", "Vaari"), parent("Mummo", "Liisa"), parent("Vaari", "Liisa"),
                spouse("Liisa", "Pekka"), parent("Liisa", "Helmi"), parent("Pekka", "Helmi"),
                sibling("Liisa", "Eero"),
            ]
            let first = FamilyTreeLayout.layout(people: people, links: links)
            let again = FamilyTreeLayout.layout(people: people, links: links)
            check("identical placements and lines", first == again)
            check("nobody shares a place", noOverlap(first))
            check("Eero is on his sister's row", first.placements["Eero"]?.row == first.placements["Liisa"]?.row)
        }

        print("— a family that shares nobody is a family of its own —")
        do {
            // Two families and one person related to neither. Which family
            // somebody is in is what the drawing needs to know before it
            // shades a row and calls it a generation: the second family's
            // row 0 is its own oldest generation and nobody else's.
            let r = FamilyTreeLayout.layout(
                people: ["Aino", "Toivo", "Eeva", "Kalle", "Sanni"],
                links: [parent("Aino", "Toivo"), spouse("Eeva", "Kalle")]
            )
            check("each family is numbered", r.family["Aino"] == 0 && r.family["Toivo"] == 0 && r.family["Eeva"] == 1)
            check("and there is an extent for each", r.familyExtents.count == 2)
            check("related to nobody is in no family", r.family["Sanni"] == nil)
            let first = r.familyExtents.first, second = r.familyExtents.last
            check("the first family ends before the second begins", (first?.maxX ?? 9) < (second?.minX ?? -9))
            check("each extent covers its own people",
                  first?.minX == r.placements["Aino"]?.x
                      && second?.minX == r.placements["Eeva"]?.x && second?.maxX == r.placements["Kalle"]?.x)
            check("and carries its own depth, not the tallest", first?.rows == 2 && second?.rows == 1,
                  "\(r.familyExtents)")

            // And the screen's question about those extents: the rail's words
            // are counted from your own row, so they are about the drawing
            // only while your own family is under the window. Scrolled on to
            // the other one they would name its generations as yours, which
            // is a relationship nobody entered. Silent when wrong in both
            // directions — a rail that withdraws too early leaves a picture
            // with nothing to explain it, and one that withdraws too late
            // says the wrong thing about somebody.
            let mine = first
            check("the rail's words apply where your family is",
                  FamilyTreeLayout.inView(mine, 0 ... 3))
            check("and still apply when only its last column is left",
                  FamilyTreeLayout.inView(mine, (mine!.maxX + 0.5) ... (mine!.maxX + 4)))
            check("and stop where it ends",
                  !FamilyTreeLayout.inView(mine, (mine!.maxX + 1.5) ... (mine!.maxX + 4)))
            check("the other family is not yours",
                  !FamilyTreeLayout.inView(mine, (second!.minX + 0.1) ... (second!.maxX + 1)))
            check("and a window that has not been measured is nobody's",
                  !FamilyTreeLayout.inView(nil, 0 ... 3))
        }

        print("— the connections a family archive actually contains —")
        do {
            // A second marriage. Both wives are drawn, each as a couple with
            // him, and the half-siblings are both under their father.
            //
            // He stands BETWEEN them, and that is the whole of it: laid out
            // with the two wives side by side, the line to the second one runs
            // straight through the first, and the drop to its children starts
            // from the middle of the couple, which is her place exactly. The
            // picture then says Hilma and Lyyli are a couple and Kerttu hangs
            // from Hilma, and the archive says neither.
            let marriages = [
                spouse("Aapo", "Hilma"), spouse("Aapo", "Lyyli"),
                parent("Aapo", "Vaino"), parent("Hilma", "Vaino"),
                parent("Aapo", "Kerttu"), parent("Lyyli", "Kerttu"),
            ]
            let r = FamilyTreeLayout.layout(
                people: ["Aapo", "Hilma", "Lyyli", "Vaino", "Kerttu"],
                links: marriages
            )
            check("both wives are on his row",
                  r.placements["Hilma"]?.row == 0 && r.placements["Lyyli"]?.row == 0)
            check("both marriages are drawn", r.segments.filter { $0.kind == .couple }.count == 2)
            check("both children are a generation below",
                  r.placements["Vaino"]?.row == 1 && r.placements["Kerttu"]?.row == 1)
            check("nobody shares a place", noOverlap(r))
            check("the man married twice stands between his wives",
                  abs((r.placements["Aapo"]?.x ?? 0) - (r.placements["Hilma"]?.x ?? 9)) == 1
                  && abs((r.placements["Aapo"]?.x ?? 0) - (r.placements["Lyyli"]?.x ?? 9)) == 1,
                  "\(r.placements.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.x)" })")
            check("no line is drawn over anybody it is not about",
                  throughSomebody(r, marriages).isEmpty, "\(throughSomebody(r, marriages))")
            check("and the wives are not drawn as a couple with each other",
                  !r.segments.contains { $0.kind == .couple && abs($0.x2 - $0.x1) > 1 },
                  "\(r.segments.filter { $0.kind == .couple })")

            // Three marriages, which no single row can put side by side: one
            // of the three has a wife standing between the two. The line to
            // her bends under the row rather than through her, and so does
            // the drop to her children — every marriage still drawn, and
            // none of them over anybody else.
            let thrice = [
                spouse("Aapo", "Hilma"), spouse("Aapo", "Lyyli"), spouse("Aapo", "Saima"),
                parent("Aapo", "Kerttu"), parent("Saima", "Kerttu"),
            ]
            let three = FamilyTreeLayout.layout(
                people: ["Aapo", "Hilma", "Lyyli", "Saima", "Kerttu"], links: thrice
            )
            check("all three wives are placed on his row",
                  ["Hilma", "Lyyli", "Saima"].allSatisfy { three.placements[$0]?.row == 0 }
                  && noOverlap(three))
            check("all three marriages are drawn",
                  Set(three.segments.filter { $0.kind == .couple }.map { "\($0.x1)-\($0.x2)@\($0.y1)" }).count >= 3,
                  "\(three.segments.filter { $0.kind == .couple })")
            check("and none of them over anybody else",
                  throughSomebody(three, thrice).isEmpty, "\(throughSomebody(three, thrice))")

            // Cousins married to each other: the family is a ring rather than
            // a tree, and a ring is where a breadth-first generation can come
            // back round to disagree with itself.
            let ringLinks = [
                spouse("A", "B"), parent("A", "C"), parent("B", "C"), parent("A", "D"), parent("B", "D"),
                parent("C", "E"), parent("D", "F"), spouse("E", "F"),
            ]
            let ring = FamilyTreeLayout.layout(people: ["A", "B", "C", "D", "E", "F"], links: ringLinks)
            check("a ring places everybody once", ring.placements.count == 6 && noOverlap(ring))
            check("the cousins are on one row", ring.placements["E"]?.row == ring.placements["F"]?.row)
            check("and their marriage is drawn", ring.segments.contains { $0.kind == .couple && $0.y1 == 2 })
            check("with nobody under either line", throughSomebody(ring, ringLinks).isEmpty,
                  "\(throughSomebody(ring, ringLinks))")

            // A marriage the generations cannot hold: Eemeli is a brother of
            // somebody a generation above his wife. One of the two lines has
            // to go — what must not happen is somebody left out or drawn on
            // top of somebody else.
            let apart = FamilyTreeLayout.layout(
                people: ["Oiva", "Eemeli", "Vaino", "Sirkka"],
                links: [sibling("Oiva", "Eemeli"), parent("Vaino", "Sirkka"), spouse("Eemeli", "Sirkka"), spouse("Oiva", "Vaino")]
            )
            check("everybody is still placed", apart.placements.count == 4 && noOverlap(apart))
            // Which line goes depends on the order the family was entered in
            // — here it is the parent, because breadth first reaches Sirkka
            // through her husband before it reaches her through her father.
            // What matters is that exactly one goes: the other three
            // relationships are still drawn and nobody is misplaced.
            let kept = apart.segments.filter { $0.kind == .couple }.count
                + (apart.segments.contains { $0.kind == .sibling } ? 1 : 0)
                + (apart.segments.contains { $0.kind == .descent } ? 1 : 0)
            check("and exactly one of the four relationships loses its line", kept == 3, "\(apart.segments)")
        }

        print("— a family too big for the screen —")
        do {
            // Four generations, three children to a couple and each of them
            // married: eighty people, which is the size a family archive
            // reaches in a year and a size nothing here had ever been run at
            // until 16 Sep 2026. Every property below holds at five people
            // too; the point is that they still hold at eighty.
            var people = ["a", "b"]
            var links = [spouse("a", "b")]
            var couples = [("a", "b")]
            var next = 0
            for _ in 0 ..< 3 {
                var born: [(String, String)] = []
                for (mother, father) in couples {
                    for _ in 0 ..< 3 {
                        next += 1
                        let child = "c\(next)", inLaw = "i\(next)"
                        people += [child, inLaw]
                        links += [parent(mother, child), parent(father, child), spouse(child, inLaw)]
                        born.append((child, inLaw))
                    }
                }
                couples = born
            }
            let r = FamilyTreeLayout.layout(people: people, links: links)
            check("everybody is placed", r.placements.count == people.count, "\(r.placements.count) of \(people.count)")
            check("nobody shares a place", noOverlap(r))
            check("four generations", r.rows == 4)
            check("wide enough for the youngest generation", r.width >= 54, "\(r.width)")
            let childBelow = links.filter { $0.kind == .parent }.allSatisfy {
                (r.placements[$0.to]?.row ?? -9) == (r.placements[$0.from]?.row ?? 9) + 1
            }
            check("every child is one row under both parents", childBelow)
            let coupleSideBySide = links.filter { $0.kind == .spouse }.allSatisfy {
                guard let a = r.placements[$0.from], let b = r.placements[$0.to] else { return false }
                return a.row == b.row && abs(a.x - b.x) == 1
            }
            check("every couple is side by side", coupleSideBySide)
            check("and no line crosses anybody, eighty deep", throughSomebody(r, links).isEmpty,
                  "\(throughSomebody(r, links).prefix(5))")
            check("one family", r.familyExtents.count == 1 && r.looseRow == nil)
            check("and nothing anywhere that cannot be drawn", r.undrawn.isEmpty, "\(r.undrawn)")
            check("and the same drawing twice", FamilyTreeLayout.layout(people: people, links: links) == r)
        }

        /// What, in a child's column, belongs to some other brood — the one
        /// way the bars can state a parent the archive does not hold. A bar
        /// of somebody else's at the child's own height is the child hung on
        /// it: fused with its own or hung from its end. A bar of somebody
        /// else's through the child's line — below where the line starts,
        /// which is the child's own bar or its own parent's card straight
        /// above — is a crossing that reads as a join. A vertical of somebody
        /// else's is a stranger's drop or anchor standing over the child.
        /// The child's own parent standing straight above it is not a
        /// stranger, and nor is the anchor of its own parents' marriage; a
        /// bar that passes over the column above where the child's line
        /// starts touches nothing of the child's and is not counted.
        func strangers(_ r: FamilyTreeLayout.Result, _ links: [L], depth: (String) -> Double) -> [String] {
            var folks: [String: Set<String>] = [:]
            for link in links where link.kind == .parent {
                guard let up = r.placements[link.from], let down = r.placements[link.to], down.row == up.row + 1 else { continue }
                folks[link.to, default: []].insert(link.from)
            }
            var wed = Set<String>()
            for link in links where link.kind == .spouse { wed.insert([link.from, link.to].sorted().joined(separator: "|")) }
            var found: [String] = []
            for (child, p) in r.placements {
                guard let mine = folks[child] else { continue }
                let x = p.x, below = Double(p.row), above = below - 1
                guard let own = r.segments.first(where: {
                    $0.kind == .descent && $0.x1 == x && $0.x2 == x && $0.y2 == below && $0.y1 > above
                }) else { continue }
                let siblings = folks.filter { $0.value == mine }.keys.compactMap { r.placements[$0]?.x }
                let parentsX = mine.sorted().compactMap { r.placements[$0]?.x }
                let married = mine.count == 2 && wed.contains(mine.sorted().joined(separator: "|"))
                let anchor = parentsX.reduce(0, +) / Double(parentsX.count)
                let reach = married ? [anchor] : parentsX
                let low = (siblings + reach).min()!, high = (siblings + reach).max()!
                let cards = mine.compactMap { r.placements[$0]?.x == x ? above + depth($0) : nil }
                let top = min(own.y1, cards.min() ?? own.y1)
                for s in r.segments where s.kind == .descent && s.y1 >= above && s.y1 <= below && s.y2 > above && s.y2 <= below {
                    if s.y1 == s.y2 {
                        guard s.x1 <= x, x <= s.x2 else { continue }
                        if s.y1 == own.y1 {
                            if !(s.x1 == low && s.x2 == high) { found.append("\(child) hung on somebody else's bar") }
                        } else if top < s.y1, s.y1 < below {
                            found.append("a bar of somebody else's through \(child)'s line at \(((s.y1 - above) * 1000).rounded() / 1000)")
                        }
                    } else if s.x1 == x && s.x2 == x && s != own {
                        if cards.contains(s.y1) { continue }
                        if married && anchor == x && s.y1 <= above + 0.4 { continue }
                        found.append("a line of somebody else's down \(child)'s column from \(((s.y1 - above) * 1000).rounded() / 1000)")
                    }
                }
            }
            return found.sorted()
        }

        print("— a line leaves a person from under their name —")
        do {
            // The layout draws in rows and knows nothing about text, so the
            // screen tells it how deep a card reaches below the row's centre
            // line: half a disc, a gap, a name and a little air, about two
            // fifths of a row — and the word *Sinä* more on the phone's own
            // card. Every line that leaves somebody downwards starts there.
            // Until 19 Sep 2026 it started at the centre of the disc and ran
            // down through the name whenever the drop was from one person
            // rather than from between two.
            //
            // The two numbers are what the screen passes at the default text
            // size, 59.4 and 75 points of a 156-point row; the letters of a
            // name were measured ending 52.7 points below the disc's centre
            // and those of *Sinä* 74.7.
            let card = 0.381, yours = 0.481

            /// Every line that crosses the band under somebody's disc — the
            /// gap and the name — at their own column, by name.
            func throughAName(_ r: FamilyTreeLayout.Result, depth: (String) -> Double) -> [String] {
                var wrong: [String] = []
                for (id, p) in r.placements.sorted(by: { $0.key < $1.key }) {
                    let centre = Double(p.row), foot = centre + depth(id)
                    for line in r.segments {
                        let x1 = min(line.x1, line.x2), x2 = max(line.x1, line.x2)
                        let y1 = min(line.y1, line.y2), y2 = max(line.y1, line.y2)
                        guard x1 <= p.x, p.x <= x2 else { continue }
                        if line.y1 == line.y2 {
                            if centre < y1 && y1 < foot { wrong.append("a line runs across \(id) at \(y1)") }
                        } else if y1 < foot && y2 > centre {
                            wrong.append("a line runs down through \(id) from \(y1)")
                        }
                    }
                }
                return wrong
            }

            // The first family somebody entered on a phone, as entered: a
            // child from each parent, three pairs of siblings, and not one
            // marriage — which rule 4 will not infer from two people having
            // a child. Jaakko's phone.
            let phone = [
                parent("Anna", "Jaakko"), parent("Antti", "Jaakko"), parent("Anna", "Erkko"),
                parent("Paula", "Anna"), parent("Jorma", "Anna"), parent("Paula", "Juhani"),
                parent("Suoma", "Antti"), parent("Pertti", "Antti"),
                parent("Suoma", "Annukka"), parent("Pertti", "Annukka"),
                sibling("Jaakko", "Erkko"), sibling("Anna", "Juhani"), sibling("Antti", "Annukka"),
            ]
            let people = ["Jaakko", "Erkko", "Anna", "Antti", "Juhani", "Annukka", "Paula", "Jorma", "Suoma", "Pertti"]
            let onPhone: (String) -> Double = { $0 == "Jaakko" ? yours : card }
            let r = FamilyTreeLayout.layout(people: people, links: phone, depth: onPhone)
            let p = r.placements
            check("everybody is placed, once", p.count == people.count && noOverlap(r), "\(p.count)")
            check("three generations", r.rows == 3 && p["Anna"]?.row == 1 && p["Jaakko"]?.row == 2)
            check("and nobody left of the picture's edge", p.values.allSatisfy { $0.x >= 0 }, "\(p)")
            /// The height the bar a child hangs from, from the child's own drop.
            func hang(_ id: String, in r: FamilyTreeLayout.Result) -> Double? {
                guard let place = r.placements[id] else { return nil }
                return r.segments.first {
                    $0.kind == .descent && $0.x1 == place.x && $0.x2 == place.x
                        && $0.y2 == Double(place.row) && $0.y1 > Double(place.row) - 1
                }?.y1
            }
            /// A drop from under somebody's name to a height.
            func drop(from id: String, to y: Double?, in r: FamilyTreeLayout.Result) -> Bool {
                guard let place = r.placements[id], let y else { return false }
                return r.segments.contains {
                    $0.kind == .descent && $0.x1 == place.x && $0.x2 == place.x
                        && $0.y1 == Double(place.row) + card && $0.y2 == y
                }
            }
            let jaakko = hang("Jaakko", in: r), erkko = hang("Erkko", in: r)
            check("Jaakko hangs from under Anna's name", drop(from: "Anna", to: jaakko, in: r),
                  "\(r.segments.filter { $0.kind == .descent && $0.y1 > 1 && $0.y1 < 2 })")
            check("and from under Antti's", drop(from: "Antti", to: jaakko, in: r))
            let between = ((p["Anna"]?.x ?? 0) + (p["Antti"]?.x ?? 0)) / 2
            check("and not from the empty space between two people the picture has not joined",
                  !r.segments.contains { $0.kind == .descent && $0.x1 == between && $0.x2 == between && $0.y1 < (jaakko ?? 0) })
            let bar = r.segments.first {
                $0.kind == .descent && $0.y1 == jaakko && $0.y2 == jaakko
                    && $0.x1 <= min(p["Anna"]!.x, p["Antti"]!.x) && $0.x2 >= max(p["Anna"]!.x, p["Antti"]!.x)
            }
            check("one bar reaches from the first parent to the last", bar != nil && bar!.x1 <= p["Jaakko"]!.x && bar!.x2 >= p["Jaakko"]!.x,
                  "\(r.segments.filter { $0.kind == .descent && $0.y1 == $0.y2 })")
            check("and Jaakko hangs from between his parents, not under either",
                  p["Jaakko"]!.x > min(p["Anna"]!.x, p["Antti"]!.x) && p["Jaakko"]!.x < max(p["Anna"]!.x, p["Antti"]!.x))
            // Erkko is Anna's alone. Until 21 Sep 2026 he stood straight under
            // her and hung from the end of the bar to Antti, the T that reads
            // as Antti's son. Now he stands beside her, on the far side from
            // Antti, and his bar leaves her line at a height of its own that
            // no line of Antti's reaches.
            check("Erkko stands beside Anna, on the far side from Antti",
                  (p["Erkko"]!.x - p["Anna"]!.x) * (p["Antti"]!.x - p["Anna"]!.x) < 0 && abs(p["Erkko"]!.x - p["Anna"]!.x) <= 1,
                  "Erkko \(p["Erkko"]!.x) Anna \(p["Anna"]!.x) Antti \(p["Antti"]!.x)")
            check("and hangs from a bar at a height of its own", erkko != nil && erkko != jaakko, "\(String(describing: erkko)) \(String(describing: jaakko))")
            check("which Anna's line reaches", drop(from: "Anna", to: erkko, in: r))
            check("and no line of Antti's does",
                  !r.segments.contains { $0.kind == .descent && $0.x1 == p["Antti"]!.x && $0.x2 == p["Antti"]!.x && $0.y2 == erkko }
                  && !r.segments.contains { $0.kind == .descent && $0.y1 == erkko && $0.y2 == erkko && $0.x1 <= p["Antti"]!.x && p["Antti"]!.x <= $0.x2 })
            check("Juhani stands beside Paula, on the far side from Jorma",
                  (p["Juhani"]!.x - p["Paula"]!.x) * (p["Jorma"]!.x - p["Paula"]!.x) < 0)
            check("and hangs from under Paula's name", drop(from: "Paula", to: hang("Juhani", in: r), in: r))
            check("Anna hangs from between Paula and Jorma", p["Anna"]!.x == (p["Paula"]!.x + p["Jorma"]!.x) / 2, "\(p["Anna"]!)")
            check("no marriage is drawn where none was entered", !r.segments.contains { $0.kind == .couple })
            check("no line runs through anybody's name", throughAName(r, depth: onPhone).isEmpty, "\(throughAName(r, depth: onPhone))")
            check("and nothing of another brood in any child's column", strangers(r, phone, depth: onPhone).isEmpty, "\(strangers(r, phone, depth: onPhone))")

            // The same family with the marriages entered: back to one drop
            // from between each couple, from the line that joins them.
            let married = phone + [spouse("Anna", "Antti"), spouse("Paula", "Jorma"), spouse("Suoma", "Pertti")]
            let m = FamilyTreeLayout.layout(people: people, links: married, depth: onPhone)
            let wedBetween = ((m.placements["Anna"]?.x ?? 0) + (m.placements["Antti"]?.x ?? 0)) / 2
            check("married, Jaakko hangs from between his parents",
                  m.segments.contains { $0.kind == .descent && $0.x1 == wedBetween && $0.x2 == wedBetween && $0.y1 == 1.0 && $0.y2 == hang("Jaakko", in: m) },
                  "\(m.segments.filter { $0.kind == .descent && $0.y1 > 1 && $0.y1 < 2 })")
            check("Erkko still from under Anna's name", drop(from: "Anna", to: hang("Erkko", in: m), in: m))
            check("and still nothing through a name", throughAName(m, depth: onPhone).isEmpty, "\(throughAName(m, depth: onPhone))")
            check("and nothing of another brood in any child's column", strangers(m, married, depth: onPhone).isEmpty, "\(strangers(m, married, depth: onPhone))")

            // A line that leaves the phone's own card starts under *Sinä*,
            // which is deeper than a name.
            let own = FamilyTreeLayout.layout(people: ["Jaakko", "Lapsi"], links: [parent("Jaakko", "Lapsi")]) { $0 == "Jaakko" ? yours : card }
            check("a drop from you starts under Sinä",
                  own.segments.contains { $0.kind == .descent && $0.x1 == $0.x2 && $0.y1 == yours && $0.y2 == 0.5 },
                  "\(own.segments)")

            // A marriage is bent under the row only round somebody. It used
            // to be bent by distance, `right - left > 1`, and a row whose
            // places are means of thirds puts a couple one place and 2⁻⁵²
            // apart: found by trying 30 000 random families through the old
            // drawing, which bent 17 of them round nobody. Bertta and Daniel
            // are one unit and want the mean of three parents — her two, his
            // one — and the family holds no child placed beside a parent,
            // which would move everybody by a fraction and put the pair
            // exactly one apart, as it did to the fixture this replaced on
            // 21 Sep 2026.
            let thirds = [
                parent("Aada", "Bertta"), parent("Cecilia", "Bertta"), parent("Fanni", "Daniel"),
                spouse("Bertta", "Daniel"), spouse("Aada", "Eero"),
            ]
            let t = FamilyTreeLayout.layout(
                people: ["Aada", "Bertta", "Cecilia", "Daniel", "Eero", "Fanni"], links: thirds
            )
            // The dip a marriage makes round somebody runs under the names
            // it goes round — and the one card it cannot keep out of is the
            // phone's own, with *Sinä* under the name, which the check lets
            // through by name.
            let thrice = [
                spouse("Aapo", "Hilma"), spouse("Aapo", "Lyyli"), spouse("Aapo", "Saima"),
                parent("Aapo", "Kerttu"), parent("Saima", "Kerttu"),
            ]
            let three = FamilyTreeLayout.layout(people: ["Aapo", "Hilma", "Lyyli", "Saima", "Kerttu"], links: thrice) { _ in card }
            let dips = three.segments.filter { $0.kind == .couple && $0.y1 == $0.y2 && $0.y1 > 0 }
            check("a marriage goes round somebody under the names", dips.count == 1 && dips.allSatisfy { $0.y1 > card && $0.y1 < 0.5 }, "\(dips)")
            check("and its legs start under the names", three.segments.filter { $0.kind == .couple && $0.x1 == $0.x2 }.allSatisfy { $0.y1 == card },
                  "\(three.segments.filter { $0.kind == .couple && $0.x1 == $0.x2 })")
            check("and nothing runs through a name", throughAName(three) { _ in card }.isEmpty, "\(throughAName(three) { _ in card })")
            let threeOwn = FamilyTreeLayout.layout(people: ["Aapo", "Hilma", "Lyyli", "Saima", "Kerttu"], links: thrice) { $0 == "Aapo" ? yours : card }
            let leaks = throughAName(threeOwn) { $0 == "Aapo" ? yours : card }
            check("the one line it lets through is that dip under Sinä",
                  leaks == ["a line runs across Aapo at 0.4"]
                  && !threeOwn.segments.contains { $0.kind == .couple && $0.x1 == $0.x2 && $0.x1 == threeOwn.placements["Aapo"]!.x },
                  "\(leaks)")

            // And the families above, at the default depth.
            let grandparents = FamilyTreeLayout.layout(
                people: ["Mummo", "Vaari", "Liisa", "Matti", "Sanni"],
                links: [spouse("Mummo", "Vaari"), parent("Mummo", "Liisa"), parent("Vaari", "Liisa"),
                        parent("Mummo", "Matti"), parent("Vaari", "Matti"), parent("Mummo", "Sanni"), parent("Vaari", "Sanni")]
            ) { _ in card }
            check("Mummo and Vaari: nothing through a name", throughAName(grandparents) { _ in card }.isEmpty,
                  "\(throughAName(grandparents) { _ in card })")
            // The same depth is passed and measured: a layout drawn at the
            // default depth and walked at the screen's would flag the drops
            // from C and D by a thousandth of a row.
            let ring = FamilyTreeLayout.layout(people: ["A", "B", "C", "D", "E", "F"], links: [
                spouse("A", "B"), parent("A", "C"), parent("B", "C"), parent("A", "D"), parent("B", "D"),
                parent("C", "E"), parent("D", "F"), spouse("E", "F"),
            ]) { _ in card }
            check("a ring: nothing through a name", throughAName(ring) { _ in card }.isEmpty, "\(throughAName(ring) { _ in card })")
        }

        print("— half-siblings: a child of one parent is not hung on the other's brood —")
        do {
            let card = 0.381
            let flat: (String) -> Double = { _ in card }
            /// The height a child hangs from, from its own drop.
            func hang(_ id: String, in r: FamilyTreeLayout.Result) -> Double? {
                guard let place = r.placements[id] else { return nil }
                return r.segments.first {
                    $0.kind == .descent && $0.x1 == place.x && $0.x2 == place.x
                        && $0.y2 == Double(place.row) && $0.y1 > Double(place.row) - 1
                }?.y1
            }
            /// Bars on one row, at one height, that touch or overlap.
            func fused(_ r: FamilyTreeLayout.Result) -> [(FamilyTreeLayout.Segment, FamilyTreeLayout.Segment)] {
                let bars = r.segments.filter { $0.kind == .descent && $0.y1 == $0.y2 }
                var pairs: [(FamilyTreeLayout.Segment, FamilyTreeLayout.Segment)] = []
                for i in bars.indices { for j in bars.indices where j > i {
                    let a = bars[i], b = bars[j]
                    if a.y1 == b.y1 && a.x1 <= b.x2 && b.x1 <= a.x2 { pairs.append((a, b)) }
                } }
                return pairs
            }

            // The smallest family with the defect: no grandparents to make
            // room, so Erkko can only go beside Anna by the family moving
            // over one place.
            let small = [parent("Anna", "Jaakko"), parent("Antti", "Jaakko"), parent("Anna", "Erkko")]
            let s = FamilyTreeLayout.layout(people: ["Anna", "Antti", "Jaakko", "Erkko"], links: small, depth: flat)
            let sp = s.placements
            check("Erkko beside Anna, away from Antti, with the family moved over for him",
                  sp["Erkko"]!.x == 0 && sp["Anna"]!.x == 1 && sp["Antti"]!.x == 2, "\(sp)")
            check("Jaakko between his parents", sp["Jaakko"]!.x == 1.5, "\(sp["Jaakko"]!)")
            check("at two heights, the child of one parent the shallower", hang("Erkko", in: s) == 0.5 && hang("Jaakko", in: s) == 0.7,
                  "\(String(describing: hang("Erkko", in: s))) \(String(describing: hang("Jaakko", in: s)))")
            check("and nothing of another brood in any child's column", strangers(s, small, depth: flat).isEmpty, "\(strangers(s, small, depth: flat))")

            // A couple with three children beside her child from before,
            // which used to be one bar with four children on it.
            let wide = [
                spouse("Antti", "Anna"), parent("Anna", "Jaakko"), parent("Antti", "Jaakko"),
                parent("Anna", "Jussi"), parent("Antti", "Jussi"), parent("Anna", "Jenni"), parent("Antti", "Jenni"),
                parent("Anna", "Erkko"),
            ]
            let w = FamilyTreeLayout.layout(people: ["Antti", "Anna", "Jaakko", "Jussi", "Jenni", "Erkko"], links: wide, depth: flat)
            let couple = w.segments.first { $0.kind == .descent && $0.y1 == $0.y2 && $0.y1 == hang("Jaakko", in: w) }
            check("the couple's three hang from one bar, centred under the couple",
                  couple != nil && [ "Jaakko", "Jussi", "Jenni" ].allSatisfy { hang($0, in: w) == couple!.y1 }
                  && (couple!.x1 + couple!.x2) / 2 == (w.placements["Anna"]!.x + w.placements["Antti"]!.x) / 2,
                  "\(String(describing: couple)) \(w.placements)")
            check("Erkko beyond it, from a bar of his own at another height",
                  w.placements["Erkko"]!.x > couple!.x2 && hang("Erkko", in: w) != couple!.y1, "\(w.placements["Erkko"]!) \(String(describing: hang("Erkko", in: w)))")
            check("and nothing of another brood in any child's column", strangers(w, wide, depth: flat).isEmpty, "\(strangers(w, wide, depth: flat))")

            // Children by two people, neither married to her: her line
            // reaches both bars, each of theirs one.
            let two = [parent("Anna", "Jaakko"), parent("Antti", "Jaakko"), parent("Anna", "Erkko"), parent("Pekka", "Erkko")]
            let d = FamilyTreeLayout.layout(people: ["Antti", "Anna", "Pekka", "Jaakko", "Erkko"], links: two, depth: flat)
            func reaches(_ id: String, _ y: Double?, in r: FamilyTreeLayout.Result) -> Bool {
                guard let place = r.placements[id], let y else { return false }
                return r.segments.contains { $0.kind == .descent && $0.x1 == place.x && $0.x2 == place.x && $0.y2 == y }
            }
            check("two bars at two heights", hang("Jaakko", in: d) != nil && hang("Erkko", in: d) != nil && hang("Jaakko", in: d) != hang("Erkko", in: d))
            check("Anna's line reaches both", reaches("Anna", hang("Jaakko", in: d), in: d) && reaches("Anna", hang("Erkko", in: d), in: d))
            check("Antti's one and Pekka's the other",
                  reaches("Antti", hang("Jaakko", in: d), in: d) && !reaches("Antti", hang("Erkko", in: d), in: d)
                  && reaches("Pekka", hang("Erkko", in: d), in: d) && !reaches("Pekka", hang("Jaakko", in: d), in: d))
            check("and nothing of another brood in any child's column", strangers(d, two, depth: flat).isEmpty, "\(strangers(d, two, depth: flat))")

            // A second marriage: two children of each. The children of each
            // used to go down one at a time from their parents' place, so
            // the first marriage's second child stood where the second
            // marriage's children start and the bars met. As a block
            // centred under each couple, the first marriage's two sit under
            // it; the second marriage's two start where those end, one
            // place short of centred, because the parents' row was placed
            // before it knew how wide the row below would be. The bars
            // keep half a place between them and both keep the half-row
            // height.
            let twice = [
                spouse("Aapo", "Hilma"), spouse("Aapo", "Lyyli"),
                parent("Aapo", "Kaisa"), parent("Hilma", "Kaisa"), parent("Aapo", "Kalle"), parent("Hilma", "Kalle"),
                parent("Aapo", "Liisa"), parent("Lyyli", "Liisa"), parent("Aapo", "Lauri"), parent("Lyyli", "Lauri"),
            ]
            let re = FamilyTreeLayout.layout(people: ["Aapo", "Hilma", "Lyyli", "Kaisa", "Kalle", "Liisa", "Lauri"], links: twice, depth: flat)
            let rp = re.placements
            check("the first marriage's children are centred under it",
                  (rp["Kaisa"]!.x + rp["Kalle"]!.x) / 2 == (rp["Aapo"]!.x + rp["Hilma"]!.x) / 2, "\(rp)")
            check("and the second's start where they end",
                  min(rp["Liisa"]!.x, rp["Lauri"]!.x) == max(rp["Kaisa"]!.x, rp["Kalle"]!.x) + 1, "\(rp)")
            let second = re.segments.first { $0.kind == .descent && $0.y1 == $0.y2 && $0.x2 == max(rp["Liisa"]!.x, rp["Lauri"]!.x) }
            check("from a bar that reaches from their parents' anchor to the last of them",
                  second != nil && second!.x1 == (rp["Aapo"]!.x + rp["Lyyli"]!.x) / 2 && hang("Liisa", in: re) == second!.y1 && hang("Lauri", in: re) == second!.y1,
                  "\(String(describing: second))")
            check("both bars at half a row, and apart", ["Kaisa", "Kalle", "Liisa", "Lauri"].allSatisfy { hang($0, in: re) == 0.5 } && fused(re).isEmpty,
                  "\(re.segments.filter { $0.y1 == $0.y2 })")
            check("and nothing of another brood in any child's column", strangers(re, twice, depth: flat).isEmpty, "\(strangers(re, twice, depth: flat))")

            // Three of the first marriage and two of the second is what a
            // row placed from the top down cannot make room for: the third
            // child stands under the second marriage's anchor. The bars are
            // at two heights, so nobody is hung on the wrong one, and what is
            // left is pinned here by name — the next thing a wider row would
            // mend, and not something a change should alter unnoticed.
            let thrice = twice + [parent("Aapo", "Kerttu"), parent("Hilma", "Kerttu")]
            let re3 = FamilyTreeLayout.layout(people: ["Aapo", "Hilma", "Lyyli", "Kaisa", "Kalle", "Kerttu", "Liisa", "Lauri"], links: thrice, depth: flat)
            check("three and two: the two bars are at two heights", fused(re3).isEmpty && hang("Kerttu", in: re3) != hang("Liisa", in: re3),
                  "\(re3.segments.filter { $0.y1 == $0.y2 })")
            check("and what remains is the second anchor down Kerttu's column",
                  strangers(re3, thrice, depth: flat) == [
                      "a bar of somebody else's through Kerttu's line at 0.7",
                      "a line of somebody else's down Kerttu's column from 0.0",
                  ], "\(strangers(re3, thrice, depth: flat))")

            // And at large: the same random families every run, through a
            // generator seeded by hand. What the three heights promise is
            // that two bars sharing a height never touch unless one of them
            // already had every height taken over it — a row no family has
            // had yet. The rest is counted and printed, not promised: a row
            // placed from the top down has no room to widen for the row
            // below it, and a child under a stranger's anchor, or a line
            // through a stranger's bar, is what that costs.
            struct Dice {
                var state: UInt64
                mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
                mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
                mutating func chance(_ p: Double) -> Bool { Double(next() % 10000) / 10000 < p }
            }
            var dice = Dice(state: 20260921)
            var children = 0, hungWrong = 0, crossed = 0, overshadowed = 0, unseparated = 0
            for _ in 0 ..< 5000 {
                let n = 4 + dice.below(9)
                let people = (0 ..< n).map { "P\($0)" }
                let gens = 2 + dice.below(3)
                var gen: [String: Int] = [:]
                for person in people { gen[person] = dice.below(gens) }
                var links: [L] = []
                for person in people where gen[person]! > 0 {
                    let above = people.filter { gen[$0] == gen[person]! - 1 }
                    guard !above.isEmpty else { continue }
                    let howMany = dice.chance(0.3) ? 0 : (dice.chance(0.6) ? 2 : 1)
                    var chosen = Set<String>()
                    for _ in 0 ..< howMany { chosen.insert(above[dice.below(above.count)]) }
                    for q in chosen.sorted() { links.append(parent(q, person)) }
                }
                for person in people where dice.chance(0.35) {
                    let same = people.filter { gen[$0] == gen[person] && $0 != person }
                    if let q = same.isEmpty ? nil : same[dice.below(same.count)] {
                        links.append(dice.chance(0.7) ? spouse(person, q) : sibling(person, q))
                    }
                }
                let r = FamilyTreeLayout.layout(people: people, links: links, depth: flat)
                // Every brood as the layout groups them, from the links rather
                // than the drawing: the one child straight under its one
                // parent draws no bar and still takes a height.
                var folks: [String: Set<String>] = [:]
                for link in links where link.kind == .parent {
                    guard let up = r.placements[link.from], let down = r.placements[link.to], down.row == up.row + 1 else { continue }
                    folks[link.to, default: []].insert(link.from)
                }
                var wedded = Set<String>()
                for link in links where link.kind == .spouse { wedded.insert([link.from, link.to].sorted().joined(separator: "|")) }
                var broods: [(row: Int, low: Double, high: Double, height: Double)] = []
                for mine in Set(folks.values) {
                    let kids = folks.filter { $0.value == mine }.keys.sorted()
                    guard let first = kids.first, let place = r.placements[first], let height = hang(first, in: r) else { continue }
                    let parentsX = mine.sorted().compactMap { r.placements[$0]?.x }
                    let reach = mine.count == 2 && wedded.contains(mine.sorted().joined(separator: "|"))
                        ? [parentsX.reduce(0, +) / Double(parentsX.count)] : parentsX
                    let xs = kids.compactMap { r.placements[$0]?.x } + reach
                    // 2.6 − 2 is not 0.6 in a Double; the tenth is.
                    broods.append((place.row - 1, xs.min()!, xs.max()!, ((height - Double(place.row - 1)) * 10).rounded() / 10))
                }
                func over(_ i: Int, _ j: Int) -> Bool {
                    broods[i].row == broods[j].row && broods[i].low <= broods[j].high && broods[j].low <= broods[i].high
                }
                for i in broods.indices { for j in broods.indices where j > i && over(i, j) && broods[i].height == broods[j].height {
                    // The fallback is the last of the three heights, and only
                    // for a bar that found the other two taken over it.
                    let excused = broods[i].height == 0.6 && [i, j].contains { k in
                        let heights = Set(broods.indices.filter { $0 != k && over($0, k) }.map { broods[$0].height })
                        return heights.contains(0.5) && heights.contains(0.7)
                    }
                    if !excused { unseparated += 1 }
                } }
                for line in strangers(r, links, depth: flat) {
                    if line.hasSuffix("bar") { hungWrong += 1 }
                    else if line.hasPrefix("a bar") { crossed += 1 }
                    else { overshadowed += 1 }
                }
                children += r.placements.filter { child, p in
                    links.contains { $0.kind == .parent && $0.to == child && r.placements[$0.from]?.row == p.row - 1 }
                }.count
            }
            check("in 5 000 random families, two bars share a height and touch only where one had every height taken over it", unseparated == 0, "\(unseparated)")
            print("       \(children) children with a parent on the row above; hung on somebody else's bar \(hungWrong), a stranger's bar through the line \(crossed), a stranger's line down the column \(overshadowed)")
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
