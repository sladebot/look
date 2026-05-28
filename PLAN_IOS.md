# Look iOS App — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a native SwiftUI iOS app that connects to the Look local photo server over LAN, providing full photo browsing, album management, tagging, and search — replacing the need for Adobe cloud storage.

**Architecture:** SwiftUI app with MVVM pattern. `APIClient` handles all networking to the Look server REST API. `PhotoStore` is the `@ObservableObject` data layer. Views are thin — `PhotosGrid`, `PhotoDetail`, `AlbumsList`, `TagsView`, `SearchView`. No local photo storage — everything streams from the server.

**Tech Stack:** SwiftUI, iOS 17+, xcodegen for project generation, native URLSession for networking, Swift Concurrency (async/await).

---

## API Reference (Look Server)

The iOS app talks to these endpoints on the LAN server (e.g. `http://10.0.0.151:8765`):

| Method | Path | iOS Use |
|--------|------|---------|
| GET | `/api/health` | Connection check, server status |
| GET | `/api/photos?limit=&offset=&tag=&camera=&q=` | Photo grid, filtering, search |
| GET | `/api/photos/{id}` | Photo detail (EXIF, metadata) |
| GET | `/api/thumbnails/{id}?size=N` | Grid thumbnails (256), detail (512) |
| GET | `/api/full/{id}` | Full-resolution viewer |
| GET | `/api/albums` | Albums list |
| GET | `/api/albums/{id}` | Album photos |
| GET | `/api/smart-collections` | Smart album list |
| GET | `/api/smart-collections/{id}` | Smart album photos |
| GET | `/api/photos/{id}/tags` | Photo's tags |
| POST | `/api/photos/{id}/tags?tag=X` | Add tag |
| DELETE | `/api/photos/{id}/tags/{tag}` | Remove tag |
| POST | `/api/photos/{id}/tags/auto` | Auto-tag from EXIF |
| GET | `/api/photos/{id}/tags/suggest` | Tag suggestions |
| GET | `/api/tags` | All tags with counts |
| GET | `/api/search?q=X` | Full-text search |

---

## File Structure

```
ios/
├── project.yml              # xcodegen project definition
├── Look/
│   ├── LookApp.swift         # @main App entry point
│   ├── ContentView.swift     # Root TabView
│   ├── Models.swift          # Codable structs (Photo, Album, Tag, etc.)
│   ├── APIClient.swift       # URLSession networking layer
│   ├── PhotoStore.swift      # @ObservableObject data store
│   ├── ServerSettings.swift  # Server URL configuration
│   ├── Views/
│   │   ├── PhotosGrid.swift       # LazyVGrid photo browser
│   │   ├── PhotoDetail.swift      # Full-res + metadata + tags
│   │   ├── PhotoCard.swift        # Single grid cell
│   │   ├── AlbumsList.swift       # Album browser
│   │   ├── AlbumDetail.swift      # Album photo list
│   │   ├── SmartAlbumsList.swift  # Smart album browser
│   │   ├── TagsView.swift         # Tag management on a photo
│   │   ├── TagPill.swift          # Single tag badge
│   │   ├── SearchView.swift       # Search interface
│   │   ├── SettingsView.swift     # Server URL, about
│   │   └── FullScreenImage.swift  # Pinch-to-zoom image viewer
│   └── Assets.xcassets/
│       ├── Contents.json
│       ├── AccentColor.colorset/
│       │   └── Contents.json
│       └── AppIcon.appiconset/
│           └── Contents.json
└── .gitignore
```

---

## Phase 1 — Scaffold & Networking

### Task 1.1: Create xcodegen project.yml and scaffold

**Files:**
- Create: `ios/project.yml`
- Create: `ios/.gitignore`
- Create: `ios/Look/LookApp.swift`
- Create: `ios/Look/ContentView.swift`
- Create: `ios/Look/Assets.xcassets/Contents.json`
- Create: `ios/Look/Assets.xcassets/AccentColor.colorset/Contents.json`

**Steps:**
1. Write `project.yml` targeting iOS 17, bundle ID `com.sladebot.look`
2. Write minimal `LookApp.swift` with `WindowGroup { ContentView() }`
3. Write placeholder `ContentView.swift` with "Connecting..." text
4. Generate project: `cd ios && /tmp/xcodegen/xcodegen/bin/xcodegen generate`
5. Verify: `swiftc -parse ios/Look/*.swift` passes

---

### Task 1.2: Create data models (Codable structs)

**Files:**
- Create: `ios/Look/Models.swift`

