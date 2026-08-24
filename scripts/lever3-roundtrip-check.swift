// The round trip PLAN.md §10 lever 3 names as "the test to run the day it is
// deployed": two identities, a real Worker, and a sealed memory that crosses
// between them — with the family key travelling only in the invite text.
//
// family-crypto-check proves the crypto in isolation; this proves the claim
// the crypto exists for. What the server stores is read back raw and checked
// for the marker and for the absence of every told word, and then opened with
// the key the second device took out of the invitation — the same two
// transforms the app runs, `SyncPayload.sealed` and `SyncPullReply.opened`,
// not a re-implementation of them.
//
// The sealing is the app's; the transport around it is not. The harness
// re-spells FamilyKey's base64url shuffle (the real one lives in the
// Keychain), the invite text's composition and parsing (InviteShare's
// `code#key` and Session.split), and the HTTP calls (SyncClient pulls in the
// whole app). So the shuffle assertion below is a self-check — it proves the
// harness's own two halves agree, and a drift in the app's FamilyKey would
// not fail here. What the app-side halves get instead is their own coverage:
// family-crypto-check for the crypto, the join tests for the invite text.
//
// Needs a running Worker, and leaves one throwaway family behind:
//
//   npx wrangler dev                  # or nothing, against production
//   swiftc -parse-as-library -o /tmp/lever3-roundtrip-check \
//     scripts/lever3-roundtrip-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
//     ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift \
//     && /tmp/lever3-roundtrip-check http://localhost:8787
//
// First production run: 24 Aug 2026, the day the Worker deployed.

import CryptoKit
import Foundation

@main
enum Lever3RoundTripCheck {
    static var failures = 0

