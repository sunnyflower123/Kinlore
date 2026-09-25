// Checks the word the family tree puts on every card, said from the phone
// owner's point of view — parent, cousin, spouse's parent (Kinship.swift).
//
// Every way of being wrong is silent. A word that settles for the nearest row
// calls a great-great-grandparent a great-grandparent; a path that runs on
// through a friend makes a friend's mother somebody's relative; a priority
// that reads the order of the ties says one word on this phone and another
// after the next sync. Each of them still puts a tidy word on a tidy card,
// and rule 4 says a wrong relationship is worse than a missing one — for a
// word as much as for a line. None of it fails a build, and a screenshot
// shows a word either way.
//
// The named cases are the app's `-seed clan`, each worked out by hand from
// the fixture, first from Elina's phone and then from a few others; then the
// rules the clan does not reach. Then random families: every word from every
// phone compared with a brute-force reading of every shortest path, each pair
// joined by a single shortest reading held to its mirror image, and the
// answer held to the same however untidily the family is handed in. Run it
// after touching Kinship.swift.
//
//   swiftc -parse-as-library -o /tmp/kinship-check \
//     scripts/kinship-check.swift ios/Kinlore/Services/Kinship.swift

import Foundation

@main
enum KinshipCheck {
    typealias Tie = Kinship.Tie
    typealias Word = Kinship.Word

    static let families = 600
    static let soups = 1_000

