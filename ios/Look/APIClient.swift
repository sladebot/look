import Foundation
import Security

/// Networking layer for the Look server.
///
/// Tailscale: the app talks plain HTTP to a self-hosted server on a private
/// tailnet. App Transport Security allows local networking and insecure HTTP
/// loads for Tailscale MagicDNS `*.ts.net` names (see Info.plist), so a
/// `100.x.y.z:PORT` address or a `machine.tailnet.ts.net:PORT` MagicDNS name
/// entered in Settings works directly. When the user has set an explicit server
/// URL we treat it as authoritative and do NOT silently fall back to
/// LAN/localhost guesses (a fallback on a tailnet just hides typos and can
/// cache the wrong server). First-run defaults to the MagicDNS URL.
class APIClient {
    static let shared = APIClient()

    private let defaultBaseURL = "http://studio.taila3f2b.ts.net:5678"
    private static let apiKeyStorageKey = "api_key"
    private static let legacyAPIKeyDefaultsKey = "api_key"
    private static let invalidDisplayURL = URL(fileURLWithPath: "/dev/null")

    /// Cached base URL that last produced a successful response.
    private var activeBaseURL: String?

    var baseURL: String { activeBaseURL ?? configuredBaseURL }

    private var decoder: JSONDecoder { JSONDecoder() }

