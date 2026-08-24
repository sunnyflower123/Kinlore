import AVFoundation
import Foundation

/// Where the app gets transcription and extraction from.
///
/// If no backend address is configured, stubs are used. The app therefore always
/// works — without a key, without a network, without a backend — and setting the
/// address switches the real services on. That keeps development moving even
/// when the Worker is broken.
enum AppServices {
    /// Where a real install syncs (docs/UX.md §7). Baked in on deploy day,
    /// 24 Aug 2026 — before this, a Release build had no address at all and
    /// every real install was silently a single-device archive.
    static let productionURL = "https://memorize.arkiste.workers.dev"

    /// The backend address. A Release build defaults to `productionURL`;
    /// `-api http://localhost:8787` overrides it, and `-api ""` means no
    /// backend at all. Every UI test launch passes `-api` explicitly — empty,
    /// or a dead loopback address — so a test run can never talk to
    /// production by accident.
    ///
    /// A DEBUG build without `-api` stays on stubs on purpose. The demo,
    /// screenshot and test recipes all launch without an address and rely on
    /// the stub pipeline; a DEBUG default of the production URL would point
    /// every one of them — and every parallel session's — at the live
    /// database. A device build that should sync passes `-api` or runs the
    /// Release configuration.
    static var apiBaseURL: URL? {
        if let raw = UserDefaults.standard.string(forKey: "api") {
            guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
            return url
        }
        #if DEBUG
        return nil
        #else
        return URL(string: productionURL)
        #endif
    }

    static var isRemote: Bool { apiBaseURL != nil }

    #if DEBUG
    /// `-defer once`: the first recording of the run is saved as audio without a
    /// transcript, as though the month's AI minutes had just run out.
    ///
    /// The deferred memory (docs/ARCHITECTURE.md §16) is otherwise reachable
    /// only by arranging a real outage — being out of minutes, or out of signal,
    /// at the exact moment somebody is talking. Neither a screenshot run nor the
    /// demo video can arrange that, and this is the one path in the app whose
    /// whole point is what happens afterwards.
    ///
    /// Only the Tell screen honours it. The catch-up is deliberately left with a
    /// working transcriber, because it is the half being demonstrated: an
    /// argument that broke both ends would show the waiting and never the
    /// finishing.
    static var defersNextTranscription: Bool {
        ["once", "silence"].contains(UserDefaults.standard.string(forKey: "defer") ?? "")
    }

    /// `-defer silence`: **every** transcription in the run fails the way a
    /// recording with no words in it fails.
    ///
    /// That is the realistic permanent failure — a button pressed and nothing
    /// said — and it is the one the catch-up has to stop asking about, because
    /// every attempt is paid for and none of them can ever succeed. Unlike
    /// `-defer once` it is wired into `transcription()` itself so the catch-up
    /// meets it too: here the interesting part *is* the second, third and fourth
    /// try.
    static var simulatesSilentRecording: Bool {
        UserDefaults.standard.string(forKey: "defer") == "silence"
    }

    /// `-defer structure`: **every** extraction in the run fails, the way a
    /// Worker that answers `transcribe` and refuses `extract` fails.
    ///
    /// This is the branch that used to lose the recording outright, and it is
    /// unreachable by hand: it needs the expensive half of the pipeline to
    /// succeed and the cheap half to fail at the same moment. What is worth
    /// looking at is what the archive holds afterwards.
    static var simulatesFailedOrganising: Bool {
        UserDefaults.standard.string(forKey: "defer") == "structure"
    }
    #endif

    /// The token comes from the caller's `Session` and is read on every call,
    /// not captured once: "Tyhjennä tämä laite" replaces the identity, and a
    /// service created before that must not keep authenticating as the old one.
    /// Reading the Keychain here directly would be worse still — `loadOrCreate`
    /// mints a fresh identity on any failed read, and a token the server has
    /// never seen turns every request into a 401.
    static func transcription(token: @escaping () -> String) -> TranscriptionService {
        #if DEBUG
        if simulatesSilentRecording { return SilentRecordingTranscriptionService() }
        #endif
        guard let base = apiBaseURL else { return StubTranscriptionService() }
        return RemoteTranscriptionService(baseURL: base, token: token)
    }

    static func purchases() -> PurchaseService {
        RevenueCatPurchases.configuredKey == nil
            ? StubPurchaseService()
            : RevenueCatPurchases()
    }

    static func extraction(token: @escaping () -> String) -> ExtractionService {
        #if DEBUG
        if simulatesFailedOrganising { return FailingExtractionService() }
        #endif
        guard let base = apiBaseURL else { return StubExtractionService() }
        return RemoteExtractionService(baseURL: base, token: token)
    }
}

// MARK: - Shared request

enum RemoteError: LocalizedError {
    case badStatus(Int)
    case emptyResult
    /// The month's AI minutes or the photo limit are used up. A separate case,
    /// because this is NOT an error but a situation the app has an answer to:
    /// the recording is saved anyway and transcribed later.
    case quotaExceeded(kind: String, used: Int, limit: Int)

    var isQuota: Bool {
        if case .quotaExceeded = self { return true }
        return false
    }

