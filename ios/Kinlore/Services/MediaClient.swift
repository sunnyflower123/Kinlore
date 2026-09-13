import Foundation

/// Transferring photos and audio to R2 through the Worker.
struct MediaClient {
    let baseURL: URL
    let token: String

    enum Kind: String {
        case photo, audio
        /// A photograph's confirmed colours, stored beside it (`media.ts`).
        case colour
    }

    private struct UploadReply: Decodable {
        let key: String
    }

    func upload(data: Data, kind: Kind) async throws -> String {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("media"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // A photo can be a megabyte and the network at a cottage slow. A short
        // timeout would abandon the upload exactly when it is slowest.
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (replyData, response) = try await URLSession.shared.upload(for: request, from: data)
        try Self.check(response, data: replyData)
        return try JSONDecoder().decode(UploadReply.self, from: replyData).key
    }

    func download(key: String) async throws -> Data {
        let encoded = key
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        guard let url = URL(string: "media/\(encoded)", relativeTo: baseURL) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    /// The server's quota response, decoded here as `AppServices` decodes it,
    /// because a 402 is the one refusal that is an answer rather than an
    /// outage: the free tier's photo ceiling. It used to come back as the same
    /// bare `URLError` as a dead network, and `try?` upstream swallowed both —
    /// so the 21st photograph looked normal in the grid and silently never
    /// reached the family. See docs/UX.md §9 and `SyncEngine`.
    private struct QuotaDenial: Decodable {
        let kind: String
        let used: Int
        let limit: Int
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 402,
           let denial = try? JSONDecoder().decode(QuotaDenial.self, from: data) {
            throw RemoteError.quotaExceeded(kind: denial.kind, used: denial.used, limit: denial.limit)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
