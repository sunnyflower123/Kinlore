// The story on a card, on the phone's side (ARCHITECTURE §27).
//
// Four things decide what a family reads on a card, and none of them shows
// in a picture: when the model is asked at all, which is the cost; what a
// person's correction of the story is worth against the model's next one,
// which is rule 4 wearing the story's clothes; what two phones settle on
// when both have a story, which is the sync rule `sync.ts` cannot apply
// because it cannot read a sealed story; and whether a story written by one
// build is a story to another, which is rule 10 in both directions.
//
//   1. **One telling, one model call.** `StoryPlan` asks for a story only
//      when the set of live tellings differs from the set the story was
//      composed from, clears it when they are all gone, and is silent
//      otherwise. Taken back, waiting for transcription and blank do not
//      count as tellings.
//   2. **A person's story is never written over.** Told after an edit, a
//      telling becomes a proposal under the story; accepted, it is a new
//      paragraph and the story stays the person's; dismissed, it is not
//      asked about again. An edit counts everything then live as read,
//      except what is waiting in a proposal. And a telling taken back from
//      under a person's story is asked about, not acted on: the plan is
//      silent, the story knows which telling is gone, kept it stops asking
//      and composed again it is cleared.
//   3. **The pull rule.** A row that says nothing keeps this phone's story.
//      An edited story on this phone beats a composed one from the server
//      whatever the moments say, and is pushed again under a later moment
//      so the family settles on it; a composed one here loses to an edited
//      one there. Two of the same kind: the newer moment, whole, and the
//      same story coming back adopts the server's moment so nothing is
//      pushed twice.
//   4. **The wire.** The story crosses as JSON with sorted keys and seconds,
//      inside the seal; a story with keys this build does not know still
//      reads; one that is not a story reads as none, and its moment goes
//      with it; a story under `byteLimit` fits under the Worker's cap once
//      sealed; the DTO carries both or neither.
//   5. **What the model is told.** The date the measured prompt saw, the
//      teller's byline or nothing, only the names the family has confirmed
//      — an unconfirmed name, and a relationship, is nowhere in the bytes
//      the phone sends (rule 4) — and the stub's sentence per telling in the
//      language asked for, which is the composing phone's: the tellings
//      cross verbatim in whatever language they were told, and a story
//      reading every telling is not composed again for a phone in another.
//
// Costs nothing: no simulator, no Worker, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/story-check scripts/story-check.swift \
//     ios/Kinlore/Services/StoryComposer.swift ios/Kinlore/Model/Models.swift \
//     ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Services/FamilyCrypto.swift \
//     && /tmp/story-check

import CryptoKit
import Foundation

