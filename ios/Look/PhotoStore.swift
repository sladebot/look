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
    @Published var isSyncing = false
    @Published var lastSyncMessage: String?
    @Published var lastAutoSyncAt: Date?
    @Published var autoSyncEnabled = true

    private let client = APIClient.shared
    private var autoSyncTask: Task<Void, Never>?
    private let autoSyncInterval: UInt64 = 30_000_000_000
    private let pageSize = 200

    func checkConnection() async {
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
        if reset { currentOffset = 0 }
        isLoading = true
        errorMessage = nil
        do {
            if reset {
                var allPhotos: [Photo] = []
                var offset = 0
                var responseTotal = 0

                while true {
                    let response = try await client.photos(
                        limit: pageSize, offset: offset,
                        query: searchQuery.isEmpty ? nil : searchQuery
                    )
                    responseTotal = response.total
                    allPhotos.append(contentsOf: response.photos)
                    offset += response.photos.count

                    if response.photos.count < pageSize {
                        break
                    }
                }

                photos = allPhotos
                currentOffset = allPhotos.count
                totalPhotos = max(responseTotal, allPhotos.count)
                isLoading = false
                return
            }

            let response = try await client.photos(
                limit: pageSize, offset: currentOffset,
                query: searchQuery.isEmpty ? nil : searchQuery
            )
            photos.append(contentsOf: response.photos)
            let loadedCount = currentOffset + response.photos.count
            totalPhotos = max(totalPhotos, response.total, loadedCount)
            currentOffset += response.photos.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func syncNow(background: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        if !background {
            lastSyncMessage = "Syncing photos..."
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
        } catch {
            if !background {
                errorMessage = error.localizedDescription
                lastSyncMessage = "Sync failed"
            }
        }

        isSyncing = false
    }

    /// Poll a background task until it leaves the running/pending state (or times out).
    private func pollTask(_ taskId: String, timeoutSeconds: Int = 180) async -> TaskInfo? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            guard let task = try? await client.task(taskId) else { return nil }
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
        guard !isLoading else { return }
        guard photos.count >= 5 else { return }
        let thresholdIndex = photos.index(photos.endIndex, offsetBy: -5)
        if let idx = photos.firstIndex(where: { $0.id == currentPhoto.id }),
           idx >= thresholdIndex,
           photos.count < totalPhotos {
            Task { await loadPhotos() }
        }
    }
}
