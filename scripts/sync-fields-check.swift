// Every field of a synced row either crosses the wire or stays on this phone.
//
// A pull replaces the rows it brings. `applyRemote` builds each one from the
// server's copy — `Subject(dto:)`, `Memory(dto:)` — and writes it over the
// phone's own, so a field the conversion does not carry goes back to its
// default on every row a pull brings. Every pull brings some: the echo of
// this phone's own push comes back on the next one, since the cursor moves
// only through pulls. And since fde0f73 a phone pulls once more from zero
// whenever it updates to a build that reads a different set of kinds — and
// every phone already in a family does so on its first launch of a build with
// that check, because unrecorded counts as different — which brings all of
// them. "A pull from zero is safe … it costs bandwidth and changes nothing
// already here" is the sentence that commit rests on, and this is what holds
// it.
//
// The failure is silent twice over. A field added to `Subject` compiles in
// `init?(dto:)` whether or not anybody writes it there, because the
// memberwise initialiser takes the default for whatever is left out — rule
// 10's trap for Codable, arriving by another road. The phone that set the
// field keeps it until its next sync, and then quietly does not. And no UI
// test can see it: every one of them launches the app with `-api` empty or
// pointed at a closed port, so no fixture has ever been pulled over.
//
// So each field of the four synced models is given its road here, once:
//
//   wire     sent by `dto`, read back by `init(dto:)`
//   server   never sent; the server fills it in on the way back
//   phone    never on the wire; what the pull brings must not replace it
//
// A field with no road fails, and that is the point: the next field added to
// any of the four cannot arrive without somebody deciding which of the three
// it is.
//
// TWO INSTRUMENTS, AND THEY ARE NOT THE SAME STRENGTH. The round trip is
// EXECUTED: a specimen with every field set away from its default goes
// through `dto`, JSON and `init(dto:)`, and what comes back is compared field
// by field — so is the colours' keep rule, which lives in `withColours`
// beside the conversions. The rest of what `applyRemote` keeps is READ,
// because `MemoryStore.swift` imports UIKit and a command-line build here
// cannot compile it, the limit `transcription-catchup-check.swift` states
// too. Read with it: the guard that leaves an unpushed row alone, the other
// half of the same sentence, since a pull that wrote over the outbox would
// replace a telling nobody has sent yet.
//
// Not here: what the server does with a key (`sync.ts`, which
// `subject-rules-check.mjs` and `memory-rules-check.mjs` drive), and the
// sealing of titles and words, which `family-crypto-check.swift` holds.
//
// Costs nothing: no simulator, no Worker, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/sync-fields-check scripts/sync-fields-check.swift \
//     ios/Kinlore/Services/FamilyCrypto.swift ios/Kinlore/Data/MemoryStore+Sync.swift \
//     ios/Kinlore/Model/Models.swift && /tmp/sync-fields-check

import Foundation