    var configuredBaseURL: String {
        let saved = UserDefaults.standard.string(forKey: "server_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved, !saved.isEmpty else { return defaultBaseURL }
        return (try? Self.normalizedBaseURLString(from: saved)) ?? saved
    }

    init() {
        migrateLegacyAPIKeyIfNeeded()
    }

    /// Optional API key. Sent as `X-API-Key` on every request so write
    /// endpoints work when the server has `API_KEY` configured.
    private var apiKey: String? {
        let key = storedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    var storedAPIKey: String {
        KeychainStore.string(forKey: Self.apiKeyStorageKey) ?? ""
    }

    @discardableResult
    func saveAPIKey(_ value: String) -> Bool {
        KeychainStore.setString(value, forKey: Self.apiKeyStorageKey)
    }

    func migrateLegacyAPIKeyIfNeeded() {
        KeychainStore.migrateUserDefaultsString(
            forKey: Self.legacyAPIKeyDefaultsKey,
            toKeychainKey: Self.apiKeyStorageKey
        )
    }

    /// True when the user explicitly configured a server URL.
    private var hasExplicitServerURL: Bool {
        let saved = UserDefaults.standard.string(forKey: "server_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false
    }

    /// Candidate base URLs to try, in order. When the user configured a URL we
    /// use only that (authoritative). Otherwise we use the Tailscale default.
    private var baseURLCandidates: [String] {
        if hasExplicitServerURL {
            return [configuredBaseURL]
        }
        return [defaultBaseURL]
    }

    // MARK: - Health

    func health() async throws -> HealthResponse { try await get("/api/health") }

    // MARK: - Import / Sync

    /// Submit a background import. Returns a task envelope to poll.
    func importPhotos(path: String? = nil) async throws -> ImportSubmitResponse {
        var p = "/api/import?background=true"
        if let path { p += "&path=\(encode(path))" }
        return try await request(p, method: "POST")
    }

    /// Synchronous import (blocks until done). Used as a fallback.
    func importPhotosSync(path: String? = nil) async throws -> ImportResponse {
        var p = "/api/import?background=false"
        if let path { p += "&path=\(encode(path))" }
        return try await request(p, method: "POST", timeout: 120)
    }

    // MARK: - Photos

    func photos(limit: Int = 50, offset: Int = 0, album: String? = nil, tag: String? = nil,
                camera: String? = nil, query: String? = nil) async throws -> PhotoListResponse {
        var params = "limit=\(limit)&offset=\(offset)"
        if let a = album { params += "&album=\(encode(a))" }
        if let t = tag { params += "&tag=\(encode(t))" }
        if let c = camera { params += "&camera=\(encode(c))" }
        if let q = query { params += "&q=\(encode(q))" }
        return try await get("/api/photos?\(params)")
    }

    func photoDetail(_ id: String) async throws -> Photo { try await get("/api/photos/\(id)") }

    func thumbnailURL(for photoId: String, size: Int = 256) -> URL {
        (try? Self.thumbnailURL(baseURL: baseURL, photoId: photoId, size: size)) ?? Self.invalidDisplayURL
    }

    func fullImageURL(for photoId: String) -> URL {
        (try? Self.fullImageURL(baseURL: baseURL, photoId: photoId)) ?? Self.invalidDisplayURL
    }

    func downloadJPEGData(_ photoId: String) async throws -> Data {
        try await fetchData("/api/download/jpeg/\(Self.encodePathComponent(photoId))")
    }

    func downloadRawData(_ photoId: String) async throws -> Data {
        try await fetchData("/api/download/raw/\(Self.encodePathComponent(photoId))")
    }

    // MARK: - Albums

    func albums() async throws -> [Album] {
        let response: AlbumListResponse = try await get("/api/albums")
        return response.albums
    }

    func albumDetail(_ id: String) async throws -> Album { try await get("/api/albums/\(id)") }

    @discardableResult
    func createAlbum(name: String, description: String = "") async throws -> CreateAlbumResponse {
        try await request("/api/albums?name=\(encode(name))&description=\(encode(description))", method: "POST")
    }

    @discardableResult
    func updateAlbum(_ id: String, name: String? = nil, description: String? = nil) async throws -> GenericStatusResponse {
        var params: [String] = []
        if let name { params.append("name=\(encode(name))") }
        if let description { params.append("description=\(encode(description))") }
        let query = params.isEmpty ? "" : "?" + params.joined(separator: "&")
        return try await request("/api/albums/\(id)\(query)", method: "PUT")
    }

    @discardableResult
    func deleteAlbum(_ id: String) async throws -> GenericStatusResponse {
        try await request("/api/albums/\(id)", method: "DELETE")
    }

    @discardableResult
    func addPhotoToAlbum(albumId: String, photoId: String) async throws -> GenericStatusResponse {
        try await request("/api/albums/\(albumId)/photos/\(photoId)", method: "POST")
    }

    @discardableResult
    func removePhotoFromAlbum(albumId: String, photoId: String) async throws -> GenericStatusResponse {
        try await request("/api/albums/\(albumId)/photos/\(photoId)", method: "DELETE")
    }

    // MARK: - Smart Collections

    func smartCollections() async throws -> SmartCollectionsResponse { try await get("/api/smart-collections") }

    func smartCollectionDetail(_ id: String) async throws -> SmartCollection {
        try await get("/api/smart-collections/\(id)")
    }

    @discardableResult
    func createSmartCollection(name: String, description: String = "", ruleSpec: String) async throws -> CreateAlbumResponse {
        try await request("/api/smart-collections?name=\(encode(name))&description=\(encode(description))&rule_spec=\(encode(ruleSpec))", method: "POST")
    }

    @discardableResult
    func evalSmartCollection(_ id: String) async throws -> GenericStatusResponse {
        try await request("/api/smart-collections/\(id)/eval", method: "POST")
    }

    @discardableResult
    func deleteSmartCollection(_ id: String) async throws -> GenericStatusResponse {
        try await request("/api/smart-collections/\(id)", method: "DELETE")
    }

    // MARK: - Tags

    func photoTags(_ photoId: String) async throws -> TagListResponse {
        try await get("/api/photos/\(photoId)/tags")
    }

    @discardableResult
    func addTag(_ photoId: String, tag: String) async throws -> TagListResponse {
        try await request("/api/photos/\(photoId)/tags?tag=\(encode(tag))", method: "POST")
    }

    @discardableResult
    func removeTag(_ photoId: String, tag: String) async throws -> GenericStatusResponse {
        try await request("/api/photos/\(photoId)/tags/\(encode(tag))", method: "DELETE")
    }

    func autoTag(_ photoId: String) async throws -> AutoTagResponse {
        try await request("/api/photos/\(photoId)/tags/auto", method: "POST")
    }

    func tagSuggestions(_ photoId: String) async throws -> TagSuggestResponse {
        try await get("/api/photos/\(photoId)/tags/suggest")
    }

    func tagHistory(_ photoId: String) async throws -> TagHistoryResponse {
        try await get("/api/photos/\(photoId)/tags/history")
    }

    func allTags() async throws -> AllTagsResponse { try await get("/api/tags") }

    @discardableResult
    func mergeTags(source: String, target: String) async throws -> GenericStatusResponse {
        try await request("/api/tags/merge?source=\(encode(source))&target=\(encode(target))", method: "POST")
    }

    func duplicateTagSuggestions() async throws -> DuplicateTagsResponse {
        try await get("/api/tags/suggest")
    }

    // MARK: - Search

    func search(query: String) async throws -> SearchResponse {
        try await get("/api/search?q=\(encode(query))&limit=50")
    }

    // MARK: - Settings

    func settings() async throws -> SettingsResponse { try await get("/api/settings") }

    @discardableResult
    func putSetting(key: String, value: String) async throws -> GenericStatusResponse {
        try await request("/api/settings/\(encode(key))?value=\(encode(value))", method: "PUT")
    }

    /// Typed boolean toggles (dedicated endpoints with their own config side-effects).
    @discardableResult
    func putBoolSetting(_ key: String, _ value: Bool) async throws -> GenericStatusResponse {
        try await request("/api/settings/\(key)?value=\(value)", method: "PUT")
    }

    // MARK: - Dedup

    func dedupSettings() async throws -> DedupSettingsResponse { try await get("/api/dedup/settings") }

    @discardableResult
    func updateDedupSettings(enabled: Bool? = nil, tolerance: Int? = nil) async throws -> DedupSettingsUpdateResponse {
        var params: [String] = []
        if let enabled { params.append("enabled=\(enabled)") }
        if let tolerance { params.append("tolerance=\(tolerance)") }
        let query = params.isEmpty ? "" : "?" + params.joined(separator: "&")
        return try await request("/api/dedup/settings\(query)", method: "PUT")
    }

    func submitDedupScan() async throws -> TaskSubmitResponse {
        try await request("/api/dedup/scan", method: "POST")
    }

    @discardableResult
    func mergeDuplicates(groupId: Int, keepPhotoId: String) async throws -> GenericStatusResponse {
        try await request("/api/dedup/merge?group_id=\(groupId)&keep_photo_id=\(encode(keepPhotoId))", method: "POST")
    }

    // MARK: - Tasks

    func tasks(limit: Int = 50, offset: Int = 0) async throws -> TaskListResponse {
        try await get("/api/tasks?limit=\(limit)&offset=\(offset)")
    }

    func task(_ id: String) async throws -> TaskInfo { try await get("/api/tasks/\(id)") }

    @discardableResult
    func cancelTask(_ id: String) async throws -> GenericStatusResponse {
        try await request("/api/tasks/\(id)/cancel", method: "POST")
    }

    // MARK: - Watch list

    func watchList() async throws -> WatchListResponse { try await get("/api/watch-list") }

    @discardableResult
    func addWatchDir(_ path: String) async throws -> GenericStatusResponse {
        try await request("/api/watch-list?path=\(encode(path))", method: "POST")
    }

    @discardableResult
    func removeWatchDir(_ path: String) async throws -> GenericStatusResponse {
        try await request("/api/watch-list/\(encodePathComponent(path))", method: "DELETE")
    }

    @discardableResult
    func setWatchActive(_ path: String, active: Bool) async throws -> GenericStatusResponse {
        try await request("/api/watch-list/\(encodePathComponent(path))/active?active=\(active)", method: "PATCH")
    }

    @discardableResult
    func updateWatchDir(_ path: String, newPath: String, active: Bool? = nil) async throws -> GenericStatusResponse {
        var query = "new_path=\(encode(newPath))"
        if let active { query += "&active=\(active)" }
        return try await request("/api/watch-list/\(encodePathComponent(path))?\(query)", method: "PATCH")
    }

    // MARK: - Geo

    func nearbyPhotos(lat: Double, lon: Double, radiusKm: Double = 5.0,
                      limit: Int = 50, offset: Int = 0) async throws -> NearbyResponse {
        try await get("/api/photos/nearby?lat=\(lat)&lon=\(lon)&radius_km=\(radiusKm)&limit=\(limit)&offset=\(offset)")
    }

    // MARK: - Migrations

    func migrationStatus() async throws -> MigrationStatusResponse { try await get("/api/migrate") }

    @discardableResult
    func runMigrations() async throws -> MigrationApplyResponse {
        try await request("/api/migrate", method: "POST")
    }

    @discardableResult
    func rollbackMigrations(targetVersion: Int) async throws -> GenericStatusResponse {
        try await request("/api/migrate/rollback?target_version=\(targetVersion)", method: "POST")
    }

    // MARK: - HTTP helpers

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func encodePathComponent(_ s: String) -> String {
        Self.encodePathComponent(s)
    }

    private static func encodePathComponent(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func normalizedBaseURLString(from rawValue: String) throws -> String {
        let url = try normalizedBaseURL(from: rawValue)
        return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func endpointURL(baseURL rawBaseURL: String, path rawPath: String) throws -> URL {
        let base = try normalizedBaseURL(from: rawBaseURL)
        guard rawPath.hasPrefix("/") else {
            throw APIError.invalidEndpointURL(baseURL: rawBaseURL, path: rawPath)
        }

        let pieces = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawEndpointPath = pieces.first, !rawEndpointPath.isEmpty else {
            throw APIError.invalidEndpointURL(baseURL: rawBaseURL, path: rawPath)
        }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let basePath = components?.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = String(rawEndpointPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.percentEncodedPath = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components?.percentEncodedQuery = pieces.count > 1 ? String(pieces[1]) : nil

        guard let url = components?.url else {
            throw APIError.invalidEndpointURL(baseURL: rawBaseURL, path: rawPath)
        }
        return url
    }

    static func thumbnailURL(baseURL: String, photoId: String, size: Int = 256) throws -> URL {
        try endpointURL(
            baseURL: baseURL,
            path: "/api/thumbnails/\(encodePathComponent(photoId))?size=\(size)"
        )
    }

    static func fullImageURL(baseURL: String, photoId: String) throws -> URL {
        try endpointURL(baseURL: baseURL, path: "/api/full/\(encodePathComponent(photoId))")
    }

    private static func normalizedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.invalidBaseURL(rawValue)
        }

        let valueWithScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: valueWithScheme),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw APIError.invalidBaseURL(rawValue)
        }

        components.scheme = scheme
        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }

        guard let url = components.url else {
            throw APIError.invalidBaseURL(rawValue)
        }
        return url
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET")
    }

    private func request<T: Decodable>(_ path: String, method: String, timeout: TimeInterval = 12) async throws -> T {
        let data = try await rawRequest(path, method: method, timeout: timeout)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(String(describing: error))
        }
    }

