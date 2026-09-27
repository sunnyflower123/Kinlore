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

    /// `-defer silence`: **every** transcription in the run fails with a reply
    /// that has no words in it (`RemoteError.emptyResult`).
    ///
    /// That stands in for the realistic permanent failure — a button pressed
    /// and nothing said — which the Worker itself answers 502 today
    /// (`openrouter.ts`). The catch-up counts both on the recording's side and
    /// has to slow its asking down for either, because every attempt is paid
    /// for and none of them can ever succeed. Unlike
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

    static func colourisation(token: @escaping () -> String) -> ColourisationService {
        guard let base = apiBaseURL else { return StubColourisationService() }
        return RemoteColourisationService(baseURL: base, token: token)
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
        case .badStatus: String(localized: "Yhteys perheen palveluun ei onnistunut. Yritä hetken kuluttua uudelleen.")
        case .emptyResult: String(localized: "Puheesta ei saatu sanoja.")
        case .quotaExceeded(let kind, _, let limit):
            // Its own sentence, because the one about telling below would tell
            // somebody who was colouring a photograph that their voice is safe.
            kind == "colourisations"
                ? String(localized: "Tämän kuukauden väritykset on käytetty.")
                : kind == "photos"
                ? String(localized: "Ilmaisessa arkistossa on tilaa \(limit) kuvalle.")
                // "Litterointiaika", the meter's own name, as everywhere else
                // it is named (docs/ARCHITECTURE.md §21). Not "AI-minuutit",
                // which is jargon at the moment the limit stops somebody —
                // and, since 26 Sep 2026, not "kertomisaika" either: telling
                // is the act rule 2 says is never limited, and naming the
                // meter after it made the app say both at once.
                //
                // What is *not* said here matters as much: the telling itself
                // is safe. Rule 2 is that telling is never paywalled, and a
                // quota stops the writing-down rather than the voice.
                : String(localized: "Tämän kuukauden litterointiaika on käytetty. Äänesi on silti tallessa.")
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

/// The language being SPOKEN, as far as this app can tell from where it sits.
///
/// It decides which system prompt the Worker uses and which hallucination
/// ceiling applies to the transcript — see PLAN.md §10 and the constant in
/// backend/src/transcribe.ts. Both of those are calibrated per language and
/// neither can be got right by guessing at the far end.
///
/// The app's own resolved localisation is the closest available answer without
/// asking: a phone showing Finnish is a phone somebody chose Finnish on, and
/// whoever talks into it is overwhelmingly likely to be speaking it.
///
/// WHERE IT IS WRONG, said rather than hidden: an English-reading grandchild
/// holding the phone while a Finnish grandmother talks. The English prompt then
/// meets Finnish speech, asks for names "as they stand alone", and has no rule
/// about case endings — so "Ainon" and "Aino" become two people in the tree.
/// If that turns out to happen, the answer is to ask the teller which language
/// they are about to speak, not to guess harder here.
enum SpokenLanguage {
    static var current: String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("fi") == true ? "fi" : "en"
    }
}

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
        /// Which prompt to transcribe with, and which words-per-second ceiling
        /// to judge the result against. Finnish and English are not the same
        /// number of words for the same story.
        let lang: String
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
                seconds: Self.duration(of: audioURL),
                lang: SpokenLanguage.current
            ),
            timeout: Self.transcriptionTimeout(seconds: Self.duration(of: audioURL))
        )
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteError.emptyResult
        }
        return reply.text
    }

    /// How long to wait for the text. The comment on `post` says it — the
    /// transcription takes as long as the audio — and a fixed 180 s said the
    /// opposite: anything past a few minutes timed out on the client while the
    /// server went on transcribing and paying, and the catch-up then paid again
    /// (founder's-eye review, 3 Sep 2026, finding #20). A minute for the upload
    /// and the queue, then twice the length of the recording; never under the
    /// old 180 s, and capped at fifteen minutes, past which a dropped connection
    /// is the likelier story — and a timeout is "about the moment" to the
    /// catch-up, retried and not counted against the recording.
    static func transcriptionTimeout(seconds: Double?) -> TimeInterval {
        min(max(180, 60 + 2 * (seconds ?? 0)), 900)
    }

    /// Read from the file rather than the recorder's clock: if audio ever comes
    /// from somewhere other than our own recording, the duration is still right.
    private static func duration(of url: URL) -> Double? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }
}

// MARK: - Colourisation

struct RemoteColourisationService: ColourisationService {
    let baseURL: URL
    let token: () -> String

    private struct Request: Encodable {
        /// The framed photograph as a base64 JPEG, the one shape the Worker takes.
        let image: String
        /// Newest first.
        let told: [String]
        /// One of `ColourLock.ratios`; the Worker drops any other.
        let aspect: String
    }

    private struct Reply: Decodable {
        let image: String
    }

    func colourise(canvas: Data, told: [String], aspect: String) async throws -> Data {
        let reply: Reply = try await post(
            "colourise",
            baseURL: baseURL,
            token: token(),
            body: Request(image: canvas.base64EncodedString(), told: told, aspect: aspect),
            // Nine to thirteen seconds a round, measured 13 Sep 2026; the rest
            // is room for a slow upload from a cottage.
            timeout: 120
        )
        guard let data = Data(base64Encoded: reply.image), !data.isEmpty else {
            throw RemoteError.emptyResult
        }
        return data
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
        /// Which of the two system prompts structures this. Not the language
        /// the app is being READ in when those differ — see SpokenLanguage.
        let lang: String
        /// What the family's archive already holds. Omitted when it holds
        /// nothing relevant, so an empty archive costs no tokens and adds no
        /// instruction about a list that is not there.
        let context: ExtractionContext?
        /// The photograph the telling is about, base64 JPEG. Omitted for a
        /// telling that is not about one — a person, a place, free dictation.
        let image: String?

        struct Correction: Encodable {
            let from: String
            let to: String
        }
    }