@main
struct StoryCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static let t0 = Date(timeIntervalSince1970: 1_780_000_000)
    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    static func telling(_ id: String, _ body: String = "Sanottu.", at seconds: TimeInterval, by name: String = "Mummo",
                        deleted: Bool = false, audioOnly: Bool = false) -> Memory {
        Memory(
            id: id, subjectID: "card", authorID: "member-\(name)", authorName: name,
            body: audioOnly ? "" : body,
            audioR2Key: audioOnly ? "family/\(id).m4a" : nil,
            source: .voice, createdAt: at(seconds),
            deletedAt: deleted ? at(seconds + 1) : nil
        )
    }

    static func main() async {
        let a = telling("a", "Ensin kerrottu.", at: 0)
        let b = telling("b", "Sitten kerrottu.", at: 100)
        let c = telling("c", "Viimeksi kerrottu.", at: 200, by: "Pekka")
        let gone = telling("gone", at: 50, deleted: true)
        let waiting = telling("waiting", at: 60, audioOnly: true)
        let blank = telling("blank", "   ", at: 70)

        print("— which tellings a story is made of —")
        let live = StoryPlan.live([c, gone, a, waiting, blank, b])
        check("taken back, waiting and blank are not tellings", live.map(\.id) == ["a", "b", "c"], "\(live.map(\.id))")

        print("— one telling, one model call —")
        check("nothing told, nothing asked", StoryPlan.plan(story: nil, memories: [gone, waiting]) == .nothing)
        check("told and no story: compose, oldest first", StoryPlan.plan(story: nil, memories: [b, a]) == .compose([a, b]))
        let composed = Story.composed("Mummo kertoo.", from: [a, b], at: at(300))
        check("a story of exactly the live tellings asks for nothing", StoryPlan.plan(story: composed, memories: [a, b, gone]) == .nothing)
        check("one more telling composes again, all of them, oldest first", StoryPlan.plan(story: composed, memories: [c, a, b]) == .compose([a, b, c]))
        check("one taken back composes again from what is left", StoryPlan.plan(story: composed, memories: [a, telling("b", at: 100, deleted: true)]) == .compose([a]))
        check("every telling taken back clears the story", StoryPlan.plan(story: composed, memories: [gone]) == .clear)
        let cleared = Story(text: "", composedFrom: [], composedAt: at(400))
        check("a cleared story is no story: told again, compose", StoryPlan.plan(story: cleared, memories: [c]) == .compose([c]))
        check("and nothing told, nothing asked", StoryPlan.plan(story: cleared, memories: []) == .nothing)
        check("a telling still waiting for its words does not compose", StoryPlan.plan(story: composed, memories: [a, b, waiting]) == .nothing)

        print("— a person's story is never written over —")
        let edited = composed.edited(to: "Mummo kertoo, ja minä korjasin.", live: [a, b], now: at(500))
        check("an edit is marked", edited.isEdited && edited.text == "Mummo kertoo, ja minä korjasin.")
        check("and with nothing new it asks for nothing", StoryPlan.plan(story: edited, memories: [a, b]) == .nothing)
        check(
            "a telling after the edit is proposed, to the story, not composed over it",
            StoryPlan.plan(story: edited, memories: [a, b, c]) == .propose([c], toStory: edited.text)
        )
        let proposed = edited.proposing("Pekka kertoo, että viimeksi kerrottu.", from: [c], at: at(600))
        check("the proposal is held under the story", proposed.proposal?.text == "Pekka kertoo, että viimeksi kerrottu." && proposed.proposal?.from == ["c"])
        check("and the story's words are untouched", proposed.text == edited.text && proposed.isEdited)
        check("a proposal for exactly the new tellings asks for nothing", StoryPlan.plan(story: proposed, memories: [a, b, c]) == .nothing)
        let d = telling("d", "Vielä yksi.", at: 700, by: "Aino")
        check("another telling proposes again, both new ones", StoryPlan.plan(story: proposed, memories: [a, b, c, d]) == .propose([c, d], toStory: edited.text))
        check("the proposal's telling taken back drops the proposal, without a call", StoryPlan.plan(story: proposed, memories: [a, b]) == .dropProposal)
        let accepted = proposed.accepting(now: at(800))
        check(
            "accepted, it is the story's last paragraph and the story stays the person's",
            accepted.text == edited.text + "\n\nPekka kertoo, että viimeksi kerrottu." && accepted.editedAt == at(800)
                && accepted.proposal == nil && Set(accepted.composedFrom) == ["a", "b", "c"]
        )
        check("and nothing more is asked", StoryPlan.plan(story: accepted, memories: [a, b, c]) == .nothing)
        let dismissed = proposed.dismissing()
        check(
            "dismissed, it is gone and not asked about again",
            dismissed.text == edited.text && dismissed.proposal == nil && Set(dismissed.composedFrom) == ["a", "b", "c"]
                && StoryPlan.plan(story: dismissed, memories: [a, b, c]) == .nothing
        )
        let written = Story(text: "Kirjoitin itse.", composedFrom: [a, b].map(\.id), editedAt: at(900))
        check("a story written by hand over the tellings read asks for nothing", StoryPlan.plan(story: written, memories: [a, b]) == .nothing)
        check("and the next telling is proposed to it", StoryPlan.plan(story: written, memories: [a, b, c]) == .propose([c], toStory: written.text))
        let overCleared = cleared.edited(to: "Kirjoitin tyhjän tilalle.", live: [a, b], now: at(950))
        check("written over a cleared story, what was live counts as read", Set(overCleared.composedFrom) == ["a", "b"] && StoryPlan.plan(story: overCleared, memories: [a, b]) == .nothing)
        let editedUnderProposal = proposed.edited(to: "Korjattu taas.", live: [a, b, c], now: at(960))
        check(
            "an edit under a pending proposal leaves the proposal pending",
            editedUnderProposal.proposal == proposed.proposal && !editedUnderProposal.composedFrom.contains("c")
                && StoryPlan.plan(story: editedUnderProposal, memories: [a, b, c]) == .nothing
        )

        print("— a telling taken back under a person's story —")
        // Under a composed story the plan composes again from what is left
        // (above). Under a person's story nothing is asked by itself: the
        // card says which tellings the story reads are gone, and a person
        // keeps the story or has it composed again.
        let bGone = telling("b", at: 100, deleted: true)
        check("nothing is asked by itself", StoryPlan.plan(story: edited, memories: [a, bGone]) == .nothing)
        check("but the story knows which telling it reads is gone", edited.takenBack(live: StoryPlan.live([a, bGone])) == ["b"])
        check("and none while every telling is there", edited.takenBack(live: [a, b]).isEmpty)
        let kept = edited.keeping(live: [a])
        check(
            "kept, the words are untouched, it stays the person's, and the gone telling is no longer counted",
            kept.text == edited.text && kept.isEdited && kept.composedFrom == ["a"] && kept.takenBack(live: [a]).isEmpty
        )
        check("and the next telling is still proposed to it, not composed over it", StoryPlan.plan(story: kept, memories: [a, c]) == .propose([c], toStory: edited.text))
        check("composed again is cleared, and a cleared story composes from what is left", StoryPlan.plan(story: cleared, memories: [a]) == .compose([a]))
        check("every telling taken back under a person's story: the story stays, and knows", StoryPlan.plan(story: edited, memories: []) == .nothing && edited.takenBack(live: []) == ["a", "b"])
        check(
            "a proposal's telling taken back is the proposal's to drop, not the story's to report",
            proposed.takenBack(live: [a, b]).isEmpty && StoryPlan.plan(story: proposed, memories: [a, b]) == .dropProposal
        )

        print("— the pull rule —")
        var mine = Subject(id: "card", kind: .photo, title: "Laituri")
        mine.story = composed
        mine.storySetAt = at(300)
        var pulled = mine
        pulled.story = nil
        pulled.storySetAt = nil
        var merged = pulled.withStory(from: mine, now: at(1000))
        check("a row with no word keeps this phone's, and pushes nothing", merged.row.story == composed && merged.row.storySetAt == at(300) && !merged.needsPush)
        var none = mine
        none.story = nil
        none.storySetAt = nil
        merged = mine.withStory(from: none, now: at(1000))
        check("a phone with no story takes the pulled one", merged.row.story == composed && merged.row.storySetAt == at(300) && !merged.needsPush)
        var theirs = mine
        theirs.story = Story.composed("Toisen puhelimen kokoama.", from: [a, b], at: at(350))
        theirs.storySetAt = at(350)
        merged = theirs.withStory(from: mine, now: at(1000))
        check("two composed stories: the newer wins whole, and nothing is pushed", merged.row.story == theirs.story && merged.row.storySetAt == at(350) && !merged.needsPush)
        merged = mine.withStory(from: theirs, now: at(1000))
        check(
            "and this phone's newer one is kept, put after the server's moment, and pushed",
            merged.row.story == theirs.story && merged.row.storySetAt! > at(300) && merged.row.storySetAt! >= at(1000) && merged.needsPush
        )
        var edit = mine
        edit.story = edited
        edit.storySetAt = at(500)
        var laterComposed = mine
        laterComposed.story = Story.composed("Kone kokosi uudestaan.", from: [a, b, c], at: at(700))
        laterComposed.storySetAt = at(700)
        merged = laterComposed.withStory(from: edit, now: at(1000))
        check(
            "a person's story beats a newer composed one, and is pushed under a moment past it",
            merged.row.story == edited && merged.row.storySetAt! > at(700) && merged.needsPush
        )
        merged = edit.withStory(from: laterComposed, now: at(1000))
        check("and a composed story here loses to an edited one there, older or not", merged.row.story == edited && merged.row.storySetAt == at(500) && !merged.needsPush)
        var otherEdit = mine
        otherEdit.story = written
        otherEdit.storySetAt = at(900)
        merged = otherEdit.withStory(from: edit, now: at(1000))
        check("two edited stories: the family's last word wins", merged.row.story == written && merged.row.storySetAt == at(900) && !merged.needsPush)
        merged = edit.withStory(from: otherEdit, now: at(1000))
        check("from either side", merged.row.story == written && merged.row.storySetAt.map { $0 > at(900) } == true && merged.needsPush)
        var echo = mine
        echo.storySetAt = at(310)
        merged = echo.withStory(from: mine, now: at(1000))
        check("the same story coming back adopts the server's moment and pushes nothing", merged.row.story == composed && merged.row.storySetAt == at(310) && !merged.needsPush)
        var clock = mine
        clock.storySetAt = at(5000)
        var older = mine
        older.story = theirs.story
        older.storySetAt = at(350)
        merged = clock.withStory(from: older, now: at(1000))
        check("a server moment ahead of this phone's clock still wins when newer", merged.row.story == composed && !merged.needsPush)
        merged = older.withStory(from: clock, now: at(1000))
        check(
            "and a story this phone stamped in the future is kept, but brought back to now for the push",
            merged.row.story == composed && merged.row.storySetAt == at(1000) && merged.needsPush
        )

        print("— the wire —")
        guard let encoded = Story.encoded(proposed) else {
            check("a story encodes", false)
            exit(1)
        }
        check("the JSON has its keys in order, so two phones write the same bytes", encoded.hasPrefix("{\"composedAt\":") && encoded.contains("\"proposal\":{\"at\":"))
        check("moments cross as whole milliseconds", encoded.contains("\"composedAt\":1780000300000,"))
        let stamped = Story(text: "Nyt.", composedAt: Date(timeIntervalSince1970: 1_790_449_052.7137442))
        check(
            "a story stamped between two milliseconds is the same story after the trip",
            Story.encoded(stamped).flatMap(Story.decoded) == stamped
        )
        let justNow = Story(text: "Nyt.")
        check("and so is one stamped now, whatever the clock's last bits", Story.encoded(justNow).flatMap(Story.decoded) == justNow)
        check("and it reads back as the same story", Story.decoded(encoded) == proposed)
        check("a second encoding is the same bytes", Story.encoded(proposed) == encoded)
        let newer = """
        {"composedAt":1780000300000,"composedFrom":["a"],"text":"Uudempi.","tone":"warm","proposal":{"at":1000,"from":["b"],"text":"Lisää.","confidence":0.4}}
        """
        check("a story from a newer build, with keys this one has not heard of, still reads", Story.decoded(newer)?.text == "Uudempi." && Story.decoded(newer)?.proposal?.text == "Lisää.")
        check("a story without a proposal key reads", Story.decoded("{\"composedAt\":1,\"composedFrom\":[],\"text\":\"Vain teksti.\"}")?.text == "Vain teksti.")
        check("a proposal this build cannot read is dropped, not the story", Story.decoded("{\"text\":\"Teksti.\",\"proposal\":\"not an object\"}")?.text == "Teksti.")
        check("what is not a story reads as none", Story.decoded("Mummo kertoo.") == nil && Story.decoded("[1,2]") == nil && Story.decoded("") == nil)
        let key = SymmetricKey(size: .bits256)
        let big = Story(text: String(repeating: "ä", count: Story.byteLimit / 2 - 200), composedFrom: (0 ..< 40).map { "id-\($0)" })
        let bigBytes = Story.encoded(big)!.utf8.count
        check("a story at the limit fits", big.fits && bigBytes <= Story.byteLimit && bigBytes > Story.byteLimit - 2000, "\(bigBytes) bytes")
        let sealedBig = FamilyCrypto.seal(Story.encoded(big)!, with: key)!
        check("and sealed it is under the Worker's cap of 131 072", sealedBig.count <= 131_072, "\(sealedBig.count) characters")
        var tooBig = big
        tooBig.text += String(repeating: "ä", count: 1200)
        check("one past it does not fit", !tooBig.fits)

        var dto = mine.dto
        check("the DTO carries the story sealed-ready and its moment", dto.story == Story.encoded(composed) && dto.story_set_at == at(300).timeIntervalSince1970)
        var noMoment = mine
        noMoment.storySetAt = nil
        dto = noMoment.dto
        check("a story with no moment sends neither", dto.story == nil && dto.story_set_at == nil)
        var noStory = mine
        noStory.story = nil
        dto = noStory.dto
        check("a moment with no story sends neither", dto.story == nil && dto.story_set_at == nil)
        var junk = mine.dto
        junk.story = "not a story"
        let read = Subject(dto: junk)
        check("a row whose story will not read has no story and no moment", read?.story == nil && read?.storySetAt == nil)
        let roundTrip = Subject(dto: mine.dto)
        check("and one that will reads back whole", roundTrip?.story == composed && roundTrip?.storySetAt == at(300))

        print("— what the model is told —")
        var card = Subject(id: "card", kind: .photo, title: "Mökin laituri")
        card.dateHint = DateHint(start: at(0), end: nil, precision: .decade)
        let aino = Subject(id: "aino", kind: .person, title: "Aino")
        let eevertti = Subject(id: "eevertti", kind: .person, title: "Eevertti", confirmed: false)
        let request = StoryRequest(
            subject: card, memories: [a, c], tellerNames: ["a": "Mummo"], mentions: [aino, eevertti],
            lang: "fi", zone: TimeZone(identifier: "Europe/Helsinki")!
        )
        check("the kind and the title", request.kind == "photo" && request.title == "Mökin laituri")
        check("the date at its precision", request.date == card.dateHint?.displayText && request.date != nil)
        check("only a confirmed name crosses, as a name and a kind", request.mentions == [StoryRequest.Mention(name: "Aino", kind: "person")], "\(request.mentions)")
        let bytes = try! JSONEncoder().encode(request)
        let json = String(decoding: bytes, as: UTF8.self)
        check("an unconfirmed name is nowhere in what the phone sends, nor any flag", !json.contains("Eevertti") && !json.contains("confirmed"))
        let fields = ((try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]).map { Set($0.keys) } ?? []
        check("and nothing else is: the request is the card, its names and its tellings, with no field for a relationship", fields == ["lang", "kind", "title", "date", "mentions", "memories"], "\(fields.sorted())")
        let nameFields = (((try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any])?["mentions"] as? [[String: Any]])?.first.map { Set($0.keys) } ?? []
        check("a name crosses with its kind and nothing more", nameFields == ["name", "kind"], "\(nameFields.sorted())")
        check("the byline, or nothing for a teller who asked not to be named", request.memories.map(\.teller) == ["Mummo", ""])
        check("the date the Finnish prompt was measured with", request.memories.first?.told == "28.5.2026", request.memories.first?.told ?? "")
        check("the source as the prompt's word", request.memories.first?.source == "voice")
        check("no story so far unless asked for a continuation", request.soFar == nil)
        let english = StoryRequest(subject: card, memories: [a], tellerNames: [:], mentions: [], lang: "en", soFar: "So far.", zone: TimeZone(identifier: "Europe/Helsinki")!)
        check("and the English prompt's date", english.memories.first?.told == "2026-05-28" && english.soFar == "So far.")
        var undated = card
        undated.dateHint = DateHint(start: nil, end: nil, precision: .unknown)
        check("an unknown date is no date", StoryRequest(subject: undated, memories: [a], tellerNames: [:], mentions: [], lang: "fi").date == nil)
        let untitled = Subject(id: "photo", kind: .photo, title: "")
        check("an untitled card sends no title, not the fallback word", StoryRequest(subject: untitled, memories: [a], tellerNames: [:], mentions: [], lang: "fi").title == nil)

        print("— which language —")
        // With several tellers there is no one speaker to follow: the frame
        // is the composing phone's, the tellings cross as they were told,
        // and a story that reads every telling is not composed again for a
        // phone in another language.
        let mixed = [telling("fi", "Mummo kertoi laiturista.", at: 0), telling("en", "We rowed to the island.", at: 100, by: "Anna")]
        let frame = StoryRequest(subject: card, memories: mixed, tellerNames: ["fi": "Mummo", "en": "Anna"], mentions: [], lang: "en")
        check("the tellings cross verbatim, each in the language it was told in", frame.memories.map(\.text) == ["Mummo kertoi laiturista.", "We rowed to the island."])
        let framed = (try? await StubStoryComposer().compose(frame)) ?? ""
        check("and the frame is the composing phone's, whatever the tellers spoke", frame.lang == "en" && framed.hasPrefix("Mummo says that mummo kertoi laiturista."), framed)
        let composedInFinnish = Story.composed("Mummo kertoo, että hän kertoi laiturista.", from: mixed, at: at(300))
        check("a phone in another language finds a story reading every telling and asks for nothing", StoryPlan.plan(story: composedInFinnish, memories: mixed) == .nothing)

        print("— the stub, which every UI test composes with —")
        do {
            let fi = try await StubStoryComposer().compose(request)
            check("a sentence per telling, in the teller's word", fi == "Mummo kertoo, että ensin kerrottu.\n\nKertoja kertoo, että viimeksi kerrottu.", fi)
            let en = try await StubStoryComposer().compose(english)
            check("and in English when asked in English", en == "Teller says that ensin kerrottu.", en)
            _ = try await FailingStoryComposer().compose(request)
            check("the failing stub fails", false)
        } catch {
            check("the failing stub fails", error is StoryComposeFailure)
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
