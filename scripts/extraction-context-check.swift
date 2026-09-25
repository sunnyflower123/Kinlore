import Foundation

// What the model is told about the family's archive.
//
// Until 19 Sep 2026 the extraction saw one thing — the transcript — so rule 6
// of the prompt could only ask about a gap in ninety seconds of speech. The
// questions converged on the three shapes that rule names and came back the
// same on the fourth telling as on the first. `ExtractionContext` is what is
// sent instead, and every way it can be wrong is silent:
//
//   * A gap reported that is not a gap. The one question an 80-year-old will
//     answer is spent asking for a year the archive already holds, and the
//     screen looks exactly the same.
//   * A gap missed. The hole stays a hole and nobody is ever asked about it.
//   * A title sent as *"Valokuva"* because `displayTitle` filled it in, which
//     tells the model the photograph is named Valokuva. `SubjectAvatar` and
//     the gallery do want that fallback; a prompt does not.
//   * A new question thrown away as a repeat when it was not one. This is the
//     expensive direction: a repeated question is a wasted turn, a discarded
//     one is a hole nobody hears about again.
//
// None of them fails a build and none shows in a screenshot. The UI is
// identical whichever questions come back — that is the whole problem with
// questions.
//
// Costs nothing: no Worker, no key, no network, no model, no simulator. The
// builder is pure and lives over the model types rather than over
// `MemoryStore`, which is what keeps it that way.
//
// Run it after touching ExtractionContext.swift.

private var failures = 0

func check(_ what: String, _ actual: some Equatable, _ expected: some Equatable) {
    let a = String(describing: actual)
    let e = String(describing: expected)
    if a == e {
        print("  ok   \(what)")
    } else {
        failures += 1
        print("  FAIL \(what)\n         got      \(a)\n         expected \(e)")
    }
}

// MARK: - A small archive

let photo = Subject(id: "p1", kind: .photo, title: "Rippijuhlat")
let untitled = Subject(id: "p2", kind: .photo, title: "")
let aino = Subject(id: "s-aino", kind: .person, title: "Aino", confirmed: false)
let toivo = Subject(
    id: "s-toivo", kind: .person, title: "Toivo",
    imageFilename: "photo-toivo.jpg",
    dateHint: DateHint(start: Date(timeIntervalSince1970: -1_000_000_000), end: nil, precision: .year)
)
let puumala = Subject(id: "s-puumala", kind: .place, title: "Puumala")

func memory(_ id: String, on subject: String, naming: [String] = [], deleted: Bool = false) -> Memory {
    var m = Memory(
        id: id, subjectID: subject, authorName: "Minä", body: "…",
        source: .voice, mentionedSubjectIDs: naming
    )
    if deleted { m.deletedAt = .now }
    return m
}

let told = [
    memory("m1", on: "p1", naming: ["s-aino", "s-puumala"]),
    memory("m2", on: "p1", naming: ["s-toivo"]),
    memory("m3", on: "s-toivo"),
]

let relation = Relation(
    id: "r1", fromSubjectID: "s-toivo", toSubjectID: "s-aino", kind: .parentOf, confirmed: true
)

let open = [
    FollowUpQuestion(id: "q1", subjectID: "p1", text: "Millainen ihminen Aino oli?"),
    FollowUpQuestion(id: "q2", subjectID: "p1", text: "Missä tämä on otettu?", answered: true),
    FollowUpQuestion(id: "q3", subjectID: "s-toivo", text: "Mitä Toivo teki työkseen?"),
    FollowUpQuestion(id: "q4", subjectID: nil, text: "Mistä haluaisit kertoa?"),
]

func build(_ target: Subject?, questions: [FollowUpQuestion] = open) -> ExtractionContext {
    ExtractionContext.build(
        target: target, subjects: [photo, untitled, aino, toivo, puumala],
        memories: told, relations: [relation], questions: questions
    )
}

