import SwiftUI

struct AlbumDetail: View {
    let album: Album
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: Photo?

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 4)
    ]

    var body: some View {
        Group {
            if isLoading {
                LookLoadingState(title: "Loading album", message: album.name)
            } else if let errorMessage {
                VStack(spacing: LookTheme.Spacing.medium) {
                    LookStatusBanner(
                        title: "Could not load album",
                        message: errorMessage,
                        tone: .error,
                        actionTitle: "Retry",
                        action: { Task { await loadPhotos() } }
                    )
                    Spacer(minLength: 0)
                }
                .padding(LookTheme.Spacing.screen)
            } else if photos.isEmpty {
                LookEmptyState(
                    title: "No photos in this album",
                    systemImage: "photo.on.rectangle",
                    message: "Add photos from a photo's detail screen."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                        HStack {
                            LookChip(title: photos.count == 1 ? "1 photo" : "\(photos.count) photos", systemImage: "photo", tint: LookTheme.ColorToken.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, LookTheme.Spacing.tight)

                        LazyVGrid(columns: columns, spacing: 4) {
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
                    }
                    .padding(.horizontal, LookTheme.Spacing.small)
                    .padding(.bottom, LookTheme.Spacing.large)
                }
                .refreshable { await loadPhotos() }
            }
        }
        .lookScreenBackground()
        .navigationTitle(album.name)
        .task { await loadPhotos() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
        }
    }

    private func loadPhotos() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await APIClient.shared.albumDetail(album.id)
            photos = detail.photos ?? []
        } catch {
            photos = []
            errorMessage = error.localizedDescription
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
