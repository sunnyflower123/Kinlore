// Checks the guessing round's name masking against Finnish inflection.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -o /tmp/guess-mask-check scripts/guess-mask-check.swift \
//     ios/Memorize/Model/GuessRound.swift && /tmp/guess-mask-check
//
// This is the one part of the feature that fails silently. A round that leaks
// the answer still looks like a working round — nobody notices until a family
// member sees "Ainolle" standing next to the gap where "Aino" used to be. The
// heuristic is a guess about a language, so it is checked against the language.
//
// The sample sentences are Finnish because that is the input under test;
// translating them would test something else. Everything around them is
// English, as the repo requires. See CLAUDE.md.
//
// It compiles the REAL ios/Memorize/Model/GuessRound.swift. The types below are
// the minimum stubs that file needs — the point is to exercise the shipping
// code, not a copy of it that can drift.

import Foundation

enum SubjectKind: String { case photo, person, place, event }

struct Subject: Identifiable, Hashable {
    var id = UUID().uuidString
    var kind: SubjectKind
    var title: String
    var mergedInto: String?
    var displayTitle: String { title.isEmpty ? "Valokuva" : title }
}

struct Memory: Identifiable, Hashable {
    var id = UUID().uuidString
    var subjectID: String
    var authorID: String?
    var body: String
    var createdAt = Date()
    var mentionedSubjectIDs: [String] = []
    /// Taken back by the teller (§19). Here so that `told` below can be the same
    /// filter the app applies — a round built on a withdrawn telling is exactly
    /// the kind of thing this script exists to catch.
    var deletedAt: Date?
    var isAwaitingTranscription: Bool { body.isEmpty }
}

struct Guess: Identifiable, Hashable {
    var id: String { "\(memoryID)|\(memberID)" }
    var memoryID: String
    var memberID: String
    /// Nil = "En muista".
    var subjectID: String?
}

@MainActor
final class MemoryStore {
    var subjects: [Subject] = []
    var memories: [Memory] = []
    var told: [Memory] { memories.filter { $0.deletedAt == nil } }
    var guesses: [Guess] = []
    func subject(id: String) -> Subject? { subjects.first { $0.id == id } }
    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects.filter { $0.kind == kind && $0.mergedInto == nil }
    }
    func isEmpty(_ subject: Subject) -> Bool {
        !memories.contains { $0.subjectID == subject.id }
    }
    func soleMentionedPerson(in memory: Memory) -> Subject? {
        let people = memory.mentionedSubjectIDs
            .compactMap { subject(id: $0) }
            .filter { $0.kind == .person && $0.mergedInto == nil }
        return people.count == 1 ? people.first : nil
    }
}

// ---------------------------------------------------------------- checks

var failures = 0

func expect(_ label: String, _ masked: GuessRoundBuilder.MaskedText?, _ expected: String?) {
    let actual = masked?.text
    if actual == expected {
        print("  ok   \(label): \(actual.map { "\"\($0)\"" } ?? "nil")")
    } else {
        failures += 1
        print("  FAIL \(label)")
        print("       got      \(actual.map { "\"\($0)\"" } ?? "nil")")
        print("       expected \(expected.map { "\"\($0)\"" } ?? "nil")")
    }
}

let M = GuessRoundBuilder.mask

