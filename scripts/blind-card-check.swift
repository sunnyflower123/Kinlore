// Checks which names the blind card deals beside the proposal, and where the
// answer sits among them.
//
// The card (`BlindConfirmation`) asks "Who is this?" over the proposal and
// three confirmed people, the proposal unmarked among them. Until 29 Sep 2026
// the three were the archive's three newest confirmed people on every card,
// so in `-seed large`, sixty people and five proposals, the one name that
// changed from card to card was the answer, and two cards gave it away. No
// seed, test or picture showed it, because each of them has exactly three
// people to choose from, and three leave nothing to choose.
//
// Every way of being wrong here is silent: each card on its own is a fair
// question. So this deals many cards from one archive and counts how many
// different threes the proposals get, whether everybody is dealt, and which
// seat the answer takes. The last is the sharp one. Dealing by the hash that
// also seats the names takes the three with the lowest seats, and the answer
// then sits last on most cards, 308 of the 400 below: a fix for the first
// leak that makes a second one.
//
// The cards in the README, the Devpost gallery and the film are pinned as their
// pictures show them.
//
// Costs nothing: no simulator, no network, no key. `MemoryStore` below stands
// in for the real one and answers the four questions the card asks it, in the
// real one's order.
//
//   swiftc -parse-as-library -o /tmp/blind-card-check scripts/blind-card-check.swift \
//     ios/Kinlore/Services/BlindConfirmation.swift ios/Kinlore/Model/Models.swift

import Foundation

/// The card's four questions, answered as `MemoryStore` answers them: people
/// newest first, tellings newest first.
@MainActor
final class MemoryStore {
    var subjects: [Subject]
    let told: [Memory]

    init(subjects: [Subject], told: [Memory]) {
        self.subjects = subjects
        self.told = told
    }

    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }

    func memories(mentioning subjectID: String) -> [Memory] {
        told.filter { $0.mentionedSubjectIDs.contains(subjectID) }.sorted { $0.createdAt > $1.createdAt }
    }

    func subject(id: String) -> Subject? {
        subjects.first { $0.id == id }
    }

    func confirm(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].confirmed = true
    }
}

