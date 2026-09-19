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
            check("and the same drawing twice", FamilyTreeLayout.layout(people: people, links: links) == r)
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