func maskChecks() {
print("— inflection —")
expect(
    "nominative + genitive + allative",
    GuessRoundBuilder.maskName("Aino", in: "Aino oli sisareni. Ainon kanssa uitiin, ja Ainolle nauroin aina."),
    "\(M) oli sisareni. \(M) kanssa uitiin, ja \(M) nauroin aina."
)
expect(
    "consonant gradation kk → k",
    GuessRoundBuilder.maskName("Pekka", in: "Pekka tuli. Pekan auto oli sininen."),
    "\(M) tuli. \(M) auto oli sininen."
)
expect(
    "-nen surname stem",
    GuessRoundBuilder.maskName("Virtanen", in: "Virtanen asui siinä. Virtasen talo paloi."),
    "\(M) asui siinä. \(M) talo paloi."
)
expect(
    "two-word name collapses to one gap",
    GuessRoundBuilder.maskName("Isoäiti Aino", in: "Isoäiti Aino leipoi joka lauantai."),
    "\(M) leipoi joka lauantai."
)
expect(
    "hyphenated name stays one word",
    GuessRoundBuilder.maskName("Liisa-Maija", in: "Liisa-Maija tuli käymään. Liisa-Maijan kanssa."),
    "\(M) tuli käymään. \(M) kanssa."
)

print("— things that must NOT be masked —")
expect(
    "lowercase word sharing the stem survives",
    GuessRoundBuilder.maskName("Aino", in: "Aino tuli aina ja ainakin kerran viikossa."),
    "\(M) tuli aina ja ainakin kerran viikossa."
)
expect(
    "long word sharing the stem survives",
    GuessRoundBuilder.maskName("Aino", in: "Aino kävi ainoastaan sunnuntaisin."),
    "\(M) kävi ainoastaan sunnuntaisin."
)
expect(
    "another capitalised name survives",
    GuessRoundBuilder.maskName("Aino", in: "Aino ja Eeva olivat siskoksia, Kuopiosta molemmat."),
    "\(M) ja Eeva olivat siskoksia, Kuopiosta molemmat."
)

print("— refusals (nil = no round is built) —")
expect(
    "name never appears",
    GuessRoundBuilder.maskName("Aino", in: "Hän oli sisareni ja asui lähellä."),
    nil
)
expect(
    "name too short to stem safely",
    GuessRoundBuilder.maskName("Jo", in: "Jo oli täällä."),
    nil
)

print("— punctuation and case endings —")
expect(
    "trailing punctuation is kept",
    GuessRoundBuilder.maskName("Puumala", in: "Kesät oltiin Puumalassa, ja Puumalaan mentiin junalla."),
    "Kesät oltiin \(M), ja \(M) mentiin junalla."
)
expect(
    "quotes and parentheses survive",
    GuessRoundBuilder.maskName("Eevertti", in: "Setä (Eevertti) sanoi: \"Eevertin vene on rannassa.\""),
    "Setä (\(M)) sanoi: \"\(M) vene on rannassa.\""
)
}

// ---------------------------------------------------------------- round rules