    /// Fetch raw bytes (downloads). Honors the same candidate/auth logic.
    private func fetchData(_ path: String, timeout: TimeInterval = 60) async throws -> Data {
        try await rawRequest(path, method: "GET", timeout: timeout)
    }

    /// Core request: tries each candidate base URL until one succeeds, caches it,
    /// and attaches the API key header when configured.
    private func rawRequest(_ path: String, method: String, timeout: TimeInterval) async throws -> Data {
        var lastError: APIError?
        let candidates = activeBaseURL.map { [$0] + baseURLCandidates.filter { c in c != activeBaseURL } } ?? baseURLCandidates

        for candidate in candidates {
            let url: URL
            do {
                url = try Self.endpointURL(baseURL: candidate, path: path)
            } catch let apiErr as APIError {
                lastError = apiErr
                if hasExplicitServerURL { throw apiErr }
                continue
            } catch {
                let apiErr = APIError.transportError(error)
                lastError = apiErr
                continue
            }

            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = timeout
            if let apiKey { req.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    // A 4xx/5xx is a real server answer — don't keep probing other hosts.
                    activeBaseURL = (try? Self.normalizedBaseURLString(from: candidate)) ?? candidate
                    throw APIError.httpError(http.statusCode)
                }
                activeBaseURL = (try? Self.normalizedBaseURLString(from: candidate)) ?? candidate
                return data
            } catch let apiErr as APIError {
                throw apiErr
            } catch {
                lastError = APIError.transportError(error)
            }
        }
        throw lastError ?? APIError.networkUnavailable("Unable to reach the Look server")
    }
}

