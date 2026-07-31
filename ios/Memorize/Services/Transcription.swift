import Foundation

/// Puheen purku tekstiksi.
///
/// Oikea toteutus lataa äänen Workerille, joka kutsuu ASR-palvelua — avaimet
/// eivät koskaan päädy sovellukseen. Moottori valitaan `scripts/asr-bench.mjs`
/// -vertailun perusteella.
protocol TranscriptionService {
    func transcribe(audioURL: URL) async throws -> String
}

/// Kehitysvaiheen toteutus. Palauttaa realistisen näytteen vanhuksen puheesta:
/// rönsyilevää, keskenjääviä lauseita, epävarma ajankohta, useita mainittuja
/// henkilöitä. Käyttöliittymä pitää suunnitella tällaiselle syötteelle eikä
/// siistille esimerkkilauseelle.
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
        // Vaihdellaan näytettä nauhoituksen keston mukaan, jottei sama teksti
        // toistu joka kerta kehitystä tehdessä.
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
