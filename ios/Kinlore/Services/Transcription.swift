import Foundation

/// Transcribing speech into text.
///
/// The real implementation uploads the audio to the Worker, which calls the ASR
/// service — keys never end up in the app. The engine is chosen on the basis of
/// the `scripts/asr-bench.mjs` comparison.
protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String
}

/// The development implementation. It returns a realistic sample of elderly
/// speech: rambling, unfinished sentences, an uncertain date and several people
/// mentioned. The UI has to be designed for input like this, not for a tidy
/// example sentence.
///
/// The samples follow the phone's language, as the stub extraction's questions
/// do (`SpokenLanguage.current`). `samples` is what a Finnish phone gets, and
/// so what the UI tests get, since they launch in Finnish; `englishSamples` is
/// what anybody running a clone in English gets. Until 28 Sep 2026 they were
/// handed a Finnish paragraph for whatever they had said.
struct StubTranscriptionService: TranscriptionService {
    var simulatedDelay: Duration = .milliseconds(1400)

    static let samples: [String] = [
        """
        No siinä kuvassa ollaan sitten sen mökin rannassa, se oli Puumalassa \
        se mökki. Tota, Aino oli siinä mun vieressä ja Toivo otti sen kuvan, \
        se oli aina se joka otti kuvat. Se oli joskus 50-luvulla, en mä nyt \
        muista tarkkaan. Siellä oli aina niin hiljaista iltaisin.
        """,
        """
        Tämä on se päivä kun Kaarina tuli meille ensimmäistä kertaa. Muistan \
        että äiti oli leiponut, ja niinku, se oli semmoinen jännä tilanne \
        kaikille. Se oli 1962 tais olla. Isä ei sanonut mitään koko iltana.
        """,
        """
        Meillä oli semmoinen puutalo Kuopiossa, siinä oli iso keittiö ja \
        siellä me aina istuttiin. Eevert asui naapurissa ja se tuli joka päivä \
        käymään. Tota, ne oli hyviä aikoja. En mä osaa selittää.
        """,
    ]

    /// The same three tellings as an English speaker might give them, written
    /// for the stub extraction's heuristics rather than word for word.
    /// `properNouns` reads only what follows the first word of a sentence, so
    /// a name sits inside its sentence where the Finnish one does and opens it
    /// where the Finnish one does; every place follows "in", which is how
    /// `looksLikePlace` knows it; and the fifties are "the fifties", which
    /// `dateHint` reads as it reads "50-luvulla".
    ///
    /// Eevert opens his sentence in both languages, so the stub proposes him
    /// in neither. `-screen interview` types this last telling as its
    /// opening, and while the English one named him, its "What sort of person
    /// was Eevert?" was the question a later round's "What sort of person was
    /// Aino?" got compared with, and dropped as a repeat of
    /// (`ExtractionContext.deduplicated`, 28 Sep 2026).
    static let englishSamples: [String] = [
        """
        So that picture is on the shore at the cottage, the cottage was in \
        Puumala. Well, Aino was there next to me and Toivo took the picture, \
        he was always the one who took the pictures. It was sometime in the \
        fifties, I don't remember exactly. It was always so quiet there in \
        the evenings.
        """,
        """
        This is the day Kaarina came to our house for the first time. I \
        remember mother had been baking and you know, it was a strange \
        evening for everyone. That was 1962, I think. Father did not say a \
        word all evening.
        """,
        """
        We had a wooden house in Kuopio, it had a big kitchen and that is \
        where we always sat. Eevert lived next door and he came round every \
        single day. Those were good times, um, I cannot really explain it.
        """,
    ]

    /// Whichever of the two the phone's language picks: what the rotation
    /// below reads, and what the demo aids in TellScreen type.
    static var inPhoneLanguage: [String] {
        SpokenLanguage.current == "en" ? englishSamples : samples
    }

