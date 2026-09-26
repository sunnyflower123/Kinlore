// The facts on a person's card, on the phone's side of sync and of the file
// (docs/ARCHITECTURE.md §26).
//
// A fact is a list inside one column, sealed whole, and that shape has three
// ways of being wrong that nothing on a screen shows:
//
//   1. **A kind this build does not know must survive it.** `PersonFact.kind`
//      is a `String` for rule 10's reason — a `String` enum makes every value
//      a later build adds a decoding error — and a fact of an unknown kind has
//      to come out of the decoder and go back into the encoder as it came, or
//      the first phone to edit anything on the card writes the family's list
//      back without it.
//   2. **The wire carries ciphertext only** (PLAN §10 lever 3). A name, a
//      trade and a note are words; the server compares nothing in them, and
//      must be able to read nothing in them.
//   3. **Two phones' lists are joined, not chosen between.** The server keeps
//      the newer list whole, because a sealed list is all it can see. So a
//      phone that pulls a list the server chose over its own has to put its
//      own facts back — and a fact it took off the card has to stay off,
//      whatever copies arrive and whatever their clocks said.
//   4. **Three roads to a push on every sync, each silent.** A server row
//      with no list must mark nothing to push, or a Worker without the
//      column is pushed at for ever; the moment a joined list goes up under
//      must be past the server's and not merely this phone's *now*, or a
//      phone whose clock runs behind loses every push; and the largest list
//      this phone will write must cross under the Worker's cap, or a list it
//      refused stands on the server for ever while the phone pushes it again.
//
// Costs nothing: no simulator, no Worker, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/facts-check scripts/facts-check.swift \
//     ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
//     ios/Kinlore/Model/Models.swift && /tmp/facts-check
import CryptoKit
import Foundation

