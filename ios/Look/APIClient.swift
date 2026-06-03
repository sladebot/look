import Foundation

class APIClient {
    static let shared = APIClient()

    #if targetEnvironment(simulator)
    private let defaultBaseURL = "http://127.0.0.1:8765"
    #else
    private let defaultBaseURL = "http://10.0.0.151:8765"
    #endif

    private var activeBaseURL: String?
    var baseURL: String {
        activeBaseURL ?? configuredBaseURL
    }

    private var decoder: JSONDecoder { JSONDecoder() }

    private var configuredBaseURL: String {
        let saved = UserDefaults.standard.string(forKey: "server_url")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false ? saved! : defaultBaseURL
    }

    private var baseURLCandidates: [String] {
        [
            configuredBaseURL,
            defaultBaseURL,
            "http://127.0.0.1:8765",
            "http://localhost:8765",
            "http://10.0.0.151:8765",
        ].reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }

    // MARK: - Health

    func health() async throws -> HealthResponse {
        try await get("/api/health")
    }

    func importPhotos(path: String? = nil) async throws -> ImportResponse {
        if let path {
            return try await post("/api/import?path=\(encode(path))")
        }
        return try await post("/api/import")
    }

    // MARK: - Photos

    func photos(limit: Int = 50, offset: Int = 0, tag: String? = nil,
                camera: String? = nil, query: String? = nil) async throws -> PhotoListResponse {
        var params = "limit=\(limit)&offset=\(offset)"
        if let t = tag { params += "&tag=\(encode(t))" }
        if let c = camera { params += "&camera=\(encode(c))" }
        if let q = query { params += "&q=\(encode(q))" }
        return try await get("/api/photos?\(params)")
    }

    func photoDetail(_ id: String) async throws -> Photo {
        try await get("/api/photos/\(id)")
    }

    func thumbnailURL(for photoId: String, size: Int = 256) -> URL {
        URL(string: "\(baseURL)/api/thumbnails/\(photoId)?size=\(size)")!
    }

    func fullImageURL(for photoId: String) -> URL {
        URL(string: "\(baseURL)/api/full/\(photoId)")!
    }

    // MARK: - Albums

    func albums() async throws -> [Album] {
        let response: AlbumListResponse = try await get("/api/albums")
        return response.albums
    }

    func albumDetail(_ id: String) async throws -> Album {
        try await get("/api/albums/\(id)")
    }

    // MARK: - Smart Collections

    func smartCollections() async throws -> SmartCollectionsResponse {
        try await get("/api/smart-collections")
    }

    func smartCollectionDetail(_ id: String) async throws -> SmartCollection {
        try await get("/api/smart-collections/\(id)")
    }

    // MARK: - Tags

    func photoTags(_ photoId: String) async throws -> TagListResponse {
        try await get("/api/photos/\(photoId)/tags")
    }

    func addTag(_ photoId: String, tag: String) async throws -> GenericStatusResponse {
        try await post("/api/photos/\(photoId)/tags?tag=\(encode(tag))")
    }

    @discardableResult
    func removeTag(_ photoId: String, tag: String) async throws -> GenericStatusResponse {
        try await delete("/api/photos/\(photoId)/tags/\(encode(tag))")
    }

    func autoTag(_ photoId: String) async throws -> AutoTagResponse {
        try await post("/api/photos/\(photoId)/tags/auto")
    }

    func tagSuggestions(_ photoId: String) async throws -> TagSuggestResponse {
        try await get("/api/photos/\(photoId)/tags/suggest")
    }

    func allTags() async throws -> AllTagsResponse {
        try await get("/api/tags")
    }

    // MARK: - Search

    func search(query: String) async throws -> PhotoListResponse {
        try await get("/api/search?q=\(encode(query))&limit=50")
    }

    // MARK: - HTTP helpers

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET")
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "POST")
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "DELETE")
    }

    private func request<T: Decodable>(_ path: String, method: String) async throws -> T {
        var lastError: Error?

        for candidate in baseURLCandidates {
            guard let url = URL(string: "\(candidate)\(path)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 8

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    throw APIError.httpError(httpResp.statusCode)
                }
                let decoded = try decoder.decode(T.self, from: data)
                activeBaseURL = candidate
                return decoded
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.httpError(0)
    }
}

enum APIError: LocalizedError {
    case httpError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Server error (\(code))"
        case .decodingError(let msg): return "Data error: \(msg)"
        }
    }
}
