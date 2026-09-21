// A telling filed under a merged card is filed under the survivor, on every
// phone and not only the one that merged.
//
// Correcting a name onto another card merges the two (`MemoryStore.rename`):
// the corrected card becomes a tombstone with a forwarding address, and the
// tellings that pointed at it are pointed at the survivor. The address
// travels. The re-pointing of another member's telling does not — the server
// writes a telling only for its author, which is rule 3 and stays — and the
// push reply counts it accepted all the same. Measured 21 Sep 2026 over the
// shipping `sync.ts` in SQLite: six rows accepted, the tombstone kept, both of
// the other member's tellings still pointing at the old card.
//
// On every other phone, then, the telling sat under a card no list shows,
// because the queries compare ids as they are stored: on no card, in no
// count, missing from the export's readable page. `MergeChain.follow` moves
// every reference to where the chain already lands, after the file is loaded
// and after every pull. Every way of getting it wrong is silent — a telling
// that is not on a card looks exactly like a telling nobody told.
//
// TWO INSTRUMENTS, AND THEY ARE NOT THE SAME STRENGTH. `MergeChain` is
// EXECUTED: the measured case, chains, a cycle, a survivor not yet pulled or
// since rejected, and the one property everything else rests on — that
// nothing a screen resolves through `subject(id:)` lands anywhere new. The
// places that call it are READ, because `MemoryStore.swift` imports UIKit
// and a command-line build here cannot compile it — the limit
// `sync-fields-check.swift` states too.
//
// Costs nothing: no simulator, no Worker, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/merge-chain-check scripts/merge-chain-check.swift \
//     ios/Kinlore/Services/MergeChain.swift ios/Kinlore/Model/Models.swift \
//     && /tmp/merge-chain-check

import Foundation

