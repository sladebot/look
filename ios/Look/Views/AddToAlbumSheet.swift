import SwiftUI

/// Sheet to add one or more photos to one of the user's manual albums.
struct AddToAlbumSheet: View {
    let photos: [Photo]
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var busyAlbumId: String?
    @State private var addedAlbumIds: Set<String> = []
    @State private var showCreate = false

    init(photo: Photo) {
        self.photos = [photo]
    }

    init(photos: [Photo]) {
        self.photos = photos
    }

    var body: some View {
        NavigationStack {
            List {
                if store.albums.isEmpty {
                    ContentUnavailableView("No albums", systemImage: "rectangle.stack",
                                           description: Text("Create an album first."))
                }
                ForEach(store.albums) { album in
                    Button {
                        Task { await add(to: album) }
                    } label: {
                        HStack(spacing: LookTheme.Spacing.small) {
                            Image(systemName: "rectangle.stack")
                                .foregroundStyle(LookTheme.ColorToken.cyan)
                                .frame(width: 26)
                            Text(album.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if busyAlbumId == album.id {
                                ProgressView()
                            } else if addedAlbumIds.contains(album.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LookTheme.ColorToken.success)
                            } else {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(LookTheme.ColorToken.readableTertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(busyAlbumId != nil)
                }
            }
            .navigationTitle(photos.count == 1 ? "Add to Album" : "Add \(photos.count) Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await store.loadAlbums() }
            .sheet(isPresented: $showCreate) { CreateAlbumSheet() }
        }
    }

    private func add(to album: Album) async {
        busyAlbumId = album.id
        defer { busyAlbumId = nil }
        do {
            for photo in photos {
                _ = try await APIClient.shared.addPhotoToAlbum(albumId: album.id, photoId: photo.id)
            }
            addedAlbumIds.insert(album.id)
            await store.loadAlbums()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
