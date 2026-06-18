import Foundation

enum NEISClientError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case serverStatus(Int)
}

struct NEISClient {
    var apiKey: String
    var baseURL: URL
    var session: URLSession

    init(
        apiKey: String = Bundle.main.object(forInfoDictionaryKey: "NEIS_API_KEY") as? String ?? "",
        baseURL: URL = URL(string: "https://open.neis.go.kr/hub")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.session = session
    }

    func request(path: String, query: [String: String]) async throws -> Data {
        guard !apiKey.isEmpty, apiKey != "YOUR_KEY_HERE", apiKey != "$(NEIS_API_KEY)" else {
            throw NEISClientError.missingAPIKey
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "KEY", value: apiKey),
            URLQueryItem(name: "Type", value: "json"),
            URLQueryItem(name: "pIndex", value: "1"),
            URLQueryItem(name: "pSize", value: "100")
        ]
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        components?.queryItems = items

        guard let url = components?.url else { throw NEISClientError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw NEISClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NEISClientError.serverStatus(http.statusCode) }
        return data
    }
}