    /// Finnish: these strings are shown to the user.
    ///
    /// No status codes. "Palvelin vastasi virheellä 500" is a fact about our
    /// server told to somebody who has no server — an error message is supposed
    /// to say what happened and what to do, and a number does neither. The code
    /// is still available to whoever is debugging, in `debugText` below.
    var errorDescription: String? {
        switch self {
        case .badStatus: "Yhteys perheen palveluun ei onnistunut. Yritä hetken kuluttua uudelleen."
        case .emptyResult: "Puheesta ei saatu sanoja."
        case .quotaExceeded(let kind, _, let limit):
            kind == "photos"
                ? "Ilmaisessa arkistossa on tilaa \(limit) kuvalle."
                // Not "AI-minuutit", which is the one place that name survived
                // after the family screen dropped it — and the worst place for
                // it to survive, because this is the sentence somebody meets at
                // the moment the limit stops them. The same quota is
                // "kertominen tässä kuussa" everywhere else it is named
                // (docs/ARCHITECTURE.md §21).
                //
                // What is *not* said here matters as much: the telling itself
                // is safe. Rule 2 is that telling is never paywalled, and a
                // quota stops the writing-down rather than the voice.
                : "Tämän kuukauden kertomisaika on käytetty. Äänesi on silti tallessa."
        }
    }

    /// English, for the console. The status code belongs here rather than in
    /// anything a user reads — it is the first thing a developer wants and the
    /// last thing an 80-year-old needs.
    var debugText: String {
        switch self {
        case .badStatus(let code): "HTTP \(code)"
        case .emptyResult: "no words in the reply"
        case .quotaExceeded(let kind, let used, let limit): "quota \(kind) \(used)/\(limit)"
        }
    }
}

/// The server's quota response. Its own type, because a nested type is not
/// allowed inside a generic function.
private struct QuotaDenial: Decodable {
    let kind: String
    let used: Int
    let limit: Int
}

private func post<Response: Decodable>(
    _ path: String,
    baseURL: URL,
    token: String,
    body: some Encodable,
    timeout: TimeInterval
) async throws -> Response {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    // An elderly user may talk for a long time, and transcription takes as long
    // as the audio. The default timeout would cut off the longest and most
    // valuable memories.
    request.timeoutInterval = timeout

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw RemoteError.emptyResult }
    if http.statusCode == 402, let denial = try? JSONDecoder().decode(QuotaDenial.self, from: data) {
        throw RemoteError.quotaExceeded(kind: denial.kind, used: denial.used, limit: denial.limit)
    }
    guard (200 ..< 300).contains(http.statusCode) else {
        throw RemoteError.badStatus(http.statusCode)
    }
    return try JSONDecoder().decode(Response.self, from: data)
}

// MARK: - Transcription

struct RemoteTranscriptionService: TranscriptionService {
    let baseURL: URL
    let token: () -> String

    private struct Request: Encodable {
        let audio: String
        let format: String
        /// The recording's length. The backend rejects a transcript that
        /// contains more words than fit into this much time — on poor audio the
        /// model hallucinates rather than falling silent, and an invented memory
        /// is worse than a missing one.
        let seconds: Double?
    }

    private struct Reply: Decodable {
        let text: String
    }

    func transcribe(audioURL: URL) async throws -> String {
        let data = try Data(contentsOf: audioURL)
        let reply: Reply = try await post(
            "transcribe",
            baseURL: baseURL,
            token: token(),
            body: Request(
                audio: data.base64EncodedString(),
                format: audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension,
                seconds: Self.duration(of: audioURL)
            ),
            timeout: 180
        )
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteError.emptyResult
        }
        return reply.text
    }

    /// Read from the file rather than the recorder's clock: if audio ever comes
    /// from somewhere other than our own recording, the duration is still right.
    private static func duration(of url: URL) -> Double? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }
}

// MARK: - Extraction

struct RemoteExtractionService: ExtractionService {
    let baseURL: URL
    let token: () -> String

    private struct Request: Encodable {
        let transcript: String
        let corrections: [Correction]
        /// Where the teller is on the question ladder, 1–5. Omitted when the
        /// caller does not track it — the Worker then leaves the follow-up
        /// questions wherever the gaps lead.
        let level: Int?

        struct Correction: Encodable {
            let from: String
            let to: String
        }
    }

    /// Mirrors the backend's `ExtractionResult`. Years travel as integers,
    /// because language models handle years reliably and unix timestamps not at
    /// all — the conversion happens here.
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

        /// The level arrived beside the question text only with the ladder
        /// (docs/ARCHITECTURE.md §12). A Worker that has not been redeployed
        /// still sends plain strings, and a question without a level is
        /// perfectly usable — the level is then read off the wording. So both
        /// shapes decode rather than one of them failing the whole extraction.
        struct QuestionReply: Decodable {
            let text: String
            let level: Int?

            private enum CodingKeys: String, CodingKey { case text, level }

            init(from decoder: Decoder) throws {
                if let plain = try? decoder.singleValueContainer().decode(String.self) {
                    text = plain
                    level = nil
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = try container.decode(String.self, forKey: .text)
                level = try container.decodeIfPresent(Int.self, forKey: .level)
            }
        }

        let body: String
        let mentions: [Mention]
        let date: DateReply
        let questions: [QuestionReply]
    }

    func extract(
        transcript: String,
        corrections: [NameCorrection],
        level: Int?
    ) async throws -> ExtractionResult {
        let reply: Reply = try await post(
            "extract",
            baseURL: baseURL,
            token: token(),
            body: Request(
                transcript: transcript,
                corrections: corrections.map { .init(from: $0.from, to: $0.to) },
                level: level
            ),
            timeout: 90
        )

        return ExtractionResult(
            body: reply.body,
            mentions: reply.mentions.compactMap { mention in
                // An unknown kind is dropped rather than guessed as a person:
                // a wrong relative is worse than a missing one.
                guard let kind = SubjectKind(rawValue: mention.kind) else { return nil }
                return MentionedEntity(
                    name: mention.name,
                    kind: kind,
                    confidence: mention.confidence
                )
            },
            dateHint: Self.dateHint(from: reply.date),
            questions: reply.questions.map { ExtractedQuestion(text: $0.text, level: $0.level) }
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
