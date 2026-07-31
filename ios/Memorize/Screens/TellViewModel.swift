import Foundation

/// Taikahetken tilakone: nauhoitus → purku → jäsennys → tulos.
///
/// Vaiheet ovat erillisiä, koska käyttäjän pitää nähdä mitä tapahtuu. Yksi
/// geneerinen "ladataan" -pyörä 20 sekunnin ajan tuntuu rikkinäiseltä; "puran
/// puhetta" ja "järjestelen muistoa" tuntuvat työltä.
@MainActor
@Observable
final class TellViewModel {
    enum Phase: Equatable {
        case idle
        case recording
        /// Näppäimistöllä kirjoittaminen. Sanelu on ensisijainen tapa, mutta
        /// kuvia lisäävä lapsenlapsi haluaa usein kirjoittaa — ja hiljaisessa
        /// tilassa tai kuulokkeitta puhuminen ei aina käy.
        case writing
        case transcribing
        case organizing
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Kirjoitettavan muiston teksti.
    var draft = ""
    private(set) var transcript: String?
    private(set) var result: ExtractionResult?
    /// Kohde johon muisto sijoitettiin — tuloksen tärkein tieto.
    private(set) var placedSubject: Subject?
    /// AI:n ehdottamat henkilöt ja paikat. Käyttäjä vahvistaa tai hylkää.
    private(set) var proposals: [Subject] = []
    private(set) var newQuestions: [FollowUpQuestion] = []
    /// Tallennetun muiston kesto, tai nil jos se kirjoitettiin. Tulosruutu
    /// näyttää äänen toiston vain kun ääntä on.
    private(set) var savedAudioDuration: TimeInterval?

    let recorder = AudioRecorder()

    private let store: MemoryStore
    private let transcription: TranscriptionService
    private let extraction: ExtractionService
    /// Kun muisto kerrotaan tietystä kuvasta tai henkilöstä, se kiinnittyy
    /// siihen. Vapaassa sanelussa tämä on nil ja kohde päätellään puheesta.
    let target: Subject?

    init(
        store: MemoryStore,
        transcription: TranscriptionService,
        extraction: ExtractionService,
        target: Subject? = nil
    ) {
        self.store = store
        self.transcription = transcription
        self.extraction = extraction
        self.target = target
    }

    // MARK: - Nauhoitus

    func startRecording() async {
        guard await recorder.requestPermission() else {
            phase = .failed("Mikrofonia ei saatu käyttöön. Salli mikrofoni asetuksista.")
            return
        }
        do {
            try recorder.start()
            phase = .recording
        } catch {
            phase = .failed("Nauhoitus ei käynnistynyt.")
        }
    }

    func stopAndProcess() async {
        guard let url = recorder.stop() else {
            // Alle sekunnin nauhoitus on vahinko, ei muisto.
            phase = .idle
            return
        }
        let duration = recorder.elapsed
        do {
            phase = .transcribing
            let text = try await transcription.transcribe(audioURL: url)
            await process(transcript: text, audioURL: url, duration: duration)
        } catch {
            phase = .failed("Puheen purku ei onnistunut. Ääni on tallessa, voit yrittää uudelleen.")
        }
    }

    // MARK: - Kirjoittaminen

    func beginWriting() {
        draft = ""
        phase = .writing
    }

    func cancelWriting() {
        draft = ""
        phase = .idle
    }

    /// Kirjoitettu teksti kulkee saman jäsennyksen läpi kuin puhuttu. Muuten
    /// kirjoittaja jäisi ilman löydettyjä henkilöitä ja jatkokysymyksiä, ja
    /// muistot olisivat kahta eri lajia samassa arkistossa.
    func submitTyped() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await process(transcript: text, audioURL: nil, duration: nil)
    }

    // MARK: - Putki

    private func process(transcript text: String, audioURL: URL?, duration: TimeInterval?) async {
        do {
            transcript = text
            phase = .organizing
            let extracted = try await extraction.extract(transcript: text)
            result = extracted

            save(extracted, transcript: text, audioURL: audioURL, duration: duration)
            phase = .done
        } catch {
            phase = .failed("Muiston järjestely ei onnistunut. Voit yrittää uudelleen.")
        }
    }