**Models to create:**
```swift
struct Photo: Codable, Identifiable {
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
}

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

struct Album: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let photoCount: Int?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case photoCount = "photo_count"
        case source
    }
}

struct TagInfo: Codable, Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int?
}

struct PhotoListResponse: Codable {
    let photos: [Photo]
    let total: Int
}

struct TagListResponse: Codable {
    let tags: [String]
}

struct AllTagsResponse: Codable {
    let tags: [TagInfo]
}

struct SmartCollection: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let ruleSpec: String?
    let photos: [Photo]?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case ruleSpec = "rule_spec"
        case photos
    }
}

struct SmartCollectionsResponse: Codable {
    let collections: [SmartCollection]
}

struct HealthResponse: Codable {
    let status: String
    let photoCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case photoCount = "photo_count"
    }
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
```

**Verify:** `swiftc -parse ios/Look/Models.swift` passes

---

### Task 1.3: Create APIClient networking layer

**Files:**
- Create: `ios/Look/APIClient.swift`

**Implementation:**
```swift
import Foundation

class APIClient {
    static let shared = APIClient()

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "server_url") ?? "http://10.0.0.151:8765"
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        return d
    }

    func health() async throws -> HealthResponse {
        return try await get("/api/health")
    }

    func photos(limit: Int = 50, offset: Int = 0, tag: String? = nil,
                camera: String? = nil, query: String? = nil) async throws -> PhotoListResponse {
        var params = "limit=\(limit)&offset=\(offset)"
        if let tag = tag { params += "&tag=\(tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag)" }
        if let camera = camera { params += "&camera=\(camera.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? camera)" }
        if let query = query { params += "&q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)" }
        return try await get("/api/photos?\(params)")
    }

    func photoDetail(_ id: String) async throws -> Photo {
        return try await get("/api/photos/\(id)")
    }

    func thumbnailURL(for photoId: String, size: Int = 256) -> URL {
        URL(string: "\(baseURL)/api/thumbnails/\(photoId)?size=\(size)")!
    }

    func fullImageURL(for photoId: String) -> URL {
        URL(string: "\(baseURL)/api/full/\(photoId)")!
    }

    func albums() async throws -> [Album] {
        return try await get("/api/albums")
    }

    func albumDetail(_ id: String) async throws -> Album {
        return try await get("/api/albums/\(id)")
    }

    func smartCollections() async throws -> SmartCollectionsResponse {
        return try await get("/api/smart-collections")
    }

    func smartCollectionDetail(_ id: String) async throws -> SmartCollection {
        return try await get("/api/smart-collections/\(id)")
    }

    func photoTags(_ photoId: String) async throws -> TagListResponse {
        return try await get("/api/photos/\(photoId)/tags")
    }

    func addTag(_ photoId: String, tag: String) async throws {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
        _ = try await post("/api/photos/\(photoId)/tags?tag=\(encoded)")
    }

    func removeTag(_ photoId: String, tag: String) async throws {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        _ = try await delete("/api/photos/\(photoId)/tags/\(encoded)")
    }

    func autoTag(_ photoId: String) async throws -> AutoTagResponse {
        return try await post("/api/photos/\(photoId)/tags/auto")
    }

    func allTags() async throws -> AllTagsResponse {
        return try await get("/api/tags")
    }

    func search(query: String) async throws -> PhotoListResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/api/search?q=\(encoded)")
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(T.self, from: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(T.self, from: data)
    }
}
```

**Verify:** `swiftc -parse ios/Look/APIClient.swift` passes

---

### Task 1.4: Create PhotoStore (ObservableObject)

**Files:**
- Create: `ios/Look/PhotoStore.swift`

```swift
import Foundation
import SwiftUI

@MainActor
class PhotoStore: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var albums: [Album] = []
    @Published var smartCollections: [SmartCollection] = []
    @Published var allTags: [TagInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var serverConnected = false
    @Published var currentOffset = 0
    @Published var totalPhotos = 0
    @Published var searchQuery = ""

    private let client = APIClient.shared

    func checkConnection() async {
        do {
            let health = try await client.health()
            serverConnected = health.status == "ok"
        } catch {
            serverConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func loadPhotos(reset: Bool = false) async {
        if reset { currentOffset = 0 }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.photos(
                limit: 50, offset: currentOffset,
                query: searchQuery.isEmpty ? nil : searchQuery
            )
            if reset {
                photos = response.photos
            } else {
                photos.append(contentsOf: response.photos)
            }
            totalPhotos = response.total
            currentOffset += response.photos.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadAlbums() async {
        do {
            albums = try await client.albums()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSmartCollections() async {
        do {
            let response = try await client.smartCollections()
            smartCollections = response.collections
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAllTags() async {
        do {
            let response = try await client.allTags()
            allTags = response.tags
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        searchQuery = query
        await loadPhotos(reset: true)
    }

    func loadMoreIfNeeded(currentPhoto: Photo) {
        guard !isLoading else { return }
        let thresholdIndex = photos.index(photos.endIndex, offsetBy: -5)
        if let idx = photos.firstIndex(where: { $0.id == currentPhoto.id }),
           idx >= thresholdIndex,
           photos.count < totalPhotos {
            Task { await loadPhotos() }
        }
    }
}
```

