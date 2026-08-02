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
/// The samples are Finnish because that is the input the app actually processes.
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

    func transcribe(audioURL: URL) async throws -> String {
        try await Task.sleep(for: simulatedDelay)
        // Vary the sample by recording length, so the same text does not come
        // back every time during development.
        let seed = Int(FileManager.default.fileSize(at: audioURL) / 1024)
        return Self.samples[abs(seed) % Self.samples.count]
    }
}

private extension FileManager {
    func fileSize(at url: URL) -> Int64 {
        let attributes = try? attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int64) ?? 0
    }
}

#if DEBUG
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