@main
struct ExtractionContextCheck {
    static func main() {
        // MARK: - The subject

        print("— the subject the telling is filed under —")
        let onPhoto = build(photo)
        check("its kind travels", onPhoto.subject?.kind ?? "", "photo")
        check("and its title", onPhoto.subject?.title ?? "", "Rippijuhlat")
        check("with the memories it already has", onPhoto.subject?.memories ?? -1, 2)
        // The fallback belongs on a card, never in a prompt: a photograph called
        // "Valokuva" is a fact the model would be entitled to use, and it is not one.
        check("an untitled photograph sends no title", build(untitled).subject?.title == nil, true)
        check("and a date nobody knows is not invented", onPhoto.subject?.date == nil, true)
        check("free dictation has no subject at all", build(nil).subject == nil, true)

        // MARK: - The holes

        print("\n— what the archive does not know —")
        let known = onPhoto.known.sorted { $0.name < $1.name }
        check("only what the telling named is described", known.map(\.name), ["Aino", "Puumala", "Toivo"])
        check(
            "a person nobody has told about is short of everything",
            ExtractionContext.build(
                target: photo, subjects: [photo, aino],
                memories: [memory("m5", on: "p1", naming: ["s-aino"])],
                relations: [], questions: []
            ).known.first?.missing ?? ["<no entry>"],
            ["birth_year", "description", "relation"]
        )
        // Aino is Toivo's child in the archive above, so the one hole she does
        // not have there is the relationship. A gap reported anyway would spend
        // the one question this audience answers on something already on file.
        check(
            "and a relationship the archive holds is not reported missing",
            known.first { $0.name == "Aino" }?.missing.contains("relation") ?? true,
            false
        )
        // A friendship is a relationship the archive holds (21 Sep 2026):
        // somebody whose only line is to a friend has been placed by a
        // person, and asking who they are would be asking again.
        check(
            "a friendship counts as a relationship the archive holds",
            ExtractionContext.build(
                target: photo, subjects: [photo, aino, toivo],
                memories: [memory("m6", on: "p1", naming: ["s-aino"])],
                relations: [Relation(id: "r2", fromSubjectID: "s-aino", toSubjectID: "s-toivo", kind: .friendOf, confirmed: true)],
                questions: []
            ).known.first?.missing.contains("relation") ?? true,
            false
        )
        check(
            "a place with no point on the map says so",
            known.first { $0.name == "Puumala" }?.missing ?? ["<no entry>"],
            ["date", "place", "description"]
        )
        // Not on the list at all, in either direction. A photograph is a real
        // hole and not a question: "onko teillä kuvaa Ainosta?" is answered
        // "kyllä on", and the ladder reads that as strain.
        check(
            "a missing photograph is never a question",
            known.contains { $0.missing.contains("photo") },
            false
        )
        check(
            "an unconfirmed proposal is included — it is who most needs asking about",
            known.contains { $0.name == "Aino" },
            true
        )
        // Toivo has a photograph, a year, a memory of his own and a relationship, so
        // there is nothing to ask. Reporting a gap here would spend the one question
        // this audience answers on something already on file.
        let onToivo = build(toivo)
        check("a subject the telling did not name is not described", onToivo.known.isEmpty, true)
        let viaToivoPhoto = ExtractionContext.build(
            target: photo, subjects: [photo, toivo],
            memories: [memory("m4", on: "p1", naming: ["s-toivo"]), memory("m5", on: "s-toivo")],
            relations: [relation], questions: []
        )
        check(
            "somebody the archive has covered has no gaps reported",
            viaToivoPhoto.known.first?.missing ?? ["<no entry>"],
            [String]()
        )

        // MARK: - What has been asked

        print("\n— and what has already been asked —")
        check("an open question on this subject is listed", onPhoto.asked, ["Millainen ihminen Aino oli?"])
        check("an answered one is not — it is not a repeat to ask again", onPhoto.asked.contains("Missä tämä on otettu?"), false)
        check("another subject's question is not either", onPhoto.asked.contains("Mitä Toivo teki työkseen?"), false)
        check("free dictation carries the unattached ones", build(nil).asked, ["Mistä haluaisit kertoa?"])

        // MARK: - Nothing to say

        print("\n— an empty archive stays quiet —")
        check("no target and no questions is empty", ExtractionContext.build(
            target: nil, subjects: [], memories: [], relations: [], questions: []
        ).isEmpty, true)

        // MARK: - Not twice

        print("\n— the same question is not asked twice —")
        let already = ["Millainen ihminen Aino oli?"]
        check(
            "a restatement is dropped",
            ExtractionContext.deduplicated(["Millainen ihminen Aino oikein oli?"], against: already),
            [String]()
        )
        check(
            "and so is the same question with more on the end",
            ExtractionContext.deduplicated(
                ["Millainen ihminen Aino oli ja mitä hän teki työkseen?"], against: already
            ),
            [String]()
        )
        // The expensive direction. These share "aino" and little else, and a threshold
        // that folded them together would throw away the question the photograph was
        // sent to produce.
        check(
            "a different question about the same person survives",
            ExtractionContext.deduplicated(["Minä vuonna Aino syntyi?"], against: already),
            ["Minä vuonna Aino syntyi?"]
        )
        check(
            "so does one about what is in the photograph",
            ExtractionContext.deduplicated(
                ["Kuvassa näkyy puuvene laiturissa — souditteko sillä usein?"], against: already
            ),
            ["Kuvassa näkyy puuvene laiturissa — souditteko sillä usein?"]
        )
        check(
            "case and punctuation do not make a question new",
            ExtractionContext.deduplicated(["MILLAINEN IHMINEN AINO OLI"], against: already),
            [String]()
        )
        check(
            "two of the same in one reply keep only the first",
            ExtractionContext.deduplicated(
                ["Minä vuonna Aino syntyi?", "Minä vuonna Aino oikein syntyi?"], against: []
            ),
            ["Minä vuonna Aino syntyi?"]
        )
        check("a blank question is never kept", ExtractionContext.deduplicated(["  "], against: []), [String]())
        check("with nothing asked before, everything survives", ExtractionContext.deduplicated(
            ["Missä tämä on otettu?"], against: []
        ), ["Missä tämä on otettu?"])

        // MARK: - Not more than five

        print("\n— one subject carries at most five open questions —")
        let fresh = ["Minä vuonna Aino syntyi?", "Missä tämä on otettu?", "Kuka souti veneen saareen?"]
        let two = ["Millainen ihminen Aino oli?", "Mitä Toivo teki työkseen?"]
        let four = two + ["Milloin mökki rakennettiin?", "Kenen koira pihalla juoksee?"]
        let five = four + ["Mitä saaressa syötiin?"]
        check("two open leave room for all three", ExtractionContext.admitted(fresh, against: two), fresh)
        check("four open leave room for the first one only", ExtractionContext.admitted(fresh, against: four), [fresh[0]])
        check("five open take nothing more", ExtractionContext.admitted(fresh, against: five), [String]())
        check(
            "a sixth already open, synced from another phone, is not a negative room",
            ExtractionContext.admitted(fresh, against: five + ["Kuka otti kuvan?"]),
            [String]()
        )
        // The cap counts after the repeat is gone, so a restatement does not use
        // up a slot the next question could have had.
        check(
            "a repeat is dropped before the cap is counted",
            ExtractionContext.admitted(["Millainen ihminen Aino oikein oli?"] + fresh, against: four),
            [fresh[0]]
        )
        check(
            "the question being answered frees its slot",
            ExtractionContext.admitted(fresh, against: five, answeringNow: "Mitä saaressa syötiin?"),
            [fresh[0]]
        )
        check(
            "and is still a repeat to ask again",
            ExtractionContext.admitted(["Mitä saaressa oikein syötiin?"], against: five, answeringNow: "Mitä saaressa syötiin?"),
            [String]()
        )
        check(
            "a question that is not open frees nothing",
            ExtractionContext.admitted(fresh, against: five, answeringNow: "Mistä haluaisit kertoa?"),
            [String]()
        )

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)

    }
}
