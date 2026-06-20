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

    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != "YOUR_KEY_HERE" && apiKey != "$(NEIS_API_KEY)"
    }

    func request(path: String, query: [String: String]) async throws -> Data {
        guard isConfigured else {
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
        NEISDebugLog.request(path: path, url: url)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw NEISClientError.invalidResponse }
        NEISDebugLog.response(path: path, statusCode: http.statusCode, byteCount: data.count)
        guard (200..<300).contains(http.statusCode) else { throw NEISClientError.serverStatus(http.statusCode) }
        return data
    }
}

enum NEISDebugLog {
    static func request(path: String, url: URL) {
        #if DEBUG
        print("[NEIS] GET \(path) \(redacted(url: url))")
        #endif
    }

    static func response(path: String, statusCode: Int, byteCount: Int) {
        #if DEBUG
        print("[NEIS] RESPONSE \(path) status=\(statusCode) bytes=\(byteCount)")
        #endif
    }

    static func info(_ message: String) {
        #if DEBUG
        print("[NEIS] \(message)")
        #endif
    }

    private static func redacted(url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            item.name == "KEY" ? URLQueryItem(name: item.name, value: "<redacted>") : item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}