@main
enum BlindCardCheck {
    @MainActor
    static func main() {
        var failures = 0

        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        /// A family's card: one photograph, one telling about it that names
        /// `proposal` and `named`, and the confirmed people `pool`, the first
        /// of them the oldest.
        func card(_ proposal: String, pool: [String], named: [String] = []) -> BlindConfirmation.Card? {
            let start = Date(timeIntervalSince1970: 1_600_000_000)
            var subjects = pool.enumerated().map { index, id in
                Subject(id: id, kind: .person, title: id, createdAt: start.addingTimeInterval(Double(index) * 86_400))
            }
            subjects.append(Subject(id: proposal, kind: .person, title: proposal, confirmed: false,
                                    createdAt: start.addingTimeInterval(1_000 * 86_400)))
            subjects.append(Subject(id: "photo", kind: .photo, title: "", imageFilename: "photo.jpg"))
            let telling = Memory(id: "telling", subjectID: "photo", authorName: "", body: "", source: .voice,
                                 mentionedSubjectIDs: [proposal] + named)
            return BlindConfirmation.next(in: MemoryStore(subjects: subjects, told: [telling]))
        }

        func ids(_ card: BlindConfirmation.Card?) -> [String] {
            card?.names.map(\.id) ?? []
        }

        // Identifiers shaped like the app's own, `UUID().uuidString`, and the
        // same on every run.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func uuid() -> String {
            var hex = ""
            for _ in 0..<16 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                hex += String(format: "%02X", UInt8(truncatingIfNeeded: state >> 56))
            }
            let cuts = [8, 12, 16, 20]
            var out = ""
            for (index, character) in hex.enumerated() {
                if cuts.contains(index) { out += "-" }
                out.append(character)
            }
            return out
        }

        print("— two proposals in one family —")
        let six = (0..<6).map { _ in uuid() }
        let first = card(uuid(), pool: six)
        let second = card(uuid(), pool: six)
        check("six confirmed people, and two proposals are dealt different threes",
              first != nil && second != nil
                  && Set(ids(first)).intersection(six) != Set(ids(second)).intersection(six),
              "\(ids(first)) and \(ids(second))")

        print("— four hundred cards from twelve people —")
        let twelve = (0..<12).map { _ in uuid() }
        var threes: Set<[String]> = []
        var dealt: [String: Int] = [:]
        var seats = [0, 0, 0, 0]
        var malformed: [String] = []
        let cards = 400
        for _ in 0..<cards {
            let proposal = uuid()
            guard let drawn = card(proposal, pool: twelve) else {
                malformed.append("no card")
                continue
            }
            let names = ids(drawn)
            let decoys = names.filter { $0 != proposal }
            if names.count != 4 || decoys.count != 3 || Set(names).count != 4 || drawn.person.id != proposal {
                malformed.append("\(names)")
            }
            threes.insert(decoys.sorted())
            for decoy in decoys { dealt[decoy, default: 0] += 1 }
            if let seat = names.firstIndex(of: proposal) { seats[seat] += 1 }
        }
        check("every card is the proposal and three others, once each", malformed.isEmpty,
              "\(malformed.prefix(3))")
        // 220 threes can be made from twelve people, and 400 cards dealt at
        // random reach about 185 of them. Taking the newest three reaches one.
        check("the cards are dealt many different threes", threes.count >= 120, "\(threes.count) of 220")
        let never = twelve.filter { dealt[$0] == nil }
        let most = dealt.values.max() ?? 0
        check("everybody is dealt, and nobody to most cards", never.isEmpty && most < cards / 2,
              "\(never.count) never dealt, one dealt to \(most) of \(cards)")
        // A quarter each is 100; 70 and 130 are well over four standard
        // deviations out, and dealing by `seat` puts nearly 400 in the last.
        let fair = seats.allSatisfy { (70...130).contains($0) }
        check("the answer sits in each of the four seats about as often", fair, "seats \(seats)")

        print("— what a card may never deal —")
        let named = Array(twelve.prefix(8))
        var leaked: [String] = []
        for _ in 0..<50 {
            let names = ids(card(uuid(), pool: twelve, named: named))
            leaked += names.filter(named.contains)
        }
        check("nobody the same telling named is a decoy", leaked.isEmpty, "\(Set(leaked).count) named people dealt")
        check("one confirmed person is too few, and there is no card",
              card(uuid(), pool: Array(twelve.prefix(1))) == nil)
        check("two make a card of three, which is the fewest",
              ids(card(uuid(), pool: Array(twelve.prefix(2)))).count == 3)
        let again = uuid()
        check("the same archive deals the same card twice, in the same seats",
              ids(card(again, pool: twelve)) == ids(card(again, pool: twelve)))

        print("— the cards in the pictures —")
        // Each has exactly three people to deal from, so dealing changes
        // nothing on them and only the seats decide the order: the README's
        // alt text, the Devpost gallery's `-seed film-week` and the film's
        // `-seed film`, and Kerttu's card in `-seed film-family`.
        let archive = ["demo-eeva", "demo-kalle", "demo-sanni"]
        check("the README's card reads Sanni, Aino, Eeva, Kalle",
              ids(card("demo-aino", pool: archive)) == ["demo-sanni", "demo-aino", "demo-eeva", "demo-kalle"],
              "\(ids(card("demo-aino", pool: archive)))")
        let film = ["demo-film-elli", "demo-film-aino", "demo-film-liisa"]
        let helmi = ids(card("demo-film-proposal", pool: film + ["demo-film-toivo"], named: ["demo-film-toivo"]))
        check("the film's card reads Aino, Elli, Helmi, Liisa",
              helmi == ["demo-film-aino", "demo-film-elli", "demo-film-proposal", "demo-film-liisa"], "\(helmi)")
        let kerttu = ids(card("demo-film-kerttu", pool: film + ["demo-film-proposal", "demo-film-toivo"],
                              named: ["demo-film-proposal", "demo-film-toivo"]))
        check("Kerttu's card in film-family reads Liisa, Aino, Elli, Kerttu",
              kerttu == ["demo-film-liisa", "demo-film-aino", "demo-film-elli", "demo-film-kerttu"], "\(kerttu)")

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
