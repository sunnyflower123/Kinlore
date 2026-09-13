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

        print("— people nobody is related to are not drawn in the tree —")
        do {
            let r = FamilyTreeLayout.layout(people: ["Aino", "Toivo", "Kaarina"], links: [parent("Aino", "Toivo")])
            check("Kaarina is listed apart", r.unconnected == ["Kaarina"])
            check("and not placed", r.placements["Kaarina"] == nil)
            let alone = FamilyTreeLayout.layout(people: ["Aino"], links: [])
            check("a tree of nobody related is empty", alone.placements.isEmpty && alone.rows == 0 && alone.unconnected == ["Aino"])
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

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