@main
struct FactsCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static let then = Date(timeIntervalSince1970: 1_780_000_000)
    static let later = Date(timeIntervalSince1970: 1_780_086_400)
    static let thirties = DateHint(
        start: Date(timeIntervalSince1970: -1_262_304_000),
        end: Date(timeIntervalSince1970: -946_771_201),
        precision: .decade
    )

    static func main() {
        print("— the file and the kinds —")
        kinds()
        file()
        print("\n— the wire —")
        wire()
        print("\n— two phones' lists —")
        join()
        print("\n— the ceilings —")
        limits()

        if failures == 0 {
            print("\nall checks passed")
        } else {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
    }

    static func kinds() {
        let ids = PersonFactKind.known.map(\.id)
        check("the table's kinds are distinct", Set(ids).count == ids.count)
        check(
            "every known kind has a word for the sheet and one for the card",
            PersonFactKind.known.allSatisfy { !$0.label.isEmpty && !$0.word.isEmpty && !$0.asks.isEmpty }
        )
        check("a stored word this build knows finds its row", PersonFactKind.of("birth").id == "birth")
        check("one it does not know is the unknown row", PersonFactKind.of("marriage").id == PersonFactKind.unknown.id)
        check(
            "and the unknown row shows every part a fact might carry",
            Set(PersonFactKind.unknown.asks) == [.text, .date, .place]
        )
        check(
            "known kinds sort in the table's order and unknown ones after them",
            PersonFactKind.rank("birth") < PersonFactKind.rank("note")
                && PersonFactKind.rank("note") < PersonFactKind.rank("marriage")
        )

        let person = Subject(
            kind: .person, title: "Eeva",
            facts: [
                PersonFact(id: "note", kind: "note", text: "n", updatedAt: then),
                PersonFact(id: "gone", kind: "birth", date: thirties, updatedAt: then, deletedAt: later),
                PersonFact(id: "odd", kind: "marriage", text: "m", updatedAt: then),
                PersonFact(id: "birth", kind: "birth", date: thirties, updatedAt: then),
            ],
            factsSetAt: later
        )
        check(
            "the card's order: birth, then the note, then the kind it has no word for, and the removed one not at all",
            person.liveFacts.map(\.id) == ["birth", "note", "odd"],
            "\(person.liveFacts.map(\.id))"
        )
    }

    static func file() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // A fact of a kind this build has no word for, with a part it does
        // know, through the file and back.
        let odd = PersonFact(id: "odd", kind: "marriage", text: "Sulkavalla", date: thirties, placeSubjectID: "place", updatedAt: then)
        let person = Subject(kind: .person, title: "Eeva", facts: [odd], factsSetAt: later)
        if let data = try? encoder.encode(person), let back = try? decoder.decode(Subject.self, from: data) {
            check("a fact of an unknown kind comes back from the file as it went", back.facts == [odd])
            check("and so does the list's moment", back.factsSetAt == later)

            // The same file written before facts existed: the two keys taken
            // out, which is what an older build wrote. Rule 10.
            if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json.removeValue(forKey: "facts")
                json.removeValue(forKey: "factsSetAt")
                let old = try? JSONSerialization.data(withJSONObject: json)
                let read = old.flatMap { try? decoder.decode(Subject.self, from: $0) }
                check("a person written before facts existed still loads, with none", read != nil && read?.facts == nil)
            } else {
                check("the encoded person is a JSON object", false)
            }
        } else {
            check("a person with facts goes through the file", false)
        }

        // Row by row: a row without an id is left out and the rest kept; a
        // row missing its moment is read as older than anything; a date
        // with a precision this build has no case for is read as no date,
        // and the fact stays.
        let rows = """
        [
          {"id":"a","kind":"note","text":"kept","updatedAt":1780000000},
          {"kind":"note","text":"no id"},
          {"id":"b","kind":"occupation","text":"old"},
          {"id":"c","kind":"birth","date":{"start":-1262304000,"end":-946771201,"precision":"century"},"updatedAt":1780000000},
          {"id":"d","kind":"residence","placeSubjectID":"p","updatedAt":1780000000,"extra":"a field from a later build"}
        ]
        """
        let read = PersonFact.decodedList(rows)
        check("a list read row by row keeps every row with an id", read?.map(\.id) == ["a", "b", "c", "d"], "\(String(describing: read?.map(\.id)))")
        check("a row without its moment is older than anything", read?[1].updatedAt == Date(timeIntervalSince1970: 0))
        check("a date of a precision this build has no case for is no date, and the fact stays", read?[2].date == nil && read?[2].kind == "birth")
        check("a field from a later build is passed over, not fatal", read?[3].placeSubjectID == "p")
        check("a string that is not a list is nil, not an empty list", PersonFact.decodedList("not json") == nil)
        check("and so is a list of no rows at all", PersonFact.decodedList("[]") == [])
    }

    static func wire() {
        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)
        let facts = [
            PersonFact(id: "birth", kind: "birth", date: thirties, placeSubjectID: "place", updatedAt: then),
            PersonFact(id: "trade", kind: "occupation", text: "Kansakoulunopettaja", updatedAt: then),
            PersonFact(id: "name", kind: "other_name", text: "o.s. Virtanen", updatedAt: then),
            PersonFact(id: "odd", kind: "marriage", text: "Sulkava", updatedAt: then),
        ]
        let person = Subject(id: "eeva", kind: .person, title: "Eeva", facts: facts, factsSetAt: later)

        let payload = SyncPayload(subjects: [person.dto])
        let sealed = payload.sealed(with: key)
        let wire = sealed.subjects[0]
        check("the list crosses with its moment", wire.facts != nil && wire.facts_set_at == later.timeIntervalSince1970)
        let words = ["Kansakoulunopettaja", "Virtanen", "Sulkava", "birth", "occupation", "marriage", "place"]
        check(
            "and the server can read none of the words, the kinds or the place in it",
            words.allSatisfy { !(wire.facts ?? "").contains($0) }
        )
        check("nor is it the plaintext under another name", wire.facts != person.dto.facts)

        // Back, as a pull reply opened with the same key.
        let reply = SyncPullReply(seq: 1, more: false, subjects: [wire], memories: [], questions: [])
        let opened = reply.opened(with: key).subjects[0]
        let back = Subject(dto: opened)
        check("opened with the family's key, every fact is what was sent, the unknown kind included", back?.facts == facts)
        check("and the moment too", back?.factsSetAt == later)

        // Under another key the list cannot be opened, and that is not an
        // empty list: it is no opinion.
        let wrong = Subject(dto: reply.opened(with: other).subjects[0])
        check("under another key the list is nil, not empty", wrong?.facts == nil)
        let local = Subject(id: "eeva", kind: .person, title: "Eeva", facts: facts, factsSetAt: then)
        if let wrong {
            let kept = wrong.withFacts(from: local)
            check("and a list that could not be opened takes nothing away", kept.row.facts == facts && kept.needsPush == false)
        }

        // Both or neither on the way out.
        var half = person
        half.factsSetAt = nil
        check("a list without its moment is no opinion on the wire", half.dto.facts == nil && half.dto.facts_set_at == nil)
        check("a person with no facts sends none", Subject(kind: .person, title: "x").dto.facts == nil)

        // The same list is the same bytes.
        check("the same list encodes to the same bytes", PersonFact.encodedList(facts) == PersonFact.encodedList(facts))
    }

    static func join() {
        let a = PersonFact(id: "a", kind: "birth", date: thirties, updatedAt: then)
        let b = PersonFact(id: "b", kind: "occupation", text: "opettaja", updatedAt: then)
        let server = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a], factsSetAt: then)

        // 1. A row that says nothing takes nothing away.
        var silent = server
        silent.facts = nil
        silent.factsSetAt = nil
        let local = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a, b], factsSetAt: later)
        let kept = silent.withFacts(from: local)
        check("a row that says nothing about facts leaves this phone's alone", kept.row.facts == [a, b] && kept.row.factsSetAt == later)
        check("and marks nothing to push — a Worker without the column is not pushed at on every sync", !kept.needsPush)

        // 2. The same list: nothing to push.
        let same = server.withFacts(from: Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a], factsSetAt: then))
        check("the same list is taken as it came, with the server's moment", same.row.facts == [a] && same.row.factsSetAt == then && !same.needsPush)

        // 3. This phone wrote one the server does not have: both, and up it goes.
        let both = server.withFacts(from: local)
        check("a fact only this phone holds is put back beside the server's", Set(both.row.facts ?? []) == [a, b])
        check("and the row goes up again", both.needsPush)
        check("under a moment later than the server's", (both.row.factsSetAt ?? .distantPast) > then)

        // 3b. A phone whose clock is ten minutes behind the server's: the
        //     moment it pushes under is past the server's all the same, so
        //     one push lands and the next pull finds nothing left to push.
        let serverNow = Date.now
        let behind = serverNow.addingTimeInterval(-600)
        let onServer = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a], factsSetAt: serverNow)
        let slow = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a, b], factsSetAt: behind.addingTimeInterval(-60))
        let first = onServer.withFacts(from: slow, now: behind)
        check("a phone ten minutes behind pushes under a moment past the server's, not its own now", first.needsPush && (first.row.factsSetAt ?? .distantPast) > serverNow)
        // The server keeps the newer list whole and answers with it.
        let stored = (first.row.factsSetAt ?? .distantPast) > serverNow ? first.row : onServer
        let second = stored.withFacts(from: first.row, now: behind.addingTimeInterval(30))
        check("and the next pull finds nothing to push: one push was enough", !second.needsPush && Set(second.row.facts ?? []) == [a, b])

        // 4. The server's newer copy of a fact wins over this phone's older one.
        var aNewer = a
        aNewer.text = "newer"
        aNewer.updatedAt = later
        let newer = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [aNewer], factsSetAt: later)
        let took = newer.withFacts(from: Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a], factsSetAt: then))
        check("the server's newer copy of a fact replaces this phone's older one", took.row.facts == [aNewer] && !took.needsPush)

        // 5. A removal here beats the server's older copy, and travels.
        var gone = a
        gone.deletedAt = later
        gone.updatedAt = later
        let removed = server.withFacts(from: Subject(id: "eeva", kind: .person, title: "Eeva", facts: [gone], factsSetAt: later))
        check("a fact taken off here stays off when an older copy arrives", removed.row.facts == [gone] && removed.row.liveFacts.isEmpty)
        check("and the removal goes up", removed.needsPush)

        // 5b. A removal stands over a live copy written after it too, from
        //     either side: a fact somebody took off is more often wrong than
        //     a change to it was right, and the two clocks are not a tiebreak
        //     worth the fact's return (rule 4).
        var stale = a
        stale.deletedAt = then
        stale.updatedAt = then
        var revived = a
        revived.text = "changed on a phone whose clock ran ahead"
        revived.updatedAt = later
        check(
            "a removal stands over a live copy written after it, from either side",
            PersonFact.joined([stale], with: [revived]) == [stale] && PersonFact.joined([revived], with: [stale]) == [stale]
        )
        var taken = PersonFact(id: "t", kind: "note", text: "words", date: thirties, placeSubjectID: "p", updatedAt: then)
        taken.remove(at: later)
        check(
            "a fact taken off keeps its id and kind and none of its words, time or place",
            taken.id == "t" && taken.kind == "note" && taken.text == nil && taken.date == nil
                && taken.placeSubjectID == nil && taken.deletedAt == later && taken.updatedAt == later
        )

        // 6. Two phones wrote two facts: both survive on both.
        let phoneA = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [a], factsSetAt: then)
        let phoneB = Subject(id: "eeva", kind: .person, title: "Eeva", facts: [b], factsSetAt: later)
        let onA = phoneB.withFacts(from: phoneA)
        let onB = phoneA.withFacts(from: phoneB)
        check("two phones' facts both survive, whichever list the server chose", Set(onA.row.facts ?? []) == [a, b] && Set(onB.row.facts ?? []) == [a, b])

        // 7. On the same moment this phone's copy stands — the one that may
        //    carry a field the other build wrote back without.
        var richer = a
        richer.text = "a field the other build could not read"
        let tie = server.withFacts(from: Subject(id: "eeva", kind: .person, title: "Eeva", facts: [richer], factsSetAt: then))
        check("on the same moment this phone's copy stands", tie.row.facts == [richer] && tie.needsPush)

        // 8. The join itself, on lists rather than rows.
        let joined = PersonFact.joined([a, b], with: [aNewer])
        check("the join keeps this phone's order and takes the newer copy", joined == [aNewer, b])
        check("and is the same from either side", Set(PersonFact.joined([aNewer], with: [a, b])) == Set(joined))
    }

    static func limits() {
        let key = SymmetricKey(size: .bits256)
        let long = "  " + String(repeating: "a", count: 1000) + " "
        check("the words are trimmed and cut at the limit", PersonFact.cut(long)?.count == PersonFact.textLimit)
        check("and words that are only space are nil", PersonFact.cut("  \n ") == nil)
        check("the limit is a sentence or two, not a word", PersonFact.textLimit >= 200)

        // The largest list this phone will write: facts of the longest words
        // in the widest characters JSON leaves as they are — four bytes each
        // — with every part filled, added until `fits` says no. The last
        // list it said yes to, sealed as the wire seals it, has to be under
        // the Worker's cap on the sealed column with room to spare, because
        // sealing grows it and the cap is measured after.
        let widest = String(repeating: "\u{1F600}", count: PersonFact.textLimit)
        var list: [PersonFact] = []
        var last: [PersonFact] = []
        while PersonFact.fits(list) {
            last = list
            list.append(PersonFact(kind: "occupation", text: widest, date: thirties, placeSubjectID: UUID().uuidString))
        }
        check("the list has a ceiling", !last.isEmpty && !PersonFact.fits(list))
        let sealed = PersonFact.encodedList(last).flatMap { FamilyCrypto.seal($0, with: key) }
        let bytes = sealed?.utf8.count ?? .max
        check("the largest list this phone will write crosses under the Worker's 65 536", bytes < 65_536, "\(bytes) bytes sealed, \(last.count) facts")
        check("and well under it: a refused list would be pushed for ever", bytes <= 55_000, "\(bytes) bytes")
        check("and the ceiling is not a low one: twenty facts of the longest words in the widest letters", last.count >= 20, "\(last.count) facts")
        check("a list of ordinary facts fits with room: a hundred trades of thirty letters", PersonFact.fits((0 ..< 100).map { _ in PersonFact(kind: "occupation", text: String(repeating: "k", count: 30), date: thirties) }))
        check("an empty list fits", PersonFact.fits([]))
        // A fact placed in a list: in place of its own copy, or at the end.
        let a = PersonFact(id: "a", kind: "note", text: "one", updatedAt: then)
        var a2 = a
        a2.text = "two"
        let b = PersonFact(id: "b", kind: "note", text: "b", updatedAt: then)
        check("a fact placed in a list replaces its own copy and joins the end otherwise", PersonFact.placing(a2, in: [a, b]) == [a2, b] && PersonFact.placing(b, in: [a]) == [a, b])
    }
}