@main
struct SyncFieldsCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    enum Road: Equatable {
        case wire
        case server
        case phone(Keeper)
    }

    /// Who keeps a field the wire does not carry.
    enum Keeper: Equatable {
        /// A line in `applyRemote` copying this phone's value onto the row
        /// the pull brought. Read.
        case applyRemote
        /// `Subject.withColours`, which `applyRemote` calls. Run.
        case withColours
    }

    /// A stored field's value, or nil when it holds nothing. Every synced model
    /// is `Hashable`, so every field it stores is too; a value that will not
    /// cast is reported rather than compared as equal to nothing.
    static func fields(of row: Any) -> [(name: String, value: AnyHashable?, comparable: Bool)] {
        Mirror(reflecting: row).children.compactMap { child in
            guard let name = child.label else { return nil }
            let mirror = Mirror(reflecting: child.value)
            let isNone = mirror.displayStyle == .optional && mirror.children.isEmpty
            let value = child.value as? AnyHashable
            return (name, value, isNone || value != nil)
        }
    }

    static func value(_ name: String, in row: Any) -> AnyHashable? {
        fields(of: row).first { $0.name == name }?.value
    }

    static func shown(_ value: AnyHashable?) -> String {
        value.map { "\($0.base)" } ?? "nothing"
    }

    /// The fields a model has and the roads written for it, compared both ways.
    static func unroutedFields(_ names: [String], _ roads: [String: Road]) -> (missing: [String], stale: [String]) {
        (names.filter { roads[$0] == nil }, roads.keys.filter { !names.contains($0) }.sorted())
    }

    /// One model's fields, each down its road.
    ///
    /// `send` is the push and `receive` the pull; `serverFills` stands in for
    /// the Worker, writing onto the pushed row what it adds on the way back
    /// and nothing else. Returns what came back from the pull, for the keep
    /// rules that need a pulled row to lay over the phone's own.
    static func audit<Row, DTO: Codable>(
        _ model: String,
        blank: Row,
        specimen: Row,
        roads: [String: Road],
        send: (Row) -> DTO,
        serverFills: (inout DTO) -> Void,
        receive: (DTO) -> Row?
    ) -> Row? {
        print("\n— \(model) —")
        let names = fields(of: specimen).map(\.name)

        let (missing, stale) = unroutedFields(names, roads)
        check(
            "each of its \(names.count) fields has a road",
            missing.isEmpty,
            missing.map {
                "\(model).\($0) has none: sent and read back (add it to `dto` and `init(dto:)`), "
                    + "filled in by the server, or kept on this phone by `applyRemote`"
            }.joined(separator: "; ")
        )
        check(
            "and every road leads to a field it still has",
            stale.isEmpty,
            stale.map { "\(model).\($0) is gone; take its road out of this check" }.joined(separator: "; ")
        )

        let blankFields = Dictionary(uniqueKeysWithValues: fields(of: blank).map { ($0.name, $0.value) })
        let unset = fields(of: specimen).filter { $0.value == blankFields[$0.name] ?? nil }.map(\.name)
        let opaque = (fields(of: specimen) + fields(of: blank)).filter { !$0.comparable }.map(\.name)
        check(
            "the specimen sets every one of them away from its default",
            unset.isEmpty && opaque.isEmpty,
            unset.map { "\(model).\($0) is left at its default, so a loss of it would look like a round trip" }
                .joined(separator: "; ")
                + opaque.map { "\(model).\($0) holds a value this check cannot compare" }.joined(separator: "; ")
        )

        // What reaches the server, through the same JSON the request carries.
        let pushed = send(specimen)
        guard let json = try? JSONEncoder().encode(pushed),
              var wire = try? JSONDecoder().decode(DTO.self, from: json)
        else {
            check("the pushed row survives JSON", false)
            return nil
        }
        guard let unfilled = receive(wire) else {
            check("the pushed row is readable as it was sent", false, "init(dto:) answered nil")
            return nil
        }
        serverFills(&wire)
        guard let pulled = receive(wire) else {
            check("the pulled row is readable", false, "init(dto:) answered nil")
            return nil
        }

        for name in names {
            guard let road = roads[name] else { continue }
            let sent = value(name, in: specimen)
            let blankValue = blankFields[name] ?? nil
            switch road {
            case .wire:
                let back = value(name, in: pulled)
                check(
                    "\(name) goes and comes back",
                    back == sent,
                    "sent \(shown(sent)), a pull writes \(shown(back)) over it on every row it brings"
                )
            case .server:
                check(
                    "\(name) is the server's to say, and never sent",
                    value(name, in: unfilled) == blankValue,
                    "the push carries \(shown(value(name, in: unfilled)))"
                )
                check(
                    "and what the server says is read",
                    value(name, in: pulled) == sent,
                    "the server said \(shown(sent)), the phone keeps \(shown(value(name, in: pulled)))"
                )
            case .phone:
                check(
                    "\(name) stays on this phone",
                    value(name, in: pulled) == blankValue,
                    "it crosses the wire as \(shown(value(name, in: pulled))); give it the road it has"
                )
            }
        }
        return pulled
    }

    static func main() {
        let then = Date(timeIntervalSince1970: 1_780_000_000)
        let later = Date(timeIntervalSince1970: 1_780_086_400)

        // MARK: Subject

        let subjectRoads: [String: Road] = [
            "id": .wire, "kind": .wire, "title": .wire,
            "imageFilename": .phone(.applyRemote),
            "r2Key": .wire, "dateHint": .wire, "place": .wire,
            "colourImageFilename": .phone(.withColours),
            "colourR2Key": .wire, "colourConfirmedByID": .wire,
            "colourConfirmedByName": .server,
            "colourConfirmedAt": .wire,
            "portraitSubjectID": .wire, "portraitFocusX": .wire, "portraitFocusY": .wire,
            "portraitSetAt": .wire,
            "facts": .wire, "factsSetAt": .wire,
            "confirmed": .wire, "createdAt": .wire, "mergedInto": .wire, "deletedAt": .wire,
        ]
        let subject = Subject(
            id: "subject", kind: .event, title: "a title",
            imageFilename: "photo-on-this-phone.jpg", r2Key: "family/photo.jpg",
            dateHint: DateHint(start: then, end: later, precision: .decade),
            place: PlaceHint(latitude: 61.5, longitude: 28.2, precision: .exact),
            colourImageFilename: "colour-on-this-phone.jpg", colourR2Key: "family/colour.jpg",
            colourConfirmedByID: "member", colourConfirmedByName: "a member's name",
            colourConfirmedAt: later,
            portraitSubjectID: "photo-of-them", portraitFocusX: 0.4, portraitFocusY: 0.3, portraitSetAt: later,
            facts: [
                PersonFact(
                    id: "fact", kind: "birth", text: "words", date: DateHint(start: then, end: later, precision: .year),
                    placeSubjectID: "place", updatedAt: then, deletedAt: later
                ),
            ],
            factsSetAt: later,
            confirmed: false, createdAt: then, mergedInto: "subject-kept", deletedAt: later
        )
        let pulledSubject = audit(
            "Subject",
            blank: Subject(id: "", kind: .photo, title: ""),
            specimen: subject,
            roads: subjectRoads,
            send: \.dto,
            serverFills: { $0.colour_confirmed_by_name = subject.colourConfirmedByName },
            receive: Subject.init(dto:)
        )

        // MARK: Memory

        let memoryRoads: [String: Road] = [
            "id": .wire, "subjectID": .wire, "authorID": .wire, "authorName": .wire,
            "body": .wire, "rawTranscript": .wire,
            "audioFilename": .phone(.applyRemote),
            "audioR2Key": .wire, "audioDuration": .wire, "source": .wire, "createdAt": .wire,
            "mentionedSubjectIDs": .wire, "tellerSubjectID": .wire, "tellerHidden": .wire,
            "deletedAt": .wire,
        ]
        _ = audit(
            "Memory",
            blank: Memory(subjectID: "", authorName: "", body: "", source: .typed),
            specimen: Memory(
                id: "memory", subjectID: "subject", authorID: "member", authorName: "a member's name",
                body: "the words", rawTranscript: "the words as heard",
                audioFilename: "voice-on-this-phone.m4a", audioR2Key: "family/voice.m4a",
                audioDuration: 42.5, source: .voice, createdAt: then,
                mentionedSubjectIDs: ["one", "two"], tellerSubjectID: "teller", tellerHidden: true,
                deletedAt: later
            ),
            roads: memoryRoads,
            send: \.dto,
            serverFills: { _ in },
            receive: Memory.init(dto:)
        )

        // MARK: Relation

        _ = audit(
            "Relation",
            blank: Relation(fromSubjectID: "", toSubjectID: "", kind: .parentOf),
            specimen: Relation(
                id: "relation", fromSubjectID: "one", toSubjectID: "two", kind: .spouseOf,
                confirmed: true, createdAt: then, deletedAt: later
            ),
            roads: [
                "id": .wire, "fromSubjectID": .wire, "toSubjectID": .wire, "kind": .wire,
                "confirmed": .wire, "createdAt": .wire, "deletedAt": .wire,
            ],
            send: \.dto,
            serverFills: { _ in },
            receive: Relation.init(dto:)
        )

        // MARK: FollowUpQuestion

        let question = FollowUpQuestion(
            id: "question", subjectID: "subject", text: "a question", storedLevel: 4,
            answered: true, createdAt: then, authorID: "member", authorName: "a member's name",
            targetMemberID: "another member", targetName: "another member's name",
            answeredMemoryID: "memory"
        )
        // The aim's name is the asker's twice over: never sent, and derived
        // by the server from the member it names.
        let questionRoads: [String: Road] = [
            "id": .wire, "subjectID": .wire, "text": .wire, "storedLevel": .wire,
            "answered": .wire, "createdAt": .wire, "authorID": .wire,
            "authorName": .server, "targetMemberID": .wire, "targetName": .server,
            "answeredMemoryID": .wire,
        ]
        _ = audit(
            "FollowUpQuestion",
            blank: FollowUpQuestion(text: ""),
            specimen: question,
            roads: questionRoads,
            send: \.dto,
            serverFills: { dto in
                dto.author_name = question.authorName
                dto.target_name = question.targetName
            },
            receive: FollowUpQuestion.init(dto:)
        )

        // MARK: What the pull must not replace

        print("\n— what a pull must not replace —")
        if let pulledSubject {
            let merged = pulledSubject.withColours(from: subject).row
            check(
                "the colours' own picture is kept under the same key",
                merged.colourImageFilename == subject.colourImageFilename,
                "a pull leaves \(merged.colourImageFilename ?? "nothing")"
            )
        }

        // The face on a person's card, which has no phone-only half and one
        // keep rule: a pulled row that says nothing about it — no moment —
        // takes nothing away, and a removal, which is a nil id under a
        // moment, does. Both are silent when wrong, and the second is the
        // one a keep rule written for the first quietly breaks.
        var silent = subject
        silent.portraitSubjectID = nil
        silent.portraitFocusX = nil
        silent.portraitFocusY = nil
        silent.portraitSetAt = nil
        let keptFace = silent.withPortrait(from: subject)
        check(
            "a pulled row with no word on the face keeps this phone's",
            keptFace.portraitSubjectID == subject.portraitSubjectID
                && keptFace.portraitFocusX == subject.portraitFocusX
                && keptFace.portraitFocusY == subject.portraitFocusY
                && keptFace.portraitSetAt == subject.portraitSetAt,
            "a pull leaves \(keptFace.portraitSubjectID ?? "nothing")"
        )
        var removal = silent
        removal.portraitSetAt = later.addingTimeInterval(60)
        let removedFace = removal.withPortrait(from: subject)
        check(
            "and a removal under a moment takes it away",
            removedFace.portraitSubjectID == nil && removedFace.portraitSetAt == removal.portraitSetAt,
            "a pull leaves \(removedFace.portraitSubjectID ?? "nothing")"
        )

        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ios/Kinlore/Data/MemoryStore.swift")
        guard let source = try? String(contentsOf: path, encoding: .utf8),
              let body = applyRemoteBody(in: source)
        else {
            print("  FAIL applyRemote could not be read at \(path.path), or is no longer shaped as this check reads it")
            exit(1)
        }

        let kept: [(model: String, array: String, roads: [String: Road])] = [
            ("Subject", "subjects", subjectRoads),
            ("Memory", "memories", memoryRoads),
        ]
        for (model, array, roads) in kept {
            for (name, road) in roads.sorted(by: { $0.key < $1.key }) {
                switch road {
                case .phone(.applyRemote):
                    check(
                        "applyRemote keeps this phone's \(model).\(name)",
                        keeps(name, from: array, in: body),
                        "looked for `incoming.\(name) = \(array)[index].\(name)`"
                    )
                case .phone(.withColours):
                    check(
                        "applyRemote lays a pulled \(model) over this phone's through withColours",
                        body.contains("incoming.withColours(from: \(array)[index])")
                    )
                    if model == "Subject" {
                        check(
                            "and the face through withPortrait, on the same row",
                            body.contains(".withPortrait(from: \(array)[index])")
                        )
                    }
                default:
                    continue
                }
            }
        }

        for (model, set) in [
            ("subject", "dirtySubjects"), ("memory", "dirtyMemories"),
            ("question", "dirtyQuestions"), ("relation", "dirtyRelations"),
        ] {
            check(
                "an unpushed \(model) is left as it is",
                body.contains("guard !\(set).contains(dto.id)"),
                "a pull would write the server's copy over a change this phone has not sent"
            )
        }

        // MARK: The check against itself

        print("\n— the check against itself —")
        let (missing, _) = unroutedFields(["id", "title", "newField"], ["id": .wire, "title": .wire])
        check("a field with no road is reported", missing == ["newField"])
        let (_, stale) = unroutedFields(["id"], ["id": .wire, "title": .wire])
        check("and a road with no field", stale == ["title"])
        let forgetful = body.replacingOccurrences(
            of: "incoming.audioFilename = memories[index].audioFilename", with: ""
        )
        check(
            "a keep line taken out of applyRemote is reported",
            keeps("audioFilename", from: "memories", in: body)
                && !keeps("audioFilename", from: "memories", in: forgetful)
        )

        if failures > 0 {
            print("\n\(failures) failed")
            exit(1)
        }
        print("\nall checks passed")
    }

    /// The body of `applyRemote`, by counting braces from its signature.
    static func applyRemoteBody(in source: String) -> String? {
        guard let signature = source.range(of: "func applyRemote(_ reply: SyncPullReply) {") else { return nil }
        var depth = 1
        var index = signature.upperBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[signature.upperBound..<index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    static func keeps(_ field: String, from array: String, in body: String) -> Bool {
        body.contains("incoming.\(field) = \(array)[index].\(field)")
    }
}