    /// Mirrors the backend's `ExtractionResult`. Years travel as integers,
    /// because language models handle years reliably and unix timestamps not at
    /// all — the conversion happens here.
    ///
    /// Internal rather than private, and only so that
    /// `scripts/date-hint-check.swift` can hand `dateHint(from:)` a reply
    /// decoded from the JSON the Worker actually sends. The two siblings above
    /// stay private; widening this one buys a check on the field names as well
    /// as on the shaping, which is the half a hand-built value would miss.
    struct Reply: Decodable {
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

    /// How long to wait for the structure. The same mistake as the fixed 180 s
    /// above, one call later: a flat 90 s, while the reply writes the whole
    /// telling out again (rule 2 of the prompt forbids shortening it) and the
    /// Worker may try three times before answering. Ninety seconds is plenty
    /// for the demo's minute and a half and nothing like enough for half an
    /// hour, which the output ceilings in `budget.ts` now allow.
    ///
    /// A tenth of a second a word is an estimate, not a measurement: about
    /// three tokens a Finnish word, at a hundred tokens a second, three times
    /// over. Never under the old 90 s, capped where the transcription's is.
    static func extractionTimeout(transcript: String) -> TimeInterval {
        let words = transcript.split(whereSeparator: \.isWhitespace).count
        return min(max(90, 60 + 0.1 * Double(words)), 900)
    }

    func extract(
        transcript: String,
        corrections: [NameCorrection],
        level: Int?,
        context: ExtractionContext,
        photo: Data?
    ) async throws -> ExtractionResult {
        let reply: Reply = try await post(
            "extract",
            baseURL: baseURL,
            token: token(),
            body: Request(
                transcript: transcript,
                corrections: corrections.map { .init(from: $0.from, to: $0.to) },
                level: level,
                lang: SpokenLanguage.current,
                context: context.isEmpty ? nil : context,
                image: photo?.base64EncodedString()
            ),
            // The photograph rides on this call rather than a second one: the
            // extraction model is already multimodal, so the picture is input
            // tokens on a round that was going to happen anyway. Measured
            // 19 Sep 2026: a flat +1140 prompt tokens whatever the
            // resolution, and $0.0045 to $0.0061 for the round.
            timeout: Self.extractionTimeout(transcript: transcript)
        )

        return ExtractionResult(
            body: reply.body,
            mentions: reply.mentions.compactMap { mention in
                // An unknown kind is dropped rather than guessed as a person:
                // a wrong relative is worse than a missing one.
                guard let kind = SubjectKind(rawValue: mention.kind) else { return nil }
                // And a name that is not one. Every entry here becomes a
                // `subject` row — `findOrCreateSubject` takes what it is
                // handed — so an empty name is a person the family is asked
                // to confirm, drawn as "Henkilö" because `displayTitle` falls
                // back to the kind. The trim is the half with teeth: "Aino "
                // and "Aino" are two titles to the comparison that decides
                // whether a name is somebody already here, so a stray space
                // is a duplicate card by another road.
                //
                // `normaliseMentions` in extract.ts does this too, and this
                // is not that guard repeated for tidiness. The Worker is
                // deployed on its own schedule and the app is built against
                // whichever version happens to be live — on 12 Sep 2026 that
                // was six days behind the repository. A client that only
                // holds when the server is current is a client that does not
                // hold.
                let name = mention.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return MentionedEntity(
                    name: name,
                    kind: kind,
                    confidence: mention.confidence
                )
            },
            dateHint: Self.dateHint(from: reply.date),
            questions: reply.questions.map { ExtractedQuestion(text: $0.text, level: $0.level) }
        )
    }

    /// What the telling is allowed to claim about when it happened.
    ///
    /// The reply carries `start_year` and `end_year` and nothing finer, while
    /// its `precision` may say "day" or "month" — the enum in `extract.ts` has
    /// carried those two from the first. A model that heard "kesäkuussa 1957"
    /// therefore answered month 1957, and this built the first of January and
    /// stored it as a month: the card then read *tammikuu 1957* as fact, a
    /// month nobody had said, and a day precision read *1.1.1957* the same way.
    /// Rule 5 is that uncertainty is stored rather than rounded, and this was
    /// the opposite — a coarse answer sharpened into a false one.
    ///
    /// So the stored precision is the precision of the data that arrived. The
    /// family sharpens it by hand in `DateSheet`, where somebody who was there
    /// chooses the month and the day, which is rule 4's shape as well: the
    /// model proposes the year it heard, a person adds what it could not hear.
    ///
    /// Internal rather than private, so that `scripts/date-hint-check.swift`
    /// can drive this function itself rather than a copy of it.
    static func dateHint(from reply: Reply.DateReply) -> DateHint? {
        guard let precision = DatePrecision(rawValue: reply.precision), precision != .unknown else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateHint.zone

        func date(_ year: Int?) -> Date? {
            guard let year else { return nil }
            return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }

        // A precision with no year behind it is not a date at all, and storing
        // one is worse than storing nothing: `date_precision` is the signal
        // sync reads as "this device has something to say about the date", so
        // an empty hint pushed from here clears a date another phone had.
        guard let start = date(reply.start_year) else { return nil }

        return DateHint(
            start: start,
            end: date(reply.end_year),
            precision: precision == .day || precision == .month ? .year : precision
        )
    }
}
