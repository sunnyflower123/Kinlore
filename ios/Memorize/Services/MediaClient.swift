import Foundation

/// Kuvien ja äänten siirto R2:een Workerin kautta.
struct MediaClient {
    let baseURL: URL
    let token: String

    enum Kind: String {
        case photo, audio
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
        // Kuva voi olla megatavu ja verkko mökillä hidas. Lyhyt aikakatkaisu
        // hylkäisi latauksen juuri silloin kun se on hitaimmillaan.
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (replyData, response) = try await URLSession.shared.upload(for: request, from: data)
        try Self.check(response)
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
        try Self.check(response)
        return data
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