    static func check(_ label: String, _ passed: Bool, _ detail: String = "") {
        if passed {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func main() async {
        let api = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "http://localhost:8787"
        guard let base = URL(string: api) else {
            print("  FAIL not a URL: \(api)")
            exit(1)
        }

        // Two phones. The names echo the check scripts' household.
        let ville = Device(name: "Ville")
        let aino = Device(name: "Aino")

        // The words under test — distinct enough that finding one in a stored
        // row could only mean it crossed in clear.
        let title = "Mökki Puumalassa"
        let body = "Aino tuli mökille joka kesä, ja rannassa puhuttiin sodan jälkeisistä vuosista."
        let transcript = "no niin, Aino tuli mökille joka kesä ja sitten rannassa istuttiin"
        let questionText = "Millainen ranta mökillä oli?"
        let words = ["Aino", "mökille", "Puumalassa", "rannassa", "ranta"]
        // Recognisable audio: an m4a-shaped head so the ftyp check means
        // something, and a marker no sealed byte stream may carry.
        var audio = Data([0x00, 0x00, 0x00, 0x20]) + Data("ftypM4A MEMORYAUDIO".utf8)
        audio.append(Data((0 ..< 2048).map { UInt8($0 % 251) }))

        do {
            // --- Device A: found the family, hold the key ---------------------
            let key = SymmetricKey(size: .bits256)
            try await post(base, "/family", [
                "memberID": ville.memberID, "secret": ville.secret, "displayName": ville.name,
            ])
            let invite = try await post(base, "/family/invite", [:], auth: ville.token)
            guard let code = invite["code"] as? String else {
                throw Failure("the invite came back without a code")
            }

            // The invite text, spelled the way InviteShare spells it — and the
            // shuffle checked against itself before anything depends on it.
            let inviteText = "\(code)#\(shareable(key))"
            check(
                "the key survives its trip through the invite text",
                adopt(String(inviteText.split(separator: "#")[1])) == key.raw
            )

            // --- Device A: seal with the app's own transform, push, upload ---
            let sealedAudio = FamilyCrypto.seal(audio, with: key)!
            let audioKey = try await upload(base, sealedAudio, kind: "audio", auth: ville.token)

            let now = Date().timeIntervalSince1970
            let subjectID = UUID().uuidString
            var payload = SyncPayload()
            payload.subjects = [SubjectDTO(
                id: subjectID, kind: "event", title: title, r2_key: nil,
                lat: nil, lon: nil, geo_precision: nil,
                date_start: nil, date_end: nil, date_precision: nil,
                confirmed: 1, merged_into: nil, created_at: now,
                deleted_at: nil, seq: nil
            )]
            payload.memories = [MemoryDTO(
                id: UUID().uuidString, subject_id: subjectID,
                author_id: nil, author_name: nil, body: body,
                raw_transcript: transcript, audio_r2_key: audioKey,
                audio_seconds: 12, source: "voice", mentions: nil,
                created_at: now, deleted_at: nil, seq: nil
            )]
            payload.questions = [QuestionDTO(
                id: UUID().uuidString, subject_id: subjectID, text: questionText,
                level: nil, status: "open", created_at: now,
                deleted_at: nil, seq: nil, author_id: nil, author_name: nil
            )]
            let sealed = payload.sealed(with: key)
            try await push(base, sealed, auth: ville.token)

            // --- Device B: join with the code, take the key from the text ----
            let parts = inviteText.split(separator: "#")
            try await post(base, "/family/join", [
                "memberID": aino.memberID, "secret": aino.secret,
                "displayName": aino.name, "code": String(parts[0]),
            ])
            guard let adopted = adopt(String(parts[1])) else {
                throw Failure("the invite text did not yield a key")
            }
            let keyB = SymmetricKey(data: adopted)

            // --- What the server stored, read back raw ------------------------
            let raw = try await pull(base, auth: aino.token)
            guard let storedSubject = raw.subjects.first(where: { $0.id == subjectID }),
                  let storedMemory = raw.memories.first,
                  let storedQuestion = raw.questions.first
            else { throw Failure("the pull came back without the pushed rows") }

            let stored = [
                storedSubject.title ?? "", storedMemory.body,
                storedMemory.raw_transcript ?? "", storedQuestion.text,
            ]
            check(
                "every stored text carries the seal",
                stored.allSatisfy { $0.hasPrefix(FamilyCrypto.marker) }
            )
            check(
                "and none of the told words reached the server",
                words.allSatisfy { word in stored.allSatisfy { !$0.contains(word) } }
            )

            // --- And opened with the travelled key, on the other phone -------
            let opened = raw.opened(with: keyB)
            check("the title opens to the same words", opened.subjects
                .first(where: { $0.id == subjectID })?.title == title)
            check("the body opens to the same words", opened.memories.first?.body == body)
            check("the raw transcript opens too", opened.memories.first?.raw_transcript == transcript)
            check("the question opens too", opened.questions.first?.text == questionText)

            // --- The audio makes the same trip through R2 ---------------------
            let fetched = try await download(base, key: audioKey, auth: aino.token)
            check(
                "the R2 bytes travel sealed",
                // dropFirst(4): ftyp sits after the four-byte box size in the
                // fixture, as in a real m4a. This said 3 briefly — the length
                // of "k1.", a different offset — and the clause could then
                // never fail; the audit caught it on day one. The second
                // conjunct does the load-bearing work either way: open() is
                // identity on unmarked data, so plaintext bytes come back
                // equal and fail the check.
                !fetched.dropFirst(4).starts(with: Data("ftyp".utf8))
                    && FamilyCrypto.open(fetched, with: keyB) != fetched
            )
            check(
                "no marker of the recording is left in the open",
                subrange(of: Data("MEMORYAUDIO".utf8), in: fetched) == nil
            )
            check("and open byte for byte on the second phone",
                  FamilyCrypto.open(fetched, with: keyB) == audio)
        } catch {
            failures += 1
            print("  FAIL \(error.localizedDescription)")
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - The invite's key spelling (mirrors FamilyKey in Identity.swift)

    /// FamilyKey.shareable, minus the Keychain: base64url without padding.
    static func shareable(_ key: SymmetricKey) -> String {
        key.raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// FamilyKey.adopt, minus the Keychain: refuse anything but 32 bytes.
    static func adopt(_ shared: String) -> Data? {
        var value = shared
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        guard let data = Data(base64Encoded: value), data.count == 32 else { return nil }
        return data
    }

    // MARK: - Plumbing

    struct Device {
        let name: String
        let memberID = UUID().uuidString
        let secret = UUID().uuidString + UUID().uuidString
        var token: String { "\(memberID).\(secret)" }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func request(
        _ base: URL, _ path: String, method: String = "GET",
        body: Data? = nil, contentType: String? = nil, auth: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let auth { request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Failure("\(method) \(path) answered \(status)")
        }
        return data
    }

    @discardableResult
    static func post(
        _ base: URL, _ path: String, _ body: [String: String], auth: String? = nil
    ) async throws -> [String: Any] {
        let data = try await request(
            base, path, method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json", auth: auth
        )
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func push(_ base: URL, _ payload: SyncPayload, auth: String) async throws {
        _ = try await request(
            base, "/sync", method: "POST", body: try JSONEncoder().encode(payload),
            contentType: "application/json", auth: auth
        )
    }

    static func pull(_ base: URL, auth: String) async throws -> SyncPullReply {
        var components = URLComponents(
            url: base.appendingPathComponent("sync"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "since", value: "0")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure("GET /sync answered \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode(SyncPullReply.self, from: data)
    }

    static func upload(
        _ base: URL, _ data: Data, kind: String, auth: String
    ) async throws -> String {
        var components = URLComponents(
            url: base.appendingPathComponent("media"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "kind", value: kind)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        let (reply, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure("POST /media answered \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        struct UploadReply: Decodable { let key: String }
        return try JSONDecoder().decode(UploadReply.self, from: reply).key
    }

    static func download(_ base: URL, key: String, auth: String) async throws -> Data {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        return try await request(base, "media/\(encoded)", auth: auth)
    }

    static func subrange(of needle: Data, in haystack: Data) -> Range<Data.Index>? {
        haystack.range(of: needle)
    }
}

extension SymmetricKey {
    /// The key's bytes, for comparing what the invite text carried against
    /// what was generated. The app never needs this; the harness does.
    var raw: Data { withUnsafeBytes { Data($0) } }
}