    static func main() {
        let clock = ContinuousClock()
        let started = clock.now
        var failures = 0

        func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if ok {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): \(detail())")
            }
        }

        /// Every one of `names` has `word` in `words` (nil: no word at all).
        func expect(_ label: String, _ words: [String: Word], _ names: [String], _ word: Word?) {
            let wrong = names.filter { words[$0] != word }
            check(label, wrong.isEmpty, wrong.map { "\($0) has \(spell(words[$0]))" }.joined(separator: ", "))
        }

        let clan = clanFixture()
        let elina = Kinship.words(from: "Elina", people: clan.people, ties: clan.ties)

        print("— the clan, from Elina's phone —")
        let fromElina: [(label: String, names: [String], word: Word?)] = [
            ("Matti and Ritva are parents — Ritva also as the parent's spouse, and the shorter reading wins",
             ["Matti", "Ritva"], .parent),
            ("Toivo, Anneli, Aune and Paavo are grandparents", ["Toivo", "Anneli", "Aune", "Paavo"], .grandparent),
            ("Väinö, Hilja, Kerttu and Oiva are great-grandparents",
             ["Väinö", "Hilja", "Kerttu", "Oiva"], .greatGrandparent),
            ("Aapo, Hilma and Lyyli are four steps up: no word, not great-grandparents",
             ["Aapo", "Hilma", "Lyyli"], nil),
            ("Mikko is the spouse", ["Mikko"], .spouse),
            ("Jukka is the sibling", ["Jukka"], .sibling),
            ("Venla, Oskari and Aino are children — the spouse's too, and the shorter reading wins",
             ["Venla", "Oskari", "Aino"], .child),
            ("Elias is a sibling's child", ["Elias"], .siblingsChild),
            ("Petra is a sibling's spouse", ["Petra"], .siblingsSpouse),
            ("Liisa is a parent's sibling", ["Liisa"], .parentsSibling),
            ("Martta, Eino, Reino and Sirkka are grandparents' siblings, and Helvi too, through Paavo",
             ["Martta", "Eino", "Reino", "Sirkka", "Helvi"], .grandparentsSibling),
            ("Veikko and Kaarina are parents' cousins", ["Veikko", "Kaarina"], .parentsCousin),
            ("Sanni and Aleksi are second cousins", ["Sanni", "Aleksi"], .secondCousin),
            ("Impi and Sulo are three up then a sibling, Urho and Onni one step further: no word",
             ["Impi", "Sulo", "Urho", "Onni"], nil),
            ("Eemeli is four steps away along two readings, neither of them a row: no word", ["Eemeli"], nil),
            ("Tuula and Heikki are a parent's cousin's spouses, five steps and no row: no word",
             ["Tuula", "Heikki"], nil),
            ("Noora and Iiris are six steps away, past the search: no word", ["Noora", "Iiris"], nil),
            ("Jonne is a friend", ["Jonne"], .friend),
            ("Rauha is Helmi's friend and not Elina's: no word", ["Rauha"], nil),
            ("Sisko, Mauri, Tarja, Onerva, Otto and Helmi share nobody with Elina: no word",
             ["Sisko", "Mauri", "Tarja", "Onerva", "Otto", "Helmi"], nil),
            ("the seven loose people: no word", loose, nil),
        ]
        for row in fromElina { expect(row.label, elina, row.names, row.word) }
        var expected: [String: Word] = [:]
        for row in fromElina { for name in row.names { expected[name] = row.word } }
        let named = Set(fromElina.flatMap(\.names))
        let unlisted = clan.people.filter { $0 != "Elina" && !named.contains($0) }
        check("every card in the clan is named above, Elina's own excepted", unlisted.isEmpty, "\(unlisted)")
        check("and nobody else has a word — Elina least of all", elina == expected, difference(elina, expected))

        print("— the clan, from other phones —")
        let kerttu = Kinship.words(from: "Kerttu", people: clan.people, ties: clan.ties)
        expect("Kerttu: Väinö, Impi and Sulo are siblings through Aapo alone — half-siblings count",
               kerttu, ["Väinö", "Impi", "Sulo"], .sibling)
        expect("Kerttu: Hilma is her father's wife, not her mother — a parent's spouse", kerttu, ["Hilma"], .parentsSpouse)
        expect("Kerttu: Helvi and Paavo are children", kerttu, ["Helvi", "Paavo"], .child)
        expect("Kerttu: Ritva and Kaarina are grandchildren", kerttu, ["Ritva", "Kaarina"], .grandchild)
        expect("Kerttu: Elina, Jukka and Aleksi are great-grandchildren",
               kerttu, ["Elina", "Jukka", "Aleksi"], .greatGrandchild)
        expect("Kerttu: Matti, Liisa and Veikko are a sibling's grandchildren",
               kerttu, ["Matti", "Liisa", "Veikko"], .siblingsGrandchild)
        expect("Kerttu: Eino and Aune are a sibling's children and her children's spouses — the table puts the first first",
               kerttu, ["Eino", "Aune"], .siblingsChild)
        expect("Kerttu: Hilja and Urho are her siblings' spouses", kerttu, ["Hilja", "Urho"], .siblingsSpouse)
        expect("Kerttu: Eemeli is her spouse's sibling", kerttu, ["Eemeli"], .spousesSibling)

        let sirkka = Kinship.words(from: "Sirkka", people: clan.people, ties: clan.ties)
        expect("Sirkka: Eemeli is her spouse — a marriage the rows cannot hold is still entered", sirkka, ["Eemeli"], .spouse)
        expect("Sirkka: Oiva is her spouse's sibling", sirkka, ["Oiva"], .spousesSibling)

        let hilma = Kinship.words(from: "Hilma", people: clan.people, ties: clan.ties)
        expect("Hilma: Lyyli is her co-spouse (spouse, spouse): no word", hilma, ["Lyyli"], nil)
        expect("Hilma: Kerttu is her spouse's child", hilma, ["Kerttu"], .spousesChild)

        let matti = Kinship.words(from: "Matti", people: clan.people, ties: clan.ties)
        expect("Matti: Ritva is his cousin and his spouse — spouse, the shorter reading", matti, ["Ritva"], .spouse)
        expect("Matti: Veikko and Kaarina are cousins", matti, ["Veikko", "Kaarina"], .cousin)
        expect("Matti: Paavo is his spouse's parent", matti, ["Paavo"], .spousesParent)
        expect("Matti: Aune is his parent's sibling and his spouse's parent — the table puts the first first",
               matti, ["Aune"], .parentsSibling)
        expect("Matti: Mikko and Petra are his children's spouses", matti, ["Mikko", "Petra"], .childsSpouse)

        let jonne = Kinship.words(from: "Jonne", people: clan.people, ties: clan.ties)
        expect("Jonne: Elina is a friend", jonne, ["Elina"], .friend)
        expect("Jonne: Mikko is a friend's spouse — no path goes on through a friend", jonne, ["Mikko"], nil)
        check("Jonne: and nobody else has a word", jonne == ["Elina": .friend], difference(jonne, ["Elina": .friend]))

        let helmi = Kinship.words(from: "Helmi", people: clan.people, ties: clan.ties)
        expect("Helmi: Rauha is her sibling and her friend — sibling, the earlier row", helmi, ["Rauha"], .sibling)
        let onerva = Kinship.words(from: "Onerva", people: clan.people, ties: clan.ties)
        expect("Onerva: Mauri and Tarja are her parent's siblings, by sibling ties alone",
               onerva, ["Mauri", "Tarja"], .parentsSibling)

        print("— rules the clan does not reach —")
        do {
            let people = ["me", "parent", "parentsSpouse", "stepSibling"]
            let ties = [
                Tie(from: "parent", to: "parentsSpouse", bond: .spouse),
                Tie(from: "parent", to: "me", bond: .parent),
                Tie(from: "parentsSpouse", to: "stepSibling", bond: .parent),
            ]
            let words = Kinship.words(from: "me", people: people, ties: ties)
            expect("a step-sibling (up, spouse, down) has no word", words, ["stepSibling"], nil)
            expect("and the step-parent is a parent's spouse", words, ["parentsSpouse"], .parentsSpouse)
        }
        do {
            let people = ["a1", "a2", "b1", "b2"]
            let ties = [
                Tie(from: "a1", to: "a2", bond: .sibling), Tie(from: "b1", to: "b2", bond: .sibling),
                Tie(from: "a1", to: "b1", bond: .spouse), Tie(from: "a2", to: "b2", bond: .spouse),
            ]
            let fromA1 = Kinship.words(from: "a1", people: people, ties: ties)
            let fromB2 = Kinship.words(from: "b2", people: people, ties: ties)
            // Both readings are true both ways, so a fixed priority gives both
            // the same word; mirror-image words would need a priority that
            // looked at something other than the readings.
            check("two siblings married to two siblings: both say sibling's spouse, the earlier of two true rows",
                  fromA1["b2"] == .siblingsSpouse && fromB2["a1"] == .siblingsSpouse,
                  "a1 says \(spell(fromA1["b2"])), b2 says \(spell(fromB2["a1"]))")
        }
        do {
            let people = ["x", "y", "z"]
            let ties = [Tie(from: "x", to: "y", bond: .sibling), Tie(from: "y", to: "z", bond: .sibling)]
            let words = Kinship.words(from: "x", people: people, ties: ties)
            expect("a sibling's sibling is no word — a half-sibling's half-sibling can be a stranger", words, ["z"], nil)
        }
        do {
            let people = ["me", "friend", "friendsParent"]
            let ties = [
                Tie(from: "me", to: "friend", bond: .friend),
                Tie(from: "friendsParent", to: "friend", bond: .parent),
            ]
            let words = Kinship.words(from: "me", people: people, ties: ties)
            expect("a friend's parent is nothing of yours", words, ["friendsParent"], nil)
            let reversed = Kinship.words(
                from: "me", people: people,
                ties: [Tie(from: "friend", to: "me", bond: .friend)] + ties.dropFirst()
            )
            expect("a friendship entered the other way round is the same friendship", reversed, ["friend"], .friend)
        }
        do {
            let people = ["me", "parent", "parentsSibling", "cousin"]
            let kin = [
                Tie(from: "parent", to: "me", bond: .parent),
                Tie(from: "parent", to: "parentsSibling", bond: .sibling),
                Tie(from: "parentsSibling", to: "cousin", bond: .parent),
            ]
            expect("a cousin is a cousin", Kinship.words(from: "me", people: people, ties: kin), ["cousin"], .cousin)
            let befriended = kin + [Tie(from: "me", to: "cousin", bond: .friend)]
            expect("a cousin who is also a friend is a friend — one step is shorter than three",
                   Kinship.words(from: "me", people: people, ties: befriended), ["cousin"], .friend)
        }
        do {
            let people = ["me", "parent", "parentsSibling", "cousin", "child"]
            let ties = [
                Tie(from: "parent", to: "me", bond: .parent),
                Tie(from: "parent", to: "parentsSibling", bond: .sibling),
                Tie(from: "parentsSibling", to: "cousin", bond: .parent),
                Tie(from: "me", to: "child", bond: .parent),
                Tie(from: "cousin", to: "child", bond: .parent),
            ]
            let words = Kinship.words(from: "me", people: people, ties: ties)
            expect("a cousin who is also the other parent of your child: down-then-up names nothing, "
                + "and the cousin reading one step longer is not consulted", words, ["cousin"], nil)
        }

        print("— what the caller may hand in —")
        check("a root that is not among the people gets no words",
              Kinship.words(from: "Nobody", people: clan.people, ties: clan.ties).isEmpty
                  && Kinship.words(from: "Elina", people: clan.people.filter { $0 != "Elina" }, ties: clan.ties).isEmpty)
        do {
            let ties = [Tie(from: "ghost", to: "a", bond: .parent), Tie(from: "ghost", to: "b", bond: .parent)]
            let without = Kinship.words(from: "a", people: ["a", "b"], ties: ties)
            let with = Kinship.words(from: "a", people: ["a", "b", "ghost"], ties: ties)
            let answer: [String: Word] = ["ghost": .parent, "b": .sibling]
            check("a parent who is not among the people makes nobody a sibling, and one who is does",
                  without.isEmpty && with == answer,
                  "without: \(difference(without, [:])); with: \(difference(with, answer))")
        }
        let selfTies = [
            Tie(from: "Elina", to: "Elina", bond: .parent), Tie(from: "Matti", to: "Matti", bond: .spouse),
            Tie(from: "Jukka", to: "Jukka", bond: .sibling), Tie(from: "Elina", to: "Elina", bond: .friend),
        ]
        let variants: [(label: String, people: [String], ties: [Tie])] = [
            ("a tie from somebody to themselves changes no word", clan.people, clan.ties + selfTies),
            ("a card listed twice changes no word", clan.people + clan.people.reversed(), clan.ties),
            ("a tie entered twice changes no word", clan.people, clan.ties + clan.ties),
            ("a symmetric tie entered the other way round changes no word", clan.people, clan.ties.map {
                $0.bond == .parent ? $0 : Tie(from: $0.to, to: $0.from, bond: $0.bond)
            }),
            ("the ties in reverse order change no word", clan.people, clan.ties.reversed()),
            ("the ties shuffled change no word", clan.people, {
                var rng = SplitMix64(state: 7)
                return rng.shuffled(clan.ties)
            }()),
            ("the people in reverse order change no word", clan.people.reversed(), clan.ties),
        ]
        for variant in variants {
            let words = Kinship.words(from: "Elina", people: variant.people, ties: variant.ties)
            check(variant.label, words == elina, difference(words, elina))
        }

        print("— contradictions —")
        let sulo = Kinship.words(from: "Sulo", people: clan.people, ties: clan.ties)
        // K2 as written: up comes before down, so a pair entered as each
        // other's parent reads parent both ways. The tree keeps the earlier
        // link instead; the words cannot, because they must not depend on the
        // order of the ties.
        check("Onni, entered as Sulo's child twice and as his parent once, is his parent — up comes before down",
              sulo["Onni"] == .parent, spell(sulo["Onni"]))
        let suloParents = sulo.filter { $0.value == .parent }.keys.sorted()
        check("so Sulo has three parent words for his three distinct parents, Aapo, Hilma and Onni",
              suloParents == ["Aapo", "Hilma", "Onni"] && distinctParents(clan.people, clan.ties)["Sulo"] == 3,
              "\(suloParents)")
        do {
            let drawn = clan.ties.filter {
                !($0 == Tie(from: "Eemeli", to: "Sirkka", bond: .spouse)
                    || $0 == Tie(from: "Onni", to: "Sulo", bond: .parent))
            }
            let words = Kinship.words(from: "Elina", people: clan.people, ties: drawn)
            check("the two links the rows cannot hold change no word on Elina's phone", words == elina,
                  difference(words, elina))
        }

        print("— the labels —")
        let miswired = Word.allCases.filter { $0.label != $0.rawValue }
        check("every word's label is its own key — with no table here the lookup hands the key back, "
            + "so a case wired to its neighbour's key shows", miswired.isEmpty, "\(miswired)")

        print("— random families —")
        var rng = SplitMix64(state: 0x4B69_6E73_6869_7021)
        var literal = Tally(), mirrored = Tally(), absent = Tally(), parents = Tally(), untidy = Tally()
        var seen: Set<Word> = []
        var roots = 0, links = 0, pairs = 0, single = 0, several = 0, unmirrored = 0
        var unmirroredExample: String?
        for _ in 0 ..< families {
            let family = randomFamily(&rng)
            links += family.ties.count
            let reference = Literal(people: family.people, ties: family.ties)
            let parentCount = distinctParents(family.people, family.ties)
            let noisy = withNoise(family, &rng)
            var said: [String: [String: Word]] = [:]
            var ambiguous: [String: Set<String>] = [:]
            for root in family.people {
                roots += 1
                let words = Kinship.words(from: root, people: family.people, ties: family.ties)
                let truth = reference.read(from: root)
                literal.record(words == truth.words, "from \(root): \(difference(words, truth.words)) in \(family.ties)")
                absent.record(words[root] == nil, "\(root) has a word for themselves")
                parents.record(words.values.filter { $0 == .parent }.count == parentCount[root, default: 0], "\(root)")
                let again = Kinship.words(from: root, people: noisy.people, ties: noisy.ties)
                untidy.record(again == words, "from \(root): \(difference(again, words))")
                seen.formUnion(words.values)
                said[root] = words
                ambiguous[root] = truth.several
            }
            for a in family.people {
                let words = said[a] ?? [:]
                for b in family.people {
                    guard let word = words[b] else { continue }
                    pairs += 1
                    let back = said[b]?[a]
                    if ambiguous[a]?.contains(b) != true {
                        single += 1
                        mirrored.record(back == mirror(word), "\(a) calls \(b) \(word), \(b) calls \(a) \(spell(back))")
                    } else {
                        several += 1
                        if back != mirror(word) {
                            unmirrored += 1
                            if unmirroredExample == nil {
                                unmirroredExample = "\(a) calls \(b) \(word), \(b) calls \(a) \(spell(back))"
                            }
                        }
                    }
                }
            }
        }
        check("every word from every phone is the first row among all its shortest readings, "
            + "read by brute force (\(literal.checked) phones)", literal.failed == 0, literal.summary)
        // That nobody gets two words is the result's type — one `Word` per id —
        // so there is nothing to count.
        check("nobody has a word for themselves", absent.failed == 0, absent.summary)
        check("as many parent words as distinct parents", parents.failed == 0, parents.summary)
        check("the same family handed in shuffled, with ties entered twice, symmetric ties reversed, "
            + "self-ties, ids not among the people and cards listed twice, gives the same words",
              untidy.failed == 0, untidy.summary)
        check("a pair with one shortest reading answers in mirror image: parent–child, grandparent–grandchild, "
            + "great-grandparent–great-grandchild, spouse, sibling, cousin, second cousin, friend, "
            + "parent's sibling–sibling's child, grandparent's sibling–sibling's grandchild, "
            + "spouse's parent–child's spouse, spouse's sibling–sibling's spouse, spouse's child–parent's spouse, "
            + "and a parent's cousin gets no word back, because a cousin's child is no row (\(mirrored.checked) pairs)",
              mirrored.failed == 0, mirrored.summary)
        let unseen = Word.allCases.filter { !seen.contains($0) }
        check("the sweep reached every word", unseen.isEmpty, "never said: \(unseen)")

        print("— tie soup: contradictions, cycles, self-ties, strangers —")
        var soupLiteral = Tally(), soupReordered = Tally(), soupAbsent = Tally(), soupParents = Tally()
        var soupRoots = 0, soupLinks = 0
        for _ in 0 ..< soups {
            let soup = tieSoup(&rng)
            soupLinks += soup.ties.count
            let reference = Literal(people: soup.people, ties: soup.ties)
            let parentCount = distinctParents(soup.people, soup.ties)
            let reordering = (people: rng.shuffled(soup.people), ties: rng.shuffled(soup.ties))
            for root in soup.people {
                soupRoots += 1
                let words = Kinship.words(from: root, people: soup.people, ties: soup.ties)
                let truth = reference.read(from: root)
                soupLiteral.record(words == truth.words, "from \(root): \(difference(words, truth.words)) in \(soup.ties)")
                soupAbsent.record(words[root] == nil, "\(root)")
                soupParents.record(words.values.filter { $0 == .parent }.count == parentCount[root, default: 0], "\(root)")
                let again = Kinship.words(from: root, people: reordering.people, ties: reordering.ties)
                soupReordered.record(again == words, "from \(root): \(difference(again, words))")
            }
        }
        check("every word is still the first row among all its shortest readings (\(soupLiteral.checked) phones)",
              soupLiteral.failed == 0, soupLiteral.summary)
        check("nobody has a word for themselves", soupAbsent.failed == 0, soupAbsent.summary)
        check("as many parent words as distinct parents, a parent who is also a child included",
              soupParents.failed == 0, soupParents.summary)
        check("and another order of the same ties gives the same words", soupReordered.failed == 0, soupReordered.summary)

        let elapsed = clock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("""

        \(families) random families (\(roots) phones, \(links) ties), \(pairs) ordered pairs with a word: \
        \(single) with one shortest reading, \(several) with several, \(unmirrored) of those not in mirror image\
        \(unmirroredExample.map { " (\($0))" } ?? ""); \(soups) tie soups (\(soupRoots) phones, \(soupLinks) ties); \
        \(String(format: "%.2f", seconds)) s
        """)
        print(failures == 0 ? "all checks passed" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - The clan

    static let loose = ["Kustaa", "Alma", "Yrjö", "Saima", "Lauri", "Hellin", "Verneri"]

    /// The app's `-seed clan`, ids as names, cards oldest first.
    static func clanFixture() -> (people: [String], ties: [Tie]) {
        var ties: [Tie] = []
        func couple(_ a: String, _ b: String, _ children: [String]) {
            ties.append(Tie(from: a, to: b, bond: .spouse))
            for child in children {
                ties.append(Tie(from: a, to: child, bond: .parent))
                ties.append(Tie(from: b, to: child, bond: .parent))
            }
        }
        func parent(_ a: String, _ child: String) { ties.append(Tie(from: a, to: child, bond: .parent)) }
        func siblings(_ a: String, _ b: String) { ties.append(Tie(from: a, to: b, bond: .sibling)) }
        func friends(_ a: String, _ b: String) { ties.append(Tie(from: a, to: b, bond: .friend)) }

        couple("Aapo", "Hilma", ["Väinö", "Impi", "Sulo"])
        couple("Aapo", "Lyyli", ["Kerttu"])
        couple("Väinö", "Hilja", ["Toivo", "Martta", "Eino", "Aune", "Reino", "Sirkka"])
        couple("Impi", "Urho", [])
        parent("Sulo", "Onni")
        couple("Kerttu", "Oiva", ["Helvi", "Paavo"])
        siblings("Oiva", "Eemeli")
        couple("Toivo", "Anneli", ["Matti", "Liisa"])
        parent("Martta", "Veikko")
        couple("Eino", "Helvi", ["Kaarina"])
        couple("Aune", "Paavo", ["Ritva"])
        couple("Eemeli", "Sirkka", [])   // across generations: the tree names it and does not draw it
        parent("Sulo", "Onni")           // entered a second time
        parent("Onni", "Sulo")           // and once the other way round
        couple("Matti", "Ritva", ["Elina", "Jukka"])
        couple("Veikko", "Tuula", ["Sanni"])
        couple("Kaarina", "Heikki", ["Aleksi"])
        couple("Elina", "Mikko", ["Venla", "Oskari", "Aino"])
        couple("Jukka", "Petra", ["Elias"])
        couple("Aleksi", "Noora", ["Iiris"])
        siblings("Sisko", "Mauri")
        siblings("Mauri", "Tarja")
        siblings("Sisko", "Tarja")
        parent("Sisko", "Onerva")
        couple("Otto", "Helmi", [])
        siblings("Helmi", "Rauha")
        friends("Helmi", "Rauha")
        friends("Elina", "Jonne")

        let people = [
            "Aapo", "Hilma", "Lyyli", "Väinö", "Impi", "Sulo", "Kerttu", "Hilja", "Urho", "Oiva", "Eemeli",
            "Onni", "Toivo", "Martta", "Eino", "Aune", "Reino", "Sirkka", "Helvi", "Paavo", "Anneli",
            "Matti", "Liisa", "Veikko", "Kaarina", "Ritva", "Tuula", "Sanni", "Heikki", "Aleksi", "Elina",
            "Jukka", "Mikko", "Venla", "Oskari", "Aino", "Petra", "Elias", "Noora", "Iiris",
            "Sisko", "Mauri", "Tarja", "Onerva", "Otto", "Helmi", "Rauha", "Jonne",
        ] + loose
        return (people, ties)
    }

    // MARK: - The reference

    /// The spec's table as the spec writes it, friend row included, in its
    /// priority order — kept apart from the engine's copy so that a row moved
    /// or mistyped there shows here.
    static let rows: [(spelled: String, word: Word)] = [
        ("up", .parent), ("up up", .grandparent), ("up up up", .greatGrandparent),
        ("down", .child), ("down down", .grandchild), ("down down down", .greatGrandchild),
        ("spouse", .spouse), ("sibling", .sibling),
        ("up sibling", .parentsSibling), ("up sibling down", .cousin),
        ("up up sibling", .grandparentsSibling), ("up up sibling down", .parentsCousin),
        ("up up sibling down down", .secondCousin),
        ("sibling down", .siblingsChild), ("sibling down down", .siblingsGrandchild),
        ("sibling spouse", .siblingsSpouse),
        ("spouse up", .spousesParent), ("spouse sibling", .spousesSibling), ("spouse down", .spousesChild),
        ("down spouse", .childsSpouse), ("up spouse", .parentsSpouse),
        ("friend", .friend),
    ]

    /// A reading as a number, one octal digit per step, so that a set of
    /// readings is a set of integers.
    static let digits = ["up": 1, "down": 2, "spouse": 3, "sibling": 4, "friend": 5]
    static let rowCodes: [(code: Int, word: Word)] = rows.map { row in
        (row.spelled.split(separator: " ").reduce(0) { $0 * 8 + digits[String($1)]! }, row.word)
    }
    /// Which row spells a reading, the first one if two did.
    static let rowOf: [Int: Int] = Dictionary(
        rowCodes.enumerated().map { ($1.code, $0) }, uniquingKeysWith: min
    )

    /// K1 and K2 read literally and written apart from the engine: every
    /// shortest walk enumerated one by one, its steps spelled out, and the
    /// first row in the table that any of them spells. Slow on purpose — it
    /// is the reference, not the answer.
    struct Literal {
        let ids: [String]
        let slot: [String: Int]
        /// Everybody one step away, with the step's digit.
        let steps: [[(to: Int, digit: Int)]]
        let friends: [[Int]]

        init(people: [String], ties: [Tie]) {
            var slot: [String: Int] = [:]
            var ids: [String] = []
            for id in people where slot[id] == nil {
                slot[id] = ids.count
                ids.append(id)
            }
            var parentsOf = [Set<Int>](repeating: [], count: ids.count)
            var spousesOf = [Set<Int>](repeating: [], count: ids.count)
            var siblingsOf = [Set<Int>](repeating: [], count: ids.count)
            var friendsOf = [Set<Int>](repeating: [], count: ids.count)
            for tie in ties {
                guard let a = slot[tie.from], let b = slot[tie.to], a != b else { continue }
                switch tie.bond {
                case .parent: parentsOf[b].insert(a)
                case .spouse: spousesOf[a].insert(b); spousesOf[b].insert(a)
                case .sibling: siblingsOf[a].insert(b); siblingsOf[b].insert(a)
                case .friend: friendsOf[a].insert(b); friendsOf[b].insert(a)
                }
            }
            var steps = [[(to: Int, digit: Int)]](repeating: [], count: ids.count)
            for a in ids.indices {
                for b in ids.indices where b != a {
                    if parentsOf[a].contains(b) { steps[a].append((b, 1)) }
                    if parentsOf[b].contains(a) { steps[a].append((b, 2)) }
                    if spousesOf[a].contains(b) { steps[a].append((b, 3)) }
                    if siblingsOf[a].contains(b) || !parentsOf[a].isDisjoint(with: parentsOf[b]) {
                        steps[a].append((b, 4))
                    }
                }
            }
            self.ids = ids
            self.slot = slot
            self.steps = steps
            self.friends = friendsOf.map { $0.sorted() }
        }

        /// The words from `root`, and everybody who has more than one shortest
        /// reading from there.
        func read(from root: String) -> (words: [String: Word], several: Set<String>) {
            guard let origin = slot[root] else { return ([:], []) }
            var distance = [Int](repeating: -1, count: ids.count)
            distance[origin] = 0
            var queue = [origin]
            var head = 0
            while head < queue.count {
                let person = queue[head]
                head += 1
                if distance[person] == 5 { continue }
                for (other, _) in steps[person] where distance[other] < 0 {
                    distance[other] = distance[person] + 1
                    queue.append(other)
                }
            }
            var readings = [[Int]](repeating: [], count: ids.count)
            func walk(_ person: Int, _ code: Int) {
                if person != origin { readings[person].append(code) }
                for (other, digit) in steps[person] where distance[other] == distance[person] + 1 {
                    walk(other, code * 8 + digit)
                }
            }
            walk(origin, 0)
            // A friend is one step away; a relative one step away as well has
            // both readings of length one, anybody else only the friend's.
            for friend in friends[origin] {
                if distance[friend] == 1 { readings[friend].append(5) } else { readings[friend] = [5] }
            }
            var words: [String: Word] = [:]
            var several: Set<String> = []
            for person in ids.indices where !readings[person].isEmpty {
                let spelled = readings[person]
                if spelled.contains(where: { $0 != spelled[0] }) { several.insert(ids[person]) }
                if let first = spelled.compactMap({ rowOf[$0] }).min() { words[ids[person]] = rowCodes[first].word }
            }
            return (words, several)
        }
    }

    /// The spec's pairs: what B calls A when A calls B `word` and only one
    /// shortest reading joins them.
    static func mirror(_ word: Word) -> Word? {
        switch word {
        case .parent: return .child
        case .child: return .parent
        case .grandparent: return .grandchild
        case .grandchild: return .grandparent
        case .greatGrandparent: return .greatGrandchild
        case .greatGrandchild: return .greatGrandparent
        case .spouse: return .spouse
        case .sibling: return .sibling
        case .cousin: return .cousin
        case .secondCousin: return .secondCousin
        case .friend: return .friend
        case .parentsSibling: return .siblingsChild
        case .siblingsChild: return .parentsSibling
        case .grandparentsSibling: return .siblingsGrandchild
        case .siblingsGrandchild: return .grandparentsSibling
        case .spousesParent: return .childsSpouse
        case .childsSpouse: return .spousesParent
        case .spousesSibling: return .siblingsSpouse
        case .siblingsSpouse: return .spousesSibling
        case .spousesChild: return .parentsSpouse
        case .parentsSpouse: return .spousesChild
        case .parentsCousin: return nil   // a cousin's child (up sibling down down) is no row
        }
    }

    /// How many different people each person has entered as a parent, among
    /// the people and themselves excepted.
    static func distinctParents(_ people: [String], _ ties: [Tie]) -> [String: Int] {
        let present = Set(people)
        var parents: [String: Set<String>] = [:]
        for tie in ties where tie.bond == .parent && tie.from != tie.to
            && present.contains(tie.from) && present.contains(tie.to) {
            parents[tie.to, default: []].insert(tie.from)
        }
        return parents.mapValues(\.count)
    }

    // MARK: - Random families

    /// A family grown the way the archive grows one: founders, marriages (some
    /// of them second), zero to six children per union, a child with one
    /// parent entered, now and then a cousin marriage, a spouse who arrives
    /// with siblings and no parents — and sometimes two of those marrying two
    /// siblings — a few loose people and a few friendships. Ties shuffled.
    static func randomFamily(_ rng: inout SplitMix64) -> (people: [String], ties: [Tie]) {
        var people: [String] = []
        var ties: [Tie] = []
        var generation: [Int] = []
        var parentsOf: [[Int]] = []
        var married: [Bool] = []
        var born: [Bool] = []
        let cap = 6 + rng.below(35)

        func person(_ level: Int, born isBorn: Bool) -> Int {
            people.append("p\(people.count)")
            generation.append(level)
            parentsOf.append([])
            married.append(false)
            born.append(isBorn)
            return people.count - 1
        }
        func tie(_ a: Int, _ b: Int, _ bond: Kinship.Bond) {
            ties.append(Tie(from: people[a], to: people[b], bond: bond))
        }
        func marry(_ a: Int, _ b: Int) {
            tie(a, b, .spouse)
            married[a] = true
            married[b] = true
        }

        var unions: [[Int]] = []
        for _ in 0 ..< 1 + rng.below(2) {
            let founder = person(0, born: true)
            if rng.chance(85) {
                let spouse = person(0, born: false)
                marry(founder, spouse)
                unions.append([founder, spouse])
            } else {
                unions.append([founder])
            }
        }
        var next = 0
        while next < unions.count, people.count < cap {
            let union = unions[next]
            next += 1
            let level = generation[union[0]] + 1
            if level > 3 { continue }
            let count = rng.chance(10) ? 5 + rng.below(2) : rng.below(5)
            var children: [Int] = []
            for _ in 0 ..< count where people.count < cap {
                let child = person(level, born: true)
                for parent in union {
                    tie(parent, child, .parent)
                    parentsOf[child].append(parent)
                }
                children.append(child)
            }
            if children.count >= 2, rng.chance(10) { tie(children[0], children[1], .sibling) }
            for child in children where people.count < cap && !married[child] && rng.chance(70) {
                let cousin = rng.chance(10)
                    ? people.indices.first { other in
                        other != child && born[other] && !married[other] && generation[other] == level
                            && Set(parentsOf[other]).isDisjoint(with: parentsOf[child])
                    }
                    : nil
                if let cousin {
                    marry(child, cousin)
                    unions.append([child, cousin])
                } else {
                    let spouse = person(level, born: false)
                    marry(child, spouse)
                    unions.append([child, spouse])
                    if rng.chance(15) {
                        var group = [spouse]
                        for _ in 0 ..< 1 + rng.below(2) where people.count < cap {
                            let sibling = person(level, born: false)
                            for member in group { tie(member, sibling, .sibling) }
                            group.append(sibling)
                        }
                        if group.count > 1, rng.chance(40),
                           let other = children.first(where: { $0 != child && !married[$0] }) {
                            marry(other, group[1])
                            unions.append([other, group[1]])
                        }
                    }
                }
                if rng.chance(10), people.count < cap {
                    let second = person(level, born: false)
                    marry(child, second)
                    unions.append([child, second])
                }
            }
            for child in children where !married[child] && rng.chance(8) { unions.append([child]) }
        }
        for _ in 0 ..< rng.below(3) { _ = person(0, born: false) }
        for _ in 0 ..< rng.below(4) {
            let a = rng.below(people.count), b = rng.below(people.count)
            if a != b { tie(a, b, .friend) }
        }
        return (people, rng.shuffled(ties))
    }

    /// The same family as the caller might hand it in on a bad day: ties
    /// entered twice, symmetric ones the other way round, ties to cards that
    /// are not among the people — a missing parent shared by two of them
    /// among them — ties from somebody to themselves, and cards listed twice.
    static func withNoise(
        _ family: (people: [String], ties: [Tie]), _ rng: inout SplitMix64
    ) -> (people: [String], ties: [Tie]) {
        var ties = family.ties
        let count = family.people.count
        for _ in 0 ..< 1 + rng.below(3) where !family.ties.isEmpty {
            ties.append(family.ties[rng.below(family.ties.count)])
        }
        for tie in family.ties where tie.bond != .parent && rng.chance(30) {
            ties.append(Tie(from: tie.to, to: tie.from, bond: tie.bond))
        }
        ties.append(Tie(from: "missing", to: family.people[rng.below(count)], bond: .parent))
        ties.append(Tie(from: "missing", to: family.people[rng.below(count)], bond: .parent))
        ties.append(Tie(from: family.people[rng.below(count)], to: "gone", bond: .spouse))
        ties.append(Tie(from: "gone", to: family.people[rng.below(count)], bond: .friend))
        let bonds: [Kinship.Bond] = [.parent, .spouse, .sibling, .friend]
        for bond in bonds {
            let someone = family.people[rng.below(count)]
            ties.append(Tie(from: someone, to: someone, bond: bond))
        }
        let people = family.people + (0 ..< 1 + rng.below(3)).map { _ in family.people[rng.below(count)] }
        return (rng.shuffled(people), rng.shuffled(ties))
    }

    /// Ties drawn at random between a handful of people: parents both ways
    /// round, cycles, a spouse who is also a sibling, self-ties and strangers.
    /// No family looks like this; the engine must still answer exactly as K2
    /// reads, the same way every time.
    static func tieSoup(_ rng: inout SplitMix64) -> (people: [String], ties: [Tie]) {
        let count = 2 + rng.below(9)
        let people = (0 ..< count).map { "s\($0)" }
        let bonds: [Kinship.Bond] = [.parent, .parent, .spouse, .sibling, .friend]
        var ties: [Tie] = []
        for _ in 0 ..< rng.below(3 * count + 1) {
            let from = rng.chance(5) ? "stranger" : people[rng.below(count)]
            let to = rng.chance(5) ? "stranger" : people[rng.below(count)]
            ties.append(Tie(from: from, to: to, bond: bonds[rng.below(bonds.count)]))
        }
        return (people, ties)
    }

    // MARK: - Plumbing

    /// SplitMix64: the same numbers on every machine and in every process.
    struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

        mutating func chance(_ percent: Int) -> Bool { below(100) < percent }

        /// Fisher–Yates with this generator, rather than the standard
        /// library's shuffle, whose algorithm is not promised to stay put.
        mutating func shuffled<T>(_ items: [T]) -> [T] {
            var items = items
            for index in stride(from: items.count - 1, to: 0, by: -1) {
                items.swapAt(index, below(index + 1))
            }
            return items
        }
    }

    /// One invariant over many cases: how many were checked, how many failed,
    /// and the first failure spelled out.
    struct Tally {
        var checked = 0
        var failed = 0
        var first: String?

        mutating func record(_ ok: Bool, _ detail: @autoclosure () -> String) {
            checked += 1
            if !ok {
                failed += 1
                if first == nil { first = detail() }
            }
        }

        var summary: String { "\(failed) of \(checked); first: \(first ?? "")" }
    }

    static func spell(_ word: Word?) -> String { word.map { "\($0)" } ?? "no word" }

    /// What differs between two answers, by id, sorted.
    static func difference(_ got: [String: Word], _ want: [String: Word]) -> String {
        Set(got.keys).union(want.keys).sorted()
            .filter { got[$0] != want[$0] }
            .map { "\($0): \(spell(got[$0])), expected \(spell(want[$0]))" }
            .joined(separator: "; ")
    }
}
