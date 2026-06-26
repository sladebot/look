import Foundation

// MARK: - Photo

struct Photo: Codable, Identifiable, Equatable {
    let id: String
    let filename: String
    let filepath: String
    let fileSize: Int?
    let width: Int?
    let height: Int?
    let mimeType: String?
    let createdAt: String?
    let hasThumbnail: Bool?
    let isFavorite: Bool?
    let exif: EXIFData?
    /// Top-level GPS columns returned by the server (gps_lat/gps_lon). The
    /// nested `exif.gps` is preferred when present; these are the fallback.
    let gpsLat: Double?
    let gpsLon: Double?

    enum CodingKeys: String, CodingKey {
        case id, filename, filepath
        case fileSize = "file_size"
        case width, height
        case mimeType = "mime_type"
        case createdAt = "created_at"
        case hasThumbnail = "has_thumbnail"
        case isFavorite = "is_favorite"
        case exif
        case gpsLat = "gps_lat"
        case gpsLon = "gps_lon"
    }

    init(
        id: String,
        filename: String,
        filepath: String,
        fileSize: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        mimeType: String? = nil,
        createdAt: String? = nil,
        hasThumbnail: Bool? = nil,
        isFavorite: Bool? = nil,
        exif: EXIFData? = nil,
        gpsLat: Double? = nil,
        gpsLon: Double? = nil
    ) {
        self.id = id
        self.filename = filename
        self.filepath = filepath
        self.fileSize = fileSize
        self.width = width
        self.height = height
        self.mimeType = mimeType
        self.createdAt = createdAt
        self.hasThumbnail = hasThumbnail
        self.isFavorite = isFavorite
        self.exif = exif
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        filepath = try container.decode(String.self, forKey: .filepath)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        hasThumbnail = Self.decodeFlexibleBool(container, key: .hasThumbnail)
        isFavorite = Self.decodeFlexibleBool(container, key: .isFavorite)
        exif = Self.decodeFlexibleExif(container, key: .exif)
        gpsLat = try? container.decodeIfPresent(Double.self, forKey: .gpsLat)
        gpsLon = try? container.decodeIfPresent(Double.self, forKey: .gpsLon)
    }

    /// The server stores EXIF as a JSON string in the `exif` column and returns
    /// it verbatim, so it may arrive as either a nested object or a JSON string.
    private static func decodeFlexibleExif(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> EXIFData? {
        if let obj = try? container.decodeIfPresent(EXIFData.self, forKey: key) {
            return obj
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key),
           let data = raw.data(using: .utf8) {
            return try? JSONDecoder().decode(EXIFData.self, from: data)
        }
        return nil
    }

    /// Best-available latitude (nested EXIF gps first, then top-level column).
    var latitude: Double? { exif?.gps?.lat ?? gpsLat }
    /// Best-available longitude (nested EXIF gps first, then top-level column).
    var longitude: Double? { exif?.gps?.lon ?? gpsLon }
    var hasLocation: Bool { latitude != nil && longitude != nil }

    private static func decodeFlexibleBool(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return nil
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool { lhs.id == rhs.id }
}

// MARK: - EXIF

struct EXIFData: Codable {
    let make: String?
    let model: String?
    let datetime: String?
    let gps: GPSData?
}

struct GPSData: Codable {
    let lat: Double?
    let lon: Double?
}

// MARK: - Album

struct Album: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let photoCount: Int?
    let source: String?
    let photos: [Photo]?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case photoCount = "photo_count"
        case source, photos
    }
}

// MARK: - Smart Collection

struct SmartCollection: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let ruleSpec: String?
    let lastEvaluatedAt: String?
    let photos: [Photo]?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case ruleSpec = "rule_spec"
        case lastEvaluatedAt = "last_evaluated_at"
        case photos
    }
}

struct SmartCollectionsResponse: Codable {
    let collections: [SmartCollection]
}

// MARK: - Tags

struct TagInfo: Codable, Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int?
}

struct TagListResponse: Codable {
    let tags: [String]?
}

struct AllTagsResponse: Codable {
    let tags: [TagInfo]
}

struct AutoTagResponse: Codable {
    let status: String
    let tagsAdded: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case tagsAdded = "tags_added"
    }
}

struct TagHistoryEntry: Codable, Identifiable {
    var id: String { "\(tag)-\(action)-\(timestamp)" }
    let tag: String
    let action: String
    let timestamp: String
    let byUser: String?

    enum CodingKeys: String, CodingKey {
        case tag, action, timestamp
        case byUser = "by_user"
    }
}

struct TagSuggestResponse: Codable {
    let photoId: String
    let suggestions: [String]

