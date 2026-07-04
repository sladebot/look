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
    @Published var hasMorePhotos = true
    @Published var searchQuery = ""
    @Published var isSyncing = false
    @Published var lastSyncMessage: String?
    @Published var syncTask: TaskInfo?
    @Published var syncProgressMessage: String?
    @Published var syncProgressFraction: Double?
    @Published var lastAutoSyncAt: Date?
    @Published var autoSyncEnabled = true

    private let client = APIClient.shared
    private var autoSyncTask: Task<Void, Never>?
    private var loadingPageKeys: Set<String> = []
    private let autoSyncInterval: UInt64 = 30_000_000_000
    private let pageSize = 200

    func checkConnection() async {
        #if DEBUG
        if LookDemoScreenshots.isActive {
            serverConnected = true
            totalPhotos = max(totalPhotos, photos.count)
            return
        }
        #endif
        do {
            let health = try await client.health()
            serverConnected = health.status == "ok"
            if let count = health.photoCount {
                totalPhotos = count
            }
        } catch {
            serverConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func loadPhotos(reset: Bool = false) async {
        #if DEBUG
        if LookDemoScreenshots.isActive {
            serverConnected = true
            totalPhotos = max(totalPhotos, photos.count)
            hasMorePhotos = false
            return
        }
        #endif
        let query = searchQuery.isEmpty ? nil : searchQuery
        let offset = reset ? 0 : currentOffset
        let pageKey = "\(query ?? ""):\(offset)"
        guard !loadingPageKeys.contains(pageKey) else { return }
        guard reset || hasMorePhotos else { return }

        loadingPageKeys.insert(pageKey)
        isLoading = true
        errorMessage = nil
        if reset {
            currentOffset = 0
            hasMorePhotos = true
        }
        defer {
            loadingPageKeys.remove(pageKey)
            isLoading = !loadingPageKeys.isEmpty
        }

        do {
            let response = try await client.photos(
                limit: pageSize, offset: offset,
                query: query
            )

            if reset {
                photos = response.photos
            } else {
                appendUniquePhotos(response.photos)
            }

            currentOffset = offset + response.photos.count
            totalPhotos = max(response.total, photos.count)
            hasMorePhotos = currentOffset < response.total && !response.photos.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncNow(background: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncTask = nil
        syncProgressMessage = nil
        syncProgressFraction = nil
        if !background {
            lastSyncMessage = "Syncing photos..."
        }
        defer {
            isSyncing = false
            syncTask = nil
            syncProgressFraction = nil
        }

        do {
            let previousCount = totalPhotos

            // The server runs imports as a background task; submit then poll.
            let submit = try await client.importPhotos()
            var imported = 0
            var errors = 0
            if let taskId = submit.taskId {
                let finished = await pollTask(taskId)
                imported = finished?.result?["imported"]?.intValue ?? 0
                errors = finished?.result?["errors"]?.intValue ?? 0
            } else if let message = submit.message {
                syncProgressMessage = message
            }

            let health = try await client.health()
            serverConnected = health.status == "ok"
            let serverCount = health.photoCount ?? previousCount

            let shouldReload = imported > 0 || serverCount != previousCount || photos.isEmpty
            if shouldReload {
                await loadPhotos(reset: true)
                await loadAlbums()
            }
            totalPhotos = serverCount
            hasMorePhotos = photos.count < totalPhotos

            lastAutoSyncAt = Date()
            if !background || imported > 0 || errors > 0 {
                if errors > 0 {
                    lastSyncMessage = "Synced \(imported) photos, \(errors) errors"
                } else if imported > 0 {
                    lastSyncMessage = "Synced \(imported) new photos"
                } else {
                    lastSyncMessage = "Library up to date (\(serverCount) photos)"
                }
            }
            syncProgressMessage = lastSyncMessage
        } catch {
            if !background {
                errorMessage = error.localizedDescription
                lastSyncMessage = "Sync failed"
            }
            syncProgressMessage = lastSyncMessage
        }
    }

    /// Poll a background task until it leaves the running/pending state (or times out).
    private func pollTask(_ taskId: String, timeoutSeconds: Int = 180) async -> TaskInfo? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            guard let task = try? await client.task(taskId) else { return nil }
            syncTask = task
            updateSyncProgress(from: task)
            if ["completed", "failed", "cancelled"].contains(task.status) {
                return task
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return nil
    }

    func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncEnabled = true
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.autoSyncInterval ?? 30_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.syncNow(background: true)
            }
        }
    }

    func stopAutoSync() {
        autoSyncEnabled = false
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    func loadAlbums() async {
        #if DEBUG
        if LookDemoScreenshots.isActive { return }
        #endif
        do {
            // /api/albums also returns smart collections (source == "smart_collection");
            // those are surfaced separately via loadSmartCollections.
            albums = try await client.albums().filter { $0.source != "smart_collection" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSmartCollections() async {
        #if DEBUG
        if LookDemoScreenshots.isActive { return }
        #endif
        do {
            let response = try await client.smartCollections()
            smartCollections = response.collections
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAllTags() async {
        #if DEBUG
        if LookDemoScreenshots.isActive { return }
        #endif
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

    /// Optimistically set a photo's favorite flag; reverts on server failure.
    /// Returns whether the server accepted the change.
    @discardableResult
    func setFavorite(_ photoId: String, to value: Bool) async -> Bool {
        applyLocalFavorite(photoId, value)
        do {
            _ = try await client.setFavorite(photoId, favorite: value)
            return true
        } catch {
            applyLocalFavorite(photoId, !value)
            errorMessage = "Could not update favorite: \(error.localizedDescription)"
            return false
        }
    }

    private func applyLocalFavorite(_ photoId: String, _ value: Bool) {
        if let index = photos.firstIndex(where: { $0.id == photoId }) {
            photos[index].isFavorite = value
        }
    }

    // MARK: - Albums

    func createAlbum(name: String, description: String = "") async {
        do {
            _ = try await client.createAlbum(name: name, description: description)
            await loadAlbums()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAlbum(_ id: String) async {
        do {
            _ = try await client.deleteAlbum(id)
            await loadAlbums()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Smart collections

    func createSmartCollection(name: String, description: String, ruleSpec: String) async {
        do {
            _ = try await client.createSmartCollection(name: name, description: description, ruleSpec: ruleSpec)
            await loadSmartCollections()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteSmartCollection(_ id: String) async {
        do {
            _ = try await client.deleteSmartCollection(id)
            await loadSmartCollections()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Server settings

    @Published var serverSettings: [String: String] = [:]

    func loadServerSettings() async {
        #if DEBUG
        if LookDemoScreenshots.isActive { return }
        #endif
        do {
            serverSettings = try await client.settings().settings
        } catch { errorMessage = error.localizedDescription }
    }

    func boolSetting(_ key: String) -> Bool {
        let v = serverSettings[key]?.lowercased()
        return v == "true" || v == "1" || v == "yes"
    }

    func toggleServerSetting(_ key: String, to value: Bool) async {
        do {
            _ = try await client.putBoolSetting(key, value)
            serverSettings[key] = value ? "true" : "false"
        } catch { errorMessage = error.localizedDescription }
    }

    func loadMoreIfNeeded(currentPhoto: Photo) {
        guard !isLoading, hasMorePhotos else { return }
        guard photos.count >= 5 else { return }
        let thresholdIndex = photos.index(photos.endIndex, offsetBy: -5)
        if let idx = photos.firstIndex(where: { $0.id == currentPhoto.id }),
           idx >= thresholdIndex,
           hasMorePhotos {
            Task { await loadPhotos() }
        }
    }

    private func appendUniquePhotos(_ newPhotos: [Photo]) {
        guard !newPhotos.isEmpty else { return }
        var seen = Set(photos.map(\.id))
        let unique = newPhotos.filter { seen.insert($0.id).inserted }
        photos.append(contentsOf: unique)
    }

    private func updateSyncProgress(from task: TaskInfo) {
        let phase = task.progress?["phase"]?.stringValue
        let current = task.progress?["current"]?.intValue
        let total = task.progress?["total_scanned"]?.intValue
            ?? task.progress?["total"]?.intValue

        if let current, let total, total > 0 {
            syncProgressFraction = min(1, max(0, Double(current) / Double(total)))
            if let phase {
                syncProgressMessage = "\(phase.capitalized) \(current) of \(total)"
            } else {
                syncProgressMessage = "Syncing \(current) of \(total)"
            }
        } else if let phase {
            syncProgressFraction = nil
            syncProgressMessage = phase.capitalized
        } else {
            syncProgressFraction = nil
            syncProgressMessage = "Sync \(task.status)"
        }
    }
}