enum APIError: LocalizedError {
    case httpError(Int)
    case decodingError(String)
    case invalidBaseURL(String)
    case invalidEndpointURL(baseURL: String, path: String)
    case offline
    case networkUnavailable(String)
    case timedOut
    case cancelled
    case transport(String)

    static func transportError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }

        guard let urlError = error as? URLError else {
            return .transport(error.localizedDescription)
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return .offline
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost,
             .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return .networkUnavailable(urlError.localizedDescription)
        default:
            return .transport(urlError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            if code == 401 { return "Unauthorized — check the API key in Settings" }
            return "Server error (\(code))"
        case .decodingError(let msg): return "Data error: \(msg)"
        case .invalidBaseURL:
            return "Invalid server URL. Enter an http:// or https:// server address."
        case .invalidEndpointURL:
            return "Invalid request URL"
        case .offline:
            return "No internet connection"
        case .networkUnavailable(let msg):
            return msg.isEmpty ? "Unable to reach the Look server" : msg
        case .timedOut:
            return "The request timed out"
        case .cancelled:
            return "The request was cancelled"
        case .transport(let msg):
            return msg.isEmpty ? "Network error" : msg
        }
    }
}

enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.sladebot.look"

    static func string(forKey key: String) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setString(_ value: String, forKey key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteString(forKey: key) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as CFDictionary

        let updateStatus = SecItemUpdate(query, [
            kSecValueData: data
        ] as CFDictionary)

        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        let addStatus = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func deleteString(forKey key: String) -> Bool {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func migrateUserDefaultsString(forKey defaultsKey: String, toKeychainKey keychainKey: String) {
        let defaults = UserDefaults.standard
        guard let legacyValue = defaults.string(forKey: defaultsKey) else { return }

        let trimmedLegacyValue = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLegacyValue.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
            return
        }

        if string(forKey: keychainKey) != nil || setString(trimmedLegacyValue, forKey: keychainKey) {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}
