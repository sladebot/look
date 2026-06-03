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

    enum CodingKeys: String, CodingKey {
        case id, filename, filepath
        case fileSize = "file_size"
        case width, height
        case mimeType = "mime_type"
        case createdAt = "created_at"
        case hasThumbnail = "has_thumbnail"
        case isFavorite = "is_favorite"
        case exif
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
        exif = try container.decodeIfPresent(EXIFData.self, forKey: .exif)
    }

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