**Verify:** `swiftc -parse ios/Look/PhotoStore.swift` passes

---

## Phase 2 — Photo Browsing

### Task 2.1: PhotoCard view (grid cell)

**Files:**
- Create: `ios/Look/Views/PhotoCard.swift`

SwiftUI view showing thumbnail with async image loading. Tap navigates to detail.

---

### Task 2.2: PhotosGrid view

**Files:**
- Create: `ios/Look/Views/PhotosGrid.swift`

`LazyVGrid` with 3 columns, infinite scroll via `loadMoreIfNeeded`, pull-to-refresh, navigation to detail.

---

### Task 2.3: FullScreenImage view (pinch-to-zoom)

**Files:**
- Create: `ios/Look/Views/FullScreenImage.swift`

`AsyncImage` with `.resizable().aspectRatio(contentMode: .fit)`, `MagnificationGesture` for pinch-to-zoom, double-tap to zoom toggle.

---

### Task 2.4: PhotoDetail view

**Files:**
- Create: `ios/Look/Views/PhotoDetail.swift`

Shows full-res image, filename, date, dimensions, camera make/model, tag pills, add/remove tag, auto-tag button, navigation to albums.

---

## Phase 3 — Albums & Smart Collections

### Task 3.1: AlbumsList view

**Files:**
- Create: `ios/Look/Views/AlbumsList.swift`

List of albums with photo counts, tap to see album photos.

---

### Task 3.2: AlbumDetail view

**Files:**
- Create: `ios/Look/Views/AlbumDetail.swift`

Shows photos in an album, same grid style as PhotosGrid.

---

### Task 3.3: SmartAlbumsList view

**Files:**
- Create: `ios/Look/Views/SmartAlbumsList.swift`

List of smart albums with rule spec preview, tap to view matched photos.

---

## Phase 4 — Tags & Search

### Task 4.1: TagPill component

**Files:**
- Create: `ios/Look/Views/TagPill.swift`

Reusable tag badge with optional delete button.

---

### Task 4.2: TagsView (on photo detail)

**Files:**
- Create: `ios/Look/Views/TagsView.swift`

Tag input field, add/remove, auto-tag button, tag suggestions list.

---

### Task 4.3: SearchView

**Files:**
- Create: `ios/Look/Views/SearchView.swift`

Search bar that calls `/api/search?q=`, displays results in grid.

---

## Phase 5 — Settings & Polish

### Task 5.1: SettingsView

**Files:**
- Create: `ios/Look/Views/SettingsView.swift`

Server URL text field (saved to UserDefaults), connection test button, photo count display, app version.

---

### Task 5.2: ContentView (TabView root)

**Files:**
- Modify: `ios/Look/ContentView.swift`

`TabView` with tabs: Photos, Albums, Smart, Search, Settings. Each tab initializes its data on appear.

---

### Task 5.3: App icon and accent color

**Files:**
- Create: `ios/Look/Assets.xcassets/AppIcon.appiconset/Contents.json`

Simple solid-color app icon. Accent color set to system blue.

---

## Execution Order

```
Phase 1: 1.1 → 1.2 → 1.3 → 1.4  (serial — each depends on previous)
Phase 2: 2.1 → 2.2 → 2.3 → 2.4  (serial — each depends on previous)
Phase 3: 3.1 → 3.2 → 3.3          (serial, can run parallel to Phase 4)
Phase 4: 4.1 → 4.2 → 4.3          (serial, can run parallel to Phase 3)
Phase 5: 5.1 → 5.2 → 5.3          (after Phases 2-4)
```

---

## Verification Checklist

```bash
# After all tasks:
cd ios
swiftc -parse Look/*.swift Look/Views/*.swift  # all pass
/tmp/xcodegen/xcodegen/bin/xcodegen generate    # no errors
open Look.xcodeproj                             # opens in Xcode
# Cmd+R to build and run on simulator
```
