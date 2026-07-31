import Foundation

/// Mistä sovellus hakee puheen purun ja jäsennyksen.
///
/// Jos backendin osoitetta ei ole määritetty, käytetään stubeja. Sovellus
/// toimii siis aina — ilman avainta, ilman verkkoa, ilman backendiä — ja
/// osoitteen asettaminen kytkee oikeat palvelut päälle. Se pitää kehityksen
/// käynnissä silloinkin kun Worker on rikki.
enum AppServices {
    /// Backendin osoite. Asetetaan käynnistysargumentilla:
    ///   `-api http://localhost:8787`
    /// tai pysyvästi `UserDefaults`iin avaimella `api`.
    static var apiBaseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: "api"),
              !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    static var isRemote: Bool { apiBaseURL != nil }

    static func transcription() -> TranscriptionService {
        guard let base = apiBaseURL else { return StubTranscriptionService() }
        return RemoteTranscriptionService(baseURL: base)
    }

    static func extraction() -> ExtractionService {
        guard let base = apiBaseURL else { return StubExtractionService() }
        return RemoteExtractionService(baseURL: base)
    }
}

// MARK: - Yhteinen kutsu

enum RemoteError: LocalizedError {
    case badStatus(Int)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "Palvelin vastasi virheellä \(code)."
        case .emptyResult: "Palvelin ei palauttanut tulosta."
        }
    }
}

private func post<Response: Decodable>(
    _ path: String,
    baseURL: URL,
    body: some Encodable,
    timeout: TimeInterval
) async throws -> Response {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    // Iäkäs käyttäjä voi puhua pitkään, ja äänen purku kestää sen mukana.
    // Oletusaikakatkaisu katkaisisi pisimmät ja arvokkaimmat muistot.
    request.timeoutInterval = timeout

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw RemoteError.emptyResult }
    guard (200 ..< 300).contains(http.statusCode) else {
        throw RemoteError.badStatus(http.statusCode)
    }
    return try JSONDecoder().decode(Response.self, from: data)
}

// MARK: - Purku

struct RemoteTranscriptionService: TranscriptionService {
    let baseURL: URL

    private struct Request: Encodable {
        let audio: String
        let format: String
    }

    private struct Reply: Decodable {
        let text: String
    }

    func transcribe(audioURL: URL) async throws -> String {
        let data = try Data(contentsOf: audioURL)
        let reply: Reply = try await post(
            "transcribe",
            baseURL: baseURL,
            body: Request(
                audio: data.base64EncodedString(),
                format: audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
            ),
            timeout: 180
        )
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteError.emptyResult
        }
        return reply.text
    }
}

// MARK: - Jäsennys

struct RemoteExtractionService: ExtractionService {
    let baseURL: URL

    private struct Request: Encodable {
        let transcript: String
    }

    /// Vastaa backendin `ExtractionResult`ia. Vuodet kulkevat kokonaislukuina,
    /// koska kielimallit käsittelevät vuosia luotettavasti ja unix-aikaleimoja
    /// eivät lainkaan — muunnos tehdään täällä.
    private struct Reply: Decodable {
        struct Mention: Decodable {
            let name: String
            let kind: String
            let confidence: Double
        }

        struct DateReply: Decodable {
            let start_year: Int?
            let end_year: Int?
            let precision: String
        }

        let body: String
        let mentions: [Mention]
        let date: DateReply
        let questions: [String]
    }

    func extract(transcript: String) async throws -> ExtractionResult {
        let reply: Reply = try await post(
            "extract",
            baseURL: baseURL,
            body: Request(transcript: transcript),
            timeout: 90
        )

        return ExtractionResult(
            body: reply.body,
            mentions: reply.mentions.compactMap { mention in
                // Tuntematon kind hylätään mieluummin kuin arvataan henkilöksi:
                // väärä sukulainen on pahempi kuin puuttuva.
                guard let kind = SubjectKind(rawValue: mention.kind) else { return nil }
                return MentionedEntity(
                    name: mention.name,
                    kind: kind,
                    confidence: mention.confidence
                )
            },
            dateHint: Self.dateHint(from: reply.date),
            questions: reply.questions
        )
    }

    private static func dateHint(from reply: Reply.DateReply) -> DateHint? {
        guard let precision = DatePrecision(rawValue: reply.precision), precision != .unknown else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current

        func date(_ year: Int?) -> Date? {
            guard let year else { return nil }
            return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }

        return DateHint(
            start: date(reply.start_year),
            end: date(reply.end_year),
            precision: precision
        )
    }
}
