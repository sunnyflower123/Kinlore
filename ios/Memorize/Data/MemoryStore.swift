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
    private(set) var relations: [Relation] = []

    /// Kirjoittajan nimi. Perheessä tämä tulee jäsentiedoista.
    var authorName = "Minä"

    /// Viimeisin palvelimelta saatu järjestysluku. Seuraava veto pyytää kaiken
    /// tätä suuremman.
    private(set) var syncSeq = 0

    /// Lähtevä jono: paikallisesti muuttuneet rivit joita ei ole vielä työnnetty.
    /// Erillinen joukko eikä mallin kenttä, jotta mallit pysyvät puhtaina ja
    /// vastaavat sitä mitä palvelimelle lähetetään.
    private(set) var dirtySubjects: Set<String> = []
    private(set) var dirtyMemories: Set<String> = []
    private(set) var dirtyQuestions: Set<String> = []
    private(set) var dirtyRelations: Set<String> = []

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

    /// Seuraa sulautusketjua. Viittaus sulautettuun kohteeseen ratkeaa aina
    /// säilyvään, joten mikään ei osoita tyhjään.
    func subject(id: String) -> Subject? {
        var current = subjects.first { $0.id == id }
        // Kierrossuoja: rikkinäinen data ei saa jumittaa käyttöliittymää.
        for _ in 0 ..< 8 {
            guard let target = current?.mergedInto else { return current }
            current = subjects.first { $0.id == target }
        }
        return current
    }

    /// Sulautetut eivät ole omia kohteitaan, joten ne eivät näy listoissa.
    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects
            .filter { $0.kind == kind && $0.mergedInto == nil }
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
        dirtySubjects.insert(subject.id)
        save()
        return subject
    }

    func add(_ subject: Subject) {
        subjects.append(subject)
        dirtySubjects.insert(subject.id)
        save()
    }

    func add(_ memory: Memory) {
        memories.append(memory)
        dirtyMemories.insert(memory.id)
        save()
    }

    func add(questions newQuestions: [FollowUpQuestion]) {
        questions.append(contentsOf: newQuestions)
        dirtyQuestions.formUnion(newQuestions.map(\.id))
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
        dirtySubjects.insert(subjectID)
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
            $0.id != subjectID && $0.kind == kind && $0.mergedInto == nil &&
                $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            // Viittaukset siirretään heti, jotta paikallinen näkymä on ehjä...
            for i in memories.indices where memories[i].subjectID == subjectID {
                memories[i].subjectID = existing.id
            }
            for i in memories.indices {
                memories[i].mentionedSubjectIDs = memories[i].mentionedSubjectIDs.map {
                    $0 == subjectID ? existing.id : $0
                }
            }
            // ...mutta riviä EI poisteta. Offline oleva toinen laite voi juuri
            // nyt lisätä muistoja tähän kohteeseen, ja poisto jättäisi ne
            // osoittamaan tyhjään. Hautakivi osoitteella ratkaisee sen ja tekee
            // sulautuksesta myös peruttavan. Ks. docs/ARKKITEHTUURI.md §2.5.
            subjects[index].mergedInto = existing.id
            dirtyMemories.formUnion(
                memories.filter { $0.subjectID == existing.id }.map(\.id)
            )
        } else {
            subjects[index].title = trimmed
        }
        dirtySubjects.insert(subjectID)
        save()
    }

    /// Päivittää muiston siivotun tekstin. `rawTranscript` ei muutu koskaan —
    /// alkuperäinen purku on todiste siitä mitä nauhalla oikeasti sanottiin.
    func updateBody(memoryID: String, body: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].body = body
        dirtyMemories.insert(memoryID)
        save()
    }

    func confirm(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].confirmed = true
        dirtySubjects.insert(subjectID)
        save()
    }

    func remove(subjectID: String) {
        subjects.removeAll { $0.id == subjectID }
        save()
    }

    func markAnswered(questionID: String) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[index].answered = true
        dirtyQuestions.insert(questionID)
        save()
    }

    // MARK: - Synkronointi
    //
    // Mutaatiot ovat täällä eivätkä laajennuksessa, koska ne koskevat samoja
    // private(set)-kenttiä kuin muukin kirjoitus. Siirtomuodot ovat
    // MemoryStore+Sync.swift:ssä: ne ovat sopimus palvelimen kanssa.

    /// Työnnettävät rivit. Tyhjä hyötykuorma tarkoittaa ettei ole mitään
    /// lähetettävää.
    func pendingPayload() -> SyncPayload {
        SyncPayload(
            subjects: subjects.filter { dirtySubjects.contains($0.id) }.map(\.dto),
            memories: memories.filter { dirtyMemories.contains($0.id) }.map(\.dto),
            questions: questions.filter { dirtyQuestions.contains($0.id) }.map(\.dto),
            relations: relations.filter { dirtyRelations.contains($0.id) }.map(\.dto)
        )
    }

    var hasPendingChanges: Bool {
        !dirtySubjects.isEmpty || !dirtyMemories.isEmpty || !dirtyQuestions.isEmpty
            || !dirtyRelations.isEmpty
    }

    /// Kuittaa työnnetyt rivit. Vain juuri lähetetyt: jos käyttäjä ehti kirjoittaa
    /// pyynnön aikana, uusi muutos jää jonoon eikä katoa.
    func clearPending(_ payload: SyncPayload) {
        dirtySubjects.subtract(payload.subjects.map(\.id))
        dirtyMemories.subtract(payload.memories.map(\.id))
        dirtyQuestions.subtract(payload.questions.map(\.id))
        dirtyRelations.subtract(payload.relations.map(\.id))
        save()
    }

    /// Soveltaa palvelimelta saadut rivit.
    ///
    /// Paikallisesti muuttunut rivi ohitetaan: se on vielä jonossa, ja etäversio
    /// ylikirjoittaisi juuri kerrotun muiston. Se päätyy palvelimelle
    /// seuraavalla työnnöllä ja voittaa silloin suuremmalla järjestysluvulla.
    func applyRemote(_ reply: SyncPullReply) {
        for dto in reply.subjects {
            guard !dirtySubjects.contains(dto.id), let incoming = Subject(dto: dto) else { continue }
            if let index = subjects.firstIndex(where: { $0.id == dto.id }) {
                subjects[index] = incoming
            } else {
                subjects.append(incoming)
            }
        }

        for dto in reply.memories {
            guard !dirtyMemories.contains(dto.id) else { continue }
            let incoming = Memory(dto: dto)
            if let index = memories.firstIndex(where: { $0.id == dto.id }) {
                memories[index] = incoming
            } else {
                memories.append(incoming)
            }
        }

        for dto in reply.questions {
            guard !dirtyQuestions.contains(dto.id) else { continue }
            let incoming = FollowUpQuestion(dto: dto)
            if let index = questions.firstIndex(where: { $0.id == dto.id }) {
                questions[index] = incoming
            } else {
                questions.append(incoming)
            }
        }

        for dto in reply.relations {
            guard !dirtyRelations.contains(dto.id), let incoming = Relation(dto: dto) else { continue }
            if let index = relations.firstIndex(where: { $0.id == dto.id }) {
                relations[index] = incoming
            } else {
                relations.append(incoming)
            }
        }

        advance(seq: reply.seq)
    }

    func advance(seq: Int) {
        guard seq > syncSeq else { return }
        syncSeq = seq
        save()
    }

    // MARK: - Sukulaisuus

    /// Henkilön suhteet ryhmiteltyinä siten kuin ihminen ne ajattelee.
    ///
    /// Symmetriset suhteet luetaan molempiin suuntiin, `parentOf` suunnattuna:
    /// sama rivi tarkoittaa toiselle vanhempaa ja toiselle lasta.
    func relatives(of subjectID: String, kind: RelationKind, asParent: Bool = false) -> [Subject] {
        relations.compactMap { relation -> Subject? in
            guard relation.kind == kind else { return nil }
            let otherID: String?
            if kind.isSymmetric {
                otherID = relation.fromSubjectID == subjectID ? relation.toSubjectID
                    : relation.toSubjectID == subjectID ? relation.fromSubjectID : nil
            } else if asParent {
                // Etsitään tämän henkilön lapsia: hän on `from`.
                otherID = relation.fromSubjectID == subjectID ? relation.toSubjectID : nil
            } else {
                otherID = relation.toSubjectID == subjectID ? relation.fromSubjectID : nil
            }
            guard let otherID else { return nil }
            return subject(id: otherID)
        }
    }

    func relation(between a: String, and b: String, kind: RelationKind) -> Relation? {
        relations.first { relation in
            guard relation.kind == kind else { return false }
            if kind.isSymmetric {
                return (relation.fromSubjectID == a && relation.toSubjectID == b)
                    || (relation.fromSubjectID == b && relation.toSubjectID == a)
            }
            return relation.fromSubjectID == a && relation.toSubjectID == b
        }
    }

    /// Lisää suhteen, tai vahvistaa olemassa olevan ehdotuksen.
    @discardableResult
    func addRelation(from: String, to: String, kind: RelationKind, confirmed: Bool = true) -> Relation? {
        guard from != to else { return nil }
        if let existing = relation(between: from, and: to, kind: kind) {
            if confirmed { confirmRelation(id: existing.id) }
            return existing
        }
        let relation = Relation(fromSubjectID: from, toSubjectID: to, kind: kind, confirmed: confirmed)
        relations.append(relation)
        dirtyRelations.insert(relation.id)
        save()
        return relation
    }

    func confirmRelation(id: String) {
        guard let index = relations.firstIndex(where: { $0.id == id }) else { return }
        relations[index].confirmed = true
        dirtyRelations.insert(id)
        save()
    }

    func removeRelation(id: String) {
        relations.removeAll { $0.id == id }
        dirtyRelations.remove(id)
        save()
    }

    // MARK: - Media

    /// Kohteet joilla on paikallinen kuva mutta ei vielä R2-avainta.
    func subjectsAwaitingUpload() -> [Subject] {
        subjects.filter { $0.imageFilename != nil && $0.r2Key == nil }
    }

    /// Muistot joiden ääni on vielä vain paikallisesti. Alkuperäinen ääni
    /// ladataan aina, myös ilmaisella tasolla — se on tuotteen ydin.
    func memoriesAwaitingUpload() -> [Memory] {
        memories.filter { $0.audioFilename != nil && $0.audioR2Key == nil }
    }

    func setR2Key(subjectID: String, key: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].r2Key = key
        dirtySubjects.insert(subjectID)
        save()
    }

    func setAudioR2Key(memoryID: String, key: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].audioR2Key = key
        dirtyMemories.insert(memoryID)
        save()
    }

    /// Ladatun median paikallinen välimuisti. Ei merkitä jonoon: tiedostonimi
    /// on laitekohtainen eikä kuulu palvelimelle.
    func setLocalImage(subjectID: String, filename: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].imageFilename = filename
        save()
    }

    func setLocalAudio(memoryID: String, filename: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].audioFilename = filename
        save()
    }

    // MARK: - Levy

    struct Snapshot: Codable {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
        var syncSeq: Int = 0
        var dirtySubjects: Set<String> = []
        var dirtyMemories: Set<String> = []
        var dirtyQuestions: Set<String> = []
        var relations: [Relation] = []
        var dirtyRelations: Set<String> = []
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        subjects = snapshot.subjects
        memories = snapshot.memories
        questions = snapshot.questions
        syncSeq = snapshot.syncSeq
        // Lähtevä jono säilyy levyllä: offline tehty muisto ei saa jäädä
        // työntämättä vain siksi että sovellus suljettiin välissä.
        dirtySubjects = snapshot.dirtySubjects
        dirtyMemories = snapshot.dirtyMemories
        dirtyQuestions = snapshot.dirtyQuestions
        relations = snapshot.relations
        dirtyRelations = snapshot.dirtyRelations
    }

    func save() {
        let snapshot = Snapshot(
            subjects: subjects,
            memories: memories,
            questions: questions,
            syncSeq: syncSeq,
            dirtySubjects: dirtySubjects,
            dirtyMemories: dirtyMemories,
            dirtyQuestions: dirtyQuestions,
            relations: relations,
            dirtyRelations: dirtyRelations
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