@main
struct MergeChainCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func person(_ title: String, into survivor: String? = nil, rejected: Bool = false) -> Subject {
        var card = Subject(kind: .person, title: title)
        card.mergedInto = survivor
        if rejected { card.deletedAt = .now }
        return card
    }

    static func telling(under subjectID: String, naming: [String] = [], teller: String? = nil) -> Memory {
        var memory = Memory(
            subjectID: subjectID, authorID: "toinen", authorName: "Bertta",
            body: "Hän leipoi pullaa joka lauantai.", source: .voice
        )
        memory.mentionedSubjectIDs = naming
        memory.tellerSubjectID = teller
        return memory
    }

    /// One telling filed under `id` and nothing else, run through `follow`:
    /// where a reference to `id` ends up.
    static func landing(of id: String, among cards: [Subject]) -> String {
        var memories = [telling(under: id)]
        var questions: [FollowUpQuestion] = []
        MergeChain.follow(memories: &memories, questions: &questions, subjects: cards)
        return memories[0].subjectID
    }

    static func main() {
        let aino = person("Aino")
        let aina = person("Aina", into: aino.id)
        let photo = Subject(kind: .photo, title: "")

        // MARK: The case that was measured

        print("— another member's tellings, after a merge on somebody else's phone —")
        var memories = [telling(under: aina.id), telling(under: photo.id, naming: [aina.id])]
        var questions = [FollowUpQuestion(subjectID: aina.id, text: "Mitä Aina leipoi?")]
        let before = memories
        let moved = MergeChain.follow(memories: &memories, questions: &questions, subjects: [aino, aina, photo])
        check("the telling filed under the merged card is filed under the survivor",
              memories[0].subjectID == aino.id)
        check("the telling that named the merged card names the survivor",
              memories[1].mentionedSubjectIDs == [aino.id])
        check("a question asked about the merged card is asked about the survivor",
              questions[0].subjectID == aino.id)
        check("and the count says three rows moved", moved == 3, "said \(moved)")
        var restored = memories
        restored[0].subjectID = before[0].subjectID
        restored[1].mentionedSubjectIDs = before[1].mentionedSubjectIDs
        check("nothing else about either telling changed", restored == before)

        memories = [telling(under: photo.id, teller: aina.id)]
        MergeChain.follow(memories: &memories, questions: &questions, subjects: [aino, aina, photo])
        check("the teller follows the card too", memories[0].tellerSubjectID == aino.id)

        memories = [telling(under: photo.id, naming: [aina.id, aino.id]),
                    telling(under: photo.id, naming: [aino.id, photo.id, aina.id])]
        MergeChain.follow(memories: &memories, questions: &questions, subjects: [aino, aina, photo])
        check("two names that are one person are named once",
              memories[0].mentionedSubjectIDs == [aino.id],
              "named \(memories[0].mentionedSubjectIDs.count) times")
        check("and the order of the others is kept",
              memories[1].mentionedSubjectIDs == [aino.id, photo.id])

        memories = [telling(under: photo.id, naming: [photo.id, photo.id])]
        MergeChain.follow(memories: &memories, questions: &questions, subjects: [aino, aina, photo])
        check("a list nothing moved in is left as it is, repeats and all",
              memories[0].mentionedSubjectIDs == [photo.id, photo.id])

        // MARK: What cannot be settled is left alone

        print("\n— what the chain cannot settle —")
        let third = person("Aini")
        let second = person("Aina", into: third.id)
        let first = person("Aine", into: second.id)
        check("a chain is followed to its end",
              landing(of: first.id, among: [first, second, third]) == third.id)

        var loopA = person("A")
        let loopB = person("B", into: loopA.id)
        loopA.mergedInto = loopB.id
        check("a cycle is left as it is, and does not hang",
              landing(of: loopA.id, among: [loopA, loopB]) == loopA.id)

        var line = [person("viimeinen")]
        for step in 0 ..< MergeChain.hops + 1 {
            line.insert(person("askel \(step)", into: line[0].id), at: 0)
        }
        check("a chain longer than the guard is left as it is",
              landing(of: line[0].id, among: line) == line[0].id)

        let waiting = person("Aina", into: "ei-vielä-täällä")
        check("a survivor this phone has not been sent yet is waited for",
              landing(of: waiting.id, among: [waiting]) == waiting.id)

        let refused = person("Aino", rejected: true)
        let intoRefused = person("Aina", into: refused.id)
        check("a survivor the family rejected takes nothing",
              landing(of: intoRefused.id, among: [refused, intoRefused]) == intoRefused.id)

        var both = person("Aina", into: aino.id)
        both.deletedAt = .now
        check("a card rejected as well as merged moves nothing",
              landing(of: both.id, among: [aino, both]) == both.id)

        // MARK: The property the rest rests on

        print("\n— nothing a screen resolves lands anywhere new —")
        let cards = [aino, aina, photo, first, second, third, loopA, loopB, waiting, refused, intoRefused, both] + line
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lookup = { (id: String) in byID[id] }
        let ids = cards.map(\.id) + ["ei-kukaan"]
        var moves = 0
        var drifted: [String] = []
        var unsettled: [String] = []
        for id in ids {
            let landed = landing(of: id, among: cards)
            if landed != id { moves += 1 }
            if MergeChain.resolve(landed, in: lookup)?.id != MergeChain.resolve(id, in: lookup)?.id {
                drifted.append(id)
            }
            if landed != id, MergeChain.resolve(landed, in: lookup)?.id != landed {
                unsettled.append(id)
            }
        }
        check("every one of \(ids.count) references resolves where it resolved before",
              drifted.isEmpty, "\(drifted.count) moved")
        check("and every one that moved sits on a card that resolves to itself",
              unsettled.isEmpty, "\(unsettled.count) did not")
        check("the universe is not trivial: some of it moved", moves > 0)

        memories = cards.map { telling(under: $0.id, naming: [$0.id], teller: $0.id) }
        questions = cards.map { FollowUpQuestion(subjectID: $0.id, text: "?") }
        MergeChain.follow(memories: &memories, questions: &questions, subjects: cards)
        let settled = memories
        let again = MergeChain.follow(memories: &memories, questions: &questions, subjects: cards)
        check("a second pass moves nothing", again == 0 && memories == settled, "moved \(again)")

        memories = [telling(under: aino.id, naming: [photo.id])]
        questions = [FollowUpQuestion(subjectID: aino.id, text: "?")]
        let untouched = (memories, questions)
        let none = MergeChain.follow(memories: &memories, questions: &questions, subjects: [aino, photo])
        check("an archive that never merged anything is not touched",
              none == 0 && memories == untouched.0 && questions == untouched.1)

        // MARK: Where the app calls it

        print("\n— where the store calls it —")
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ios/Kinlore/Data/MemoryStore.swift")
        guard let source = try? String(contentsOf: path, encoding: .utf8) else {
            print("  FAIL MemoryStore.swift could not be read at \(path.path)")
            exit(1)
        }
        let places: [(signature: String, what: String, call: String)] = [
            ("private func load() {", "a loaded file is followed", "followMerges()"),
            ("func applyRemote(_ reply: SyncPullReply) {", "every pull is followed", "followMerges()"),
            ("func rename(subjectID: String, to newTitle: String) {", "a merge made here is followed", "followMerges()"),
            ("private func followMerges() {", "the store moves its rows by MergeChain", "MergeChain.follow("),
            ("func subject(id: String) -> Subject? {", "subject(id:) walks the same chain", "MergeChain.resolve("),
        ]
        for place in places {
            guard let body = body(after: place.signature, in: source) else {
                check(place.what, false, "`\(place.signature)` is no longer in MemoryStore.swift")
                continue
            }
            check(place.what, body.contains(place.call), "no `\(place.call)` in it")
        }
        if let body = body(after: "private func followMerges() {", in: source) {
            check("and queues nothing", !body.contains("dirty"),
                  "the server refuses another member's telling, and every phone draws this itself")
        }

        // MARK: The check against itself

        print("\n— the check against itself —")
        let forgetful = source.replacingOccurrences(of: "        followMerges()\n        advance(seq:", with: "        advance(seq:")
        check("a call taken out of applyRemote is reported",
              body(after: "func applyRemote(_ reply: SyncPullReply) {", in: source)?.contains("followMerges()") == true
                  && body(after: "func applyRemote(_ reply: SyncPullReply) {", in: forgetful)?.contains("followMerges()") == false)

        if failures > 0 {
            print("\n\(failures) failed")
            exit(1)
        }
        print("\nall checks passed")
    }

    /// A function's body, by counting braces from its signature.
    static func body(after signature: String, in source: String) -> String? {
        guard let start = source.range(of: signature) else { return nil }
        var depth = 1
        var index = start.upperBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[start.upperBound..<index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
