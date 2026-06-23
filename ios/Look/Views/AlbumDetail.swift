import SwiftUI

struct AlbumDetail: View {
    let album: Album
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var selected: Photo?

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundColor(.secondary)
                    Text("No photos in this album").font(.headline)
                    Text("Add photos from a photo's detail screen.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            PhotoCard(photo: photo)
                                .onTapGesture { selected = photo }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await remove(photo) }
                                    } label: {
                                        Label("Remove from Album", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .navigationTitle(album.name)
        .task { await loadPhotos() }
        .refreshable { await loadPhotos() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
        }
    }

    private func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }
        if let detail = try? await APIClient.shared.albumDetail(album.id) {
            photos = detail.photos ?? []
        }
    }

    private func remove(_ photo: Photo) async {
        do {
            _ = try await APIClient.shared.removePhotoFromAlbum(albumId: album.id, photoId: photo.id)
            photos.removeAll { $0.id == photo.id }
            await store.loadAlbums()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
