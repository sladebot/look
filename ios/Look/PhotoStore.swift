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
            let response = try await client.photos(
                limit: 50, offset: currentOffset,
                query: searchQuery.isEmpty ? nil : searchQuery
            )
            if reset {
                photos = response.photos
            } else {
                photos.append(contentsOf: response.photos)
            }
            let loadedCount = reset ? response.photos.count : currentOffset + response.photos.count
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
            let result = try await client.importPhotos()
            let health = try await client.health()
            serverConnected = health.status == "ok"

            let serverCount = health.photoCount ?? previousCount
            let shouldReload = result.imported > 0 || serverCount != previousCount || photos.isEmpty
            if shouldReload {
                await loadPhotos(reset: true)
                await loadAlbums()
                totalPhotos = serverCount
            } else {
                totalPhotos = serverCount
            }

            lastAutoSyncAt = Date()
            if !background || result.imported > 0 || result.errors > 0 {
                let checked = result.totalScanned
                let imported = result.imported
                let errors = result.errors
                if errors > 0 {
                    lastSyncMessage = "Synced \(imported) photos, \(errors) errors"
                } else if imported > 0 {
                    lastSyncMessage = "Synced \(imported) new photos"
                } else {
                    lastSyncMessage = "Checked \(checked) photos"
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