@MainActor
func roundChecks() {
    print("— round eligibility —")
    let store = MemoryStore()
    let aino = Subject(kind: .person, title: "Aino")
    let eeva = Subject(kind: .person, title: "Eeva")
    let kalle = Subject(kind: .person, title: "Kalle")
    let sanni = Subject(kind: .person, title: "Sanni")
    let photo = Subject(kind: .photo, title: "")
    store.subjects = [aino, eeva, kalle, sanni, photo]

    func check(_ label: String, _ memory: Memory, _ expected: Bool) {
        let round = GuessRoundBuilder.round(for: memory, store: store, memberID: "me")
        if (round != nil) == expected {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label): round \(round == nil ? "not built" : "built"), expected the opposite")
        }
    }

    // A realistic length. The round rules require enough story to survive the
    // masking, so a one-line body is not a fair test of anything else.
    let body = "Aino tuli mökille joka kesä, ja Ainon kanssa soudettiin saareen kalaan "
        + "aamuvarhaisella. Kahvipannu oli aina mukana, ja rannassa istuttiin pitkään puhumassa."

    check("ordinary memory by someone else", Memory(
        subjectID: photo.id, authorID: "mummo", body: body, mentionedSubjectIDs: [aino.id]
    ), true)

    check("my own memory", Memory(
        subjectID: photo.id, authorID: "me", body: body, mentionedSubjectIDs: [aino.id]
    ), false)

    check("author unknown (local-only archive)", Memory(
        subjectID: photo.id, authorID: nil, body: body, mentionedSubjectIDs: [aino.id]
    ), false)

    check("two people named", Memory(
        subjectID: photo.id, authorID: "mummo",
        body: "Aino ja Eeva tulivat mökille, ja Ainon kanssa soudettiin saareen kalaan "
            + "aamuvarhaisella. Kahvipannu oli mukana, ja rannassa istuttiin pitkään puhumassa.",
        mentionedSubjectIDs: [aino.id, eeva.id]
    ), false)

    check("memory told about the answer herself", Memory(
        subjectID: aino.id, authorID: "mummo", body: body, mentionedSubjectIDs: [aino.id]
    ), false)

    // A telling the teller took back (§19). It is an ordinary memory in every
    // other respect, which is the point: nothing about the round itself says no,
    // only the tombstone does — and a round built on a withdrawn story would put
    // it in front of the whole family.
    check("a telling that was taken back", Memory(
        subjectID: photo.id, authorID: "mummo", body: body,
        mentionedSubjectIDs: [aino.id], deletedAt: Date()
    ), false)

    check("audio not yet transcribed", Memory(
        subjectID: photo.id, authorID: "mummo", body: "", mentionedSubjectIDs: [aino.id]
    ), false)

    check("too short to recognise anyone from", Memory(
        subjectID: photo.id, authorID: "mummo",
        body: "Aino oli sisareni ja asui lähellä.", mentionedSubjectIDs: [aino.id]
    ), false)

    check("mostly gaps", Memory(
        subjectID: photo.id, authorID: "mummo",
        body: "Aino, Aino, Ainon, Ainolle, Aino ja Aino, ja sitten Aino tuli taas Ainon kanssa.",
        mentionedSubjectIDs: [aino.id]
    ), false)

    store.subjects = [aino, eeva, photo]
    check("too few people for four options", Memory(
        subjectID: photo.id, authorID: "mummo", body: body, mentionedSubjectIDs: [aino.id]
    ), false)

    // Stability: the same round must look identical on every device and on
    // every redraw, or "which option moved" becomes a clue.
    store.subjects = [aino, eeva, kalle, sanni, photo]
    let memory = Memory(
        id: "fixed-memory-id", subjectID: photo.id, authorID: "mummo",
        body: body, mentionedSubjectIDs: [aino.id]
    )
    let first = GuessRoundBuilder.round(for: memory, store: store, memberID: "me")
    let second = GuessRoundBuilder.round(for: memory, store: store, memberID: "me")
    if first?.options.map(\.id) == second?.options.map(\.id), first?.options.count == 4 {
        print("  ok   option order is stable and there are four of them")
    } else {
        failures += 1
        print("  FAIL option order is not stable")
    }
    if let first, first.options.contains(where: { $0.id == first.answer.id }) {
        print("  ok   the answer is among the options")
    } else {
        failures += 1
        print("  FAIL the answer is missing from the options")
    }

    // A round between one real relative and three names nobody has ever said
    // out loud is not a question — the answer is whichever name you recognise.
    print("— decoys —")
    let ghost1 = Subject(kind: .person, title: "Tuntematon Yksi")
    let ghost2 = Subject(kind: .person, title: "Tuntematon Kaksi")
    let ghost3 = Subject(kind: .person, title: "Tuntematon Kolme")
    store.subjects = [aino, eeva, kalle, sanni, ghost1, ghost2, ghost3, photo]
    store.memories = [
        Memory(subjectID: eeva.id, authorID: "mummo", body: "Eevasta kerrottiin."),
        Memory(subjectID: kalle.id, authorID: "mummo", body: "Kallesta kerrottiin."),
        Memory(subjectID: sanni.id, authorID: "mummo", body: "Sannista kerrottiin."),
    ]
    let withDecoys = GuessRoundBuilder.round(for: memory, store: store, memberID: "me")
    let decoyTitles = (withDecoys?.options ?? []).filter { $0.id != aino.id }.map(\.title).sorted()
    if decoyTitles == ["Eeva", "Kalle", "Sanni"] {
        print("  ok   decoys are people the family has talked about")
    } else {
        failures += 1
        print("  FAIL decoys were \(decoyTitles), expected the three with memories")
    }

    print("— waiting count —")
    store.memories = (1 ... 12).map {
        Memory(id: "m-\($0)", subjectID: photo.id, authorID: "mummo",
               body: body, mentionedSubjectIDs: [aino.id])
    }
    let waiting = GuessRoundBuilder.roundsWaiting(store: store, memberID: "me", limit: 9)
    if waiting == 9 {
        print("  ok   the waiting count stops at its cap")
    } else {
        failures += 1
        print("  FAIL waiting count was \(waiting), expected the cap of 9")
    }

    store.guesses = (1 ... 12).map {
        Guess(memoryID: "m-\($0)", memberID: "me", subjectID: nil)
    }
    let afterSkips = GuessRoundBuilder.roundsWaiting(store: store, memberID: "me", limit: 9)
    if afterSkips == 0, GuessRoundBuilder.nextRound(store: store, memberID: "me") == nil {
        print("  ok   \"En muista\" retires a round instead of blocking the queue")
    } else {
        failures += 1
        print("  FAIL a skipped round is still being offered")
    }
}

@main
enum GuessMaskCheck {
    @MainActor
    static func main() {
        maskChecks()
        roundChecks()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
