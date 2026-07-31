import Foundation

/// Paikallinen tallennus.
///
/// Rajapinta on erillään toteutuksesta, koska tämä korvautuu Worker-clientilla
/// kun synkronointi tulee. JSON-tiedosto riittää siihen asti: perheen muistojen
/// määrä on satoja, ei satojatuhansia, eikä tietokantaa kannata valita ennen
/// kuin backend on olemassa — kahden totuudenlähteen synkronointi on se ansa
/// jota vasten tämä on suunniteltu.
@MainActor
@Observable
final class MemoryStore {
    private(set) var subjects: [Subject] = []
    private(set) var memories: [Memory] = []
    private(set) var questions: [FollowUpQuestion] = []

    /// Kirjoittajan nimi. Korvautuu perheen jäsentiedolla kun kutsulinkit tulevat.
    var authorName = "Minä"

    private let fileURL: URL

    init(filename: String = "memorize-store.json") {
        let documents = URL.documentsDirectory
        fileURL = documents.appendingPathComponent(filename)
        load()
    }

    // MARK: - Kyselyt

    func memories(for subjectID: String) -> [Memory] {
        memories
            .filter { $0.subjectID == subjectID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subject(id: String) -> Subject? {
        subjects.first { $0.id == id }
    }

    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects
            .filter { $0.kind == kind }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func openQuestions(limit: Int = 3) -> [FollowUpQuestion] {
        Array(questions.filter { !$0.answered }.prefix(limit))
    }

    /// Kohde jolla ei ole vielä yhtään muistoa. Näitä ei piiloteta vaan
    /// näytetään kutsuna: "kukaan ei ole vielä kertonut mitään Ainosta".
    func isEmpty(_ subject: Subject) -> Bool {
        !memories.contains { $0.subjectID == subject.id }
    }

    // MARK: - Kirjoitus

    /// Etsii samannimisen kohteen tai luo uuden. Tämä on se kohta jossa sama
    /// henkilö eri muistoista yhdistyy yhdeksi henkilökortiksi.
    func findOrCreateSubject(named name: String, kind: SubjectKind, confirmed: Bool) -> Subject {
        if let existing = subjects.first(where: {
            $0.kind == kind && $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let subject = Subject(kind: kind, title: name, confirmed: confirmed)
        subjects.append(subject)
        save()
        return subject
    }

    func add(_ subject: Subject) {
        subjects.append(subject)
        save()
    }

    func add(_ memory: Memory) {
        memories.append(memory)
        save()
    }

    func add(questions newQuestions: [FollowUpQuestion]) {
        questions.append(contentsOf: newQuestions)
        save()
    }

    /// Täydentää kohteen tiedot sillä mitä siitä kerrottiin.
    ///
    /// **Vain tyhjät kentät täytetään.** Ihmisen kirjoittamaa otsikkoa tai
    /// aiemman muiston tuomaa ajankohtaa ei ylikirjoiteta — myöhempi sanelu ei
    /// saa hiljaa muuttaa sitä mitä perhe on jo yhdessä päättänyt.
    func describe(subjectID: String, title: String?, dateHint: DateHint?) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        if let title, subjects[index].title.isEmpty {
            subjects[index].title = title
        }
        if let dateHint, subjects[index].dateHint == nil {
            subjects[index].dateHint = dateHint
        }
        save()
    }

    /// Nimeää kohteen uudelleen. Käytetään kun kertoja korjaa puheentunnistuksen
    /// väärin kuuleman nimen — se on ainoa hetki jolloin virhe on vielä
    /// korjattavissa, koska myöhemmin kukaan ei tiedä mitä nauhalla sanottiin.
    ///
    /// Jos samanniminen kohde on jo olemassa, korjattu sulautuu siihen: kertoja
    /// tarkoitti samaa ihmistä, ja kaksi korttia olisi juuri se kaksoiskappale
    /// jota koko perusmuotovaatimus yrittää estää.
    func rename(subjectID: String, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = subjects.firstIndex(where: { $0.id == subjectID })
        else { return }

        let kind = subjects[index].kind
        if let existing = subjects.first(where: {
            $0.id != subjectID && $0.kind == kind &&
                $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            for i in memories.indices where memories[i].subjectID == subjectID {
                memories[i].subjectID = existing.id
            }
            for i in memories.indices {
                memories[i].mentionedSubjectIDs = memories[i].mentionedSubjectIDs.map {
                    $0 == subjectID ? existing.id : $0
                }
            }
            subjects.remove(at: index)
        } else {
            subjects[index].title = trimmed
        }
        save()
    }

    /// Päivittää muiston siivotun tekstin. `rawTranscript` ei muutu koskaan —
    /// alkuperäinen purku on todiste siitä mitä nauhalla oikeasti sanottiin.
    func updateBody(memoryID: String, body: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].body = body
        save()
    }

    func confirm(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].confirmed = true
        save()
    }

    func remove(subjectID: String) {
        subjects.removeAll { $0.id == subjectID }
        save()
    }

    func markAnswered(questionID: String) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[index].answered = true
        save()
    }

    // MARK: - Levy

    private struct Snapshot: Codable {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        subjects = snapshot.subjects
        memories = snapshot.memories
        questions = snapshot.questions
    }

    private func save() {
        let snapshot = Snapshot(subjects: subjects, memories: memories, questions: questions)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
