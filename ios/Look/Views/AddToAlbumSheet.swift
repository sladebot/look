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
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FILE INTO A COLLECTION")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(LookTheme.ColorToken.warning)
                        Text(photos.count == 1 ? "Choose an album for this frame." : "Choose an album for \(photos.count) selected frames.")
                            .font(LookTheme.Typography.secondary)
                            .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    }

                    if store.albums.isEmpty {
                        LookEmptyState(title: "No albums yet", systemImage: "rectangle.stack",
                                       message: "Create your first album, then add these photos.",
                                       actionTitle: "Create album") { showCreate = true }
                    } else {
                        LazyVStack(spacing: LookTheme.Spacing.small) {
                            ForEach(store.albums) { album in
                                Button { Task { await add(to: album) } } label: {
                                    HStack(spacing: LookTheme.Spacing.small) {
                                        Group {
                                            if let cover = album.coverPhotoId {
                                                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: cover, size: 128))
                                            } else {
                                                LookTheme.ColorToken.elevated
                                                    .overlay { Image(systemName: "rectangle.stack").foregroundStyle(LookTheme.ColorToken.accent) }
                                            }
                                        }
                                        .frame(width: 58, height: 58)
                                        .clipped()

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(album.name)
                                                .font(LookTheme.Typography.bodyEmphasis)
                                                .foregroundStyle(LookTheme.ColorToken.primaryText)
                                            Text((album.photoCount ?? 0) == 1 ? "1 frame" : "\((album.photoCount ?? 0).formatted()) frames")
                                                .font(LookTheme.Typography.caption)
                                                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                                        }
                                        Spacer()
                                        if busyAlbumId == album.id { ProgressView() }
                                        else if addedAlbumIds.contains(album.id) {
                                            Image(systemName: "checkmark.square.fill").foregroundStyle(LookTheme.ColorToken.success)
                                        } else {
                                            Image(systemName: "plus.square").foregroundStyle(LookTheme.ColorToken.accent)
                                        }
                                    }
                                    .padding(8)
                                    .background(LookTheme.ColorToken.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(busyAlbumId != nil)
                            }
                        }
                    }
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
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
        var added = 0
        do {
            for photo in photos {
                _ = try await APIClient.shared.addPhotoToAlbum(albumId: album.id, photoId: photo.id)
                added += 1
            }
            addedAlbumIds.insert(album.id)
        } catch {
            store.errorMessage = added > 0
                ? "Added \(added) of \(photos.count) photos, then: \(error.localizedDescription)"
                : error.localizedDescription
        }
        await store.loadAlbums()
    }
}