    enum CodingKeys: String, CodingKey {
        case photoId = "photo_id"
        case suggestions
    }
}

// MARK: - Responses

struct PhotoListResponse: Codable {
    let photos: [Photo]
    let total: Int
}

struct AlbumListResponse: Codable {
    let albums: [Album]
}

struct HealthResponse: Codable {
    let status: String
    let photoCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case photoCount = "photo_count"
    }
}

struct ImportResponse: Codable {
    let imported: Int
    let errors: Int
    let totalScanned: Int
    let message: String?
    let errorDetails: [String]?

    enum CodingKeys: String, CodingKey {
        case imported, errors, message
        case totalScanned = "total_scanned"
        case errorDetails = "error_details"
    }
}

struct SearchResponse: Codable {
    let photos: [Photo]
}

struct GenericStatusResponse: Codable {
    let status: String?
    let detail: String?
}

struct CreateAlbumResponse: Codable {
    let id: String
    let name: String?
}

// MARK: - Import / Tasks

struct ImportSubmitResponse: Codable {
    let status: String
    let taskId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status, message
        case taskId = "task_id"
    }
}

struct TaskSubmitResponse: Codable {
    let status: String
    let taskId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status, message
        case taskId = "task_id"
    }
}

struct TaskListResponse: Codable {
    let tasks: [TaskInfo]
}

struct TaskInfo: Codable, Identifiable {
    var id: String { taskId }
    let taskId: String
    let taskType: String?
    let status: String
    let error: String?
    let createdAt: String?
    let completedAt: String?
    let progress: JSONValue?
    let result: JSONValue?

    enum CodingKeys: String, CodingKey {
        case status, error, progress, result
        case taskId = "task_id"
        case taskType = "task_type"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

// MARK: - Tag history / merge

struct TagHistoryResponse: Codable {
    let photoId: String?
    let history: [TagHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case history
        case photoId = "photo_id"
    }
}

struct DuplicateTagsResponse: Codable {
    let suggestions: [DuplicateTagGroup]
}

struct DuplicateTagGroup: Codable, Identifiable {
    var id: String { normal }
    let normal: String
    let tag: String?
    let c: Int?
}

// MARK: - Settings

struct SettingsResponse: Codable {
    let settings: [String: String]
}

// MARK: - Dedup

struct DedupSettingsResponse: Codable {
    let dedupEnabled: Bool
    let dedupTolerance: Int

    enum CodingKeys: String, CodingKey {
        case dedupEnabled = "dedup_enabled"
        case dedupTolerance = "dedup_tolerance"
    }
}

struct DedupSettingsUpdateResponse: Codable {
    let status: String?
    let settings: DedupSettingsResponse?
}

struct DedupGroupPhoto: Codable, Identifiable, Equatable {
    var id: String { photoId }
    let photoId: String
    let filename: String?
    let filepath: String?
    let phash: String?

    enum CodingKeys: String, CodingKey {
        case filename, filepath, phash
        case photoId = "photo_id"
    }
}

// MARK: - Watch list

struct WatchListResponse: Codable {
    let directories: [WatchDirectory]
}

struct WatchDirectory: Codable, Identifiable {
    var id: String { path }
    let path: String
    let addedAt: String?
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case path, active
        case addedAt = "added_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt)
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .active) {
            active = b ?? true
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .active) {
            active = (i ?? 1) != 0
        } else {
            active = true
        }
    }
}

// MARK: - Geo

struct NearbyResponse: Codable {
    let photos: [Photo]
    let total: Int?
}

// MARK: - Migrations

struct MigrationStatusResponse: Codable {
    let currentVersion: Int
    let pending: [MigrationItem]
    let allRegistered: [MigrationItem]?

    enum CodingKeys: String, CodingKey {
        case pending
        case currentVersion = "current_version"
        case allRegistered = "all_registered"
    }
}

struct MigrationItem: Codable, Identifiable {
    var id: Int { version }
    let version: Int
    let description: String
    let hasRollback: Bool?

    enum CodingKeys: String, CodingKey {
        case version, description
        case hasRollback = "has_rollback"
    }
}

struct MigrationApplyResponse: Codable {
    let status: String
    let appliedCount: Int?
    let migrations: [String]?

    enum CodingKeys: String, CodingKey {
        case status, migrations
        case appliedCount = "applied_count"
    }
}

// MARK: - Flexible JSON value (for task progress/result blobs)

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let arr = try? c.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? c.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    // Convenience accessors
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
    subscript(_ key: String) -> JSONValue? { objectValue?[key] }
}
