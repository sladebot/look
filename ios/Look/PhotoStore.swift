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