    /// Rotation rather than the file-size seed this used: consecutive
    /// recordings must differ — the interview loop's rounds each say
    /// something new in development, and the test that checks the rounds
    /// accumulate their names needs to know which round said what. The seed
    /// varied with the length of real microphone audio, which made the
    /// second round a coin toss.
    @MainActor private static var next = 0

    /// `-sample film`: the film's own telling, every time, instead of the
    /// rotation. What her voice says on the soundtrack and what the screen
    /// writes down have to be the same words, and a take has to come out the
    /// same on every attempt. English, unlike the samples above, because the
    /// film is shot in English. A placeholder until the shooting list's first
    /// step (SHOOT-v16.md §1 in the video project) has replaced it with what
    /// the real pipeline heard; `-seed film` writes the same sentence into
    /// its fixture, and `StubExtractionService.filmResult` returns what was
    /// made of it.
    static let film = "That's Puumala, at the jetty. Helmi and Toivo. It was the thirties, I was small then."

    /// The canned memory `-screen interview` puts on the result screen, when
    /// the same `-sample film` is set. English for exactly the reason `film`
    /// above is: the app is filmed in English, and until 25 Sep 2026 this
    /// screen carried `samples[2]` — a Finnish paragraph held for ten seconds
    /// over the paywall beat, which is the one place in the film an isolated
    /// judge read as a rules failure rather than a flaw ("All materials in
    /// English or with an English translation").
    ///
    /// `samples` itself stays Finnish: it is what a Finnish phone processes and
    /// what the UI tests read. `englishSamples` is its counterpart for every
    /// other phone, and this is kept apart from it because the film was cut to
    /// these words.
    static let filmMemory = """
        We had a wooden house in Kuopio, it had a big kitchen and that is \
        where we always sat. Eevert lived next door and he came round every \
        single day. Well — those were good times. I cannot really explain it.
        """

    func transcribe(audioURL: URL) async throws -> String {
        #if DEBUG
        if let delay = AppServices.processingDelay(transcribing: true) { try await Task.sleep(for: delay) }
        #endif
        try await Task.sleep(for: simulatedDelay)
        if UserDefaults.standard.string(forKey: "sample") == "film" { return Self.film }
        return await MainActor.run {
            defer { Self.next += 1 }
            let pool = Self.inPhoneLanguage
            return pool[Self.next % pool.count]
        }
    }
}

#if DEBUG
/// Fails the way a reply with no words in it fails: `RemoteError.emptyResult`,
/// which `RemoteTranscriptionService` throws on a 200 whose text is blank.
///
/// That is not how the Worker answers a silence today. `complete()` refuses a
/// reply with no content (`openrouter.ts`), so the route answers 502
/// `upstream_failed` and the app meets it as `badStatus(502)`. The catch-up
/// counts the two alike, which is what this stands in for.
///
/// Switched on with `-defer silence`, and it never stops failing — which is the
/// point. This is the shape of a permanent failure, and what matters is that the
/// catch-up counts it, moves on to the next recording rather than stopping, and
/// after the third failure asks only a day later, then less and less often. See
/// docs/ARCHITECTURE.md §16.
struct SilentRecordingTranscriptionService: TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String {
        throw RemoteError.emptyResult
    }
}

/// Fails the run's first transcription as though the AI minutes had run out,
/// then gets out of the way and lets the real service through.
///
/// Switched on with `-defer once`. One failure rather than every failure,
/// because the interesting half is what happens next: the audio is saved, the
/// catch-up finds it, and the memory finishes itself.
struct DeferringTranscriptionService: TranscriptionService {
    let wrapped: TranscriptionService

    @MainActor private static var hasFired = false

    func transcribe(audioURL: URL) async throws -> String {
        let isFirst = await MainActor.run {
            defer { Self.hasFired = true }
            return !Self.hasFired
        }
        if isFirst {
            throw RemoteError.quotaExceeded(kind: "ai_seconds", used: 600, limit: 600)
        }
        return try await wrapped.transcribe(audioURL: audioURL)
    }
}
#endif