    private func save(
        _ extracted: ExtractionResult,
        transcript: String,
        audioURL: URL?,
        duration: TimeInterval?
    ) {
        // Mainitut henkilöt ja paikat syntyvät vahvistamattomina ehdotuksina.
        // Vahvistamaton ei näy sukupuussa faktana — väärä sukulaisuussuhde on
        // pahempi kuin puuttuva.
        var mentioned: [Subject] = []
        for entity in extracted.mentions {
            // Uusi henkilö syntyy AINA vahvistamattomana, riippumatta siitä
            // kuinka varma malli on. Varmuus koskee mallin omaa jäsennystä, ei
            // sitä onko henkilö oikea: se kuuli "Aino", mutta puhuja saattoi
            // sanoa "Aune". Varma-mutta-väärä on juuri se vaarallinen tapaus,
            // ja jos varmuus ohittaisi vahvistuksen, se ohittuisi aina.
            //
            // `findOrCreateSubject` palauttaa jo tunnetun henkilön sellaisenaan,
            // joten vahvistus kysytään kerran per henkilö, ei per muisto.
            let subject = store.findOrCreateSubject(
                named: entity.name,
                kind: entity.kind,
                confirmed: false
            )
            mentioned.append(subject)
        }
        proposals = mentioned.filter { !$0.confirmed }

        // Vapaa sanelu tarvitsee kodin. Nimetään se paikan ja ajan mukaan —
        // juuri se järjestely jota käyttäjä ei itse jaksaisi tehdä.
        let home = placeSubject(for: extracted, mentioned: mentioned)
        placedSubject = home

        let audioName = audioURL.flatMap(Self.persistAudio(from:))

        let memory = Memory(
            subjectID: home.id,
            authorName: store.authorName,
            body: extracted.body,
            // Kirjoitetussa muistossa raakateksti on sama kuin siivottu, mutta
            // se tallennetaan silti: jos siivousta joskus muutetaan, alkuperäinen
            // sanamuoto on yhä tallessa.
            rawTranscript: transcript,
            audioFilename: audioName,
            audioDuration: duration,
            source: audioURL == nil ? .typed : .voice,
            mentionedSubjectIDs: mentioned.map(\.id)
        )
        store.add(memory)
        savedAudioDuration = duration

        let questions = extracted.questions.map {
            FollowUpQuestion(subjectID: home.id, text: $0)
        }
        store.add(questions: questions)
        newQuestions = questions
    }

    /// Etsii tai luo kohteen johon muisto kuuluu.
    private func placeSubject(for extracted: ExtractionResult, mentioned: [Subject]) -> Subject {
        let suggested = Self.suggestedTitle(for: extracted, mentioned: mentioned)

        // Kuvasta kerrottu muisto kuuluu siihen kuvaan — ei arvailua. Kuva myös
        // saa nimen ja ajankohdan siitä mitä siitä kerrottiin: juuri se
        // järjestely jota kukaan ei jaksaisi tehdä kolmellekymmenelle
        // skannatulle valokuvalle.
        if let target {
            store.describe(subjectID: target.id, title: suggested, dateHint: extracted.dateHint)
            return store.subject(id: target.id) ?? target
        }

        // Vapaa sanelu tarvitsee kodin. Sama paikka ja aika kokoaa muistot
        // yhteen sen sijaan että jokainen sanelu synnyttäisi oman irrallisen
        // tapahtumansa.
        let title = suggested ?? "Kerrottu muisto"
        if let existing = store.subjects(of: .event).first(where: { $0.title == title }) {
            return existing
        }
        let subject = Subject(kind: .event, title: title, dateHint: extracted.dateHint)
        store.add(subject)
        return subject
    }

    /// Otsikko paikasta ja ajasta: "Puumalassa, 1950-luku".
    /// Nil jos puheesta ei irronnut kumpaakaan — silloin on rehellisempää
    /// jättää nimeämättä kuin keksiä otsikko tyhjästä.
    private static func suggestedTitle(
        for extracted: ExtractionResult,
        mentioned: [Subject]
    ) -> String? {
        var parts: [String] = []
        if let place = mentioned.first(where: { $0.kind == .place }) {
            parts.append(place.title)
        }
        if let hint = extracted.dateHint, hint.precision != .unknown {
            parts.append(hint.displayText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Siirtää äänen väliaikaishakemistosta pysyvään. Isoäidin ääni on itsessään
    /// perintö, joten sitä ei jätetä paikkaan jonka järjestelmä saa tyhjentää.
    private static func persistAudio(from url: URL) -> String? {
        let destination = URL.documentsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination.lastPathComponent
        } catch {
            return nil
        }
    }

    // MARK: - Ehdotusten käsittely

    func confirm(_ subject: Subject) {
        store.confirm(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    func reject(_ subject: Subject) {
        store.remove(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    func reset() {
        phase = .idle
        draft = ""
        transcript = nil
        result = nil
        placedSubject = nil
        proposals = []
        newQuestions = []
        savedAudioDuration = nil
    }
}
