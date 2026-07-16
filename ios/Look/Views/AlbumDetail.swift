import SwiftUI

struct AlbumDetail: View {
    let album: Album
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: Photo?
    @State private var albumName: String
    @State private var showEditAlbum = false
    @State private var selectionMode = false
    @State private var selectedPhotoIds: Set<String> = []
    @State private var isRemovingSelection = false
    @State private var isFavoritingSelection = false
    @State private var isPreparingShare = false
    @State private var shareItem: SelectionShareItem?
    @State private var toast: LookToast?
    @Namespace private var viewerZoomNamespace

    init(album: Album) {
        self.album = album
        _albumName = State(initialValue: album.name)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 4)
    ]

    private var selectedPhotos: [Photo] {
        photos.filter { selectedPhotoIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if isLoading {
                LookLoadingState(title: "Loading album", message: albumName)
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
                grid
            }
        }
        .lookScreenBackground()
        .navigationTitle(selectionMode ? selectionSummary : albumName)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectionMode)
        .lookToast($toast, bottomPadding: selectionMode ? 88 : 12)
        .task { await loadPhotos() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
                .modifier(LookZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.urls)
        }
        .sheet(isPresented: $showEditAlbum) {
            EditAlbumSheet(album: album, currentName: albumName) { newName in
                albumName = newName
                await store.loadAlbums()
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                albumHeader

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos) { photo in
                        PhotoCard(photo: photo,
                                  isSelected: selectedPhotoIds.contains(photo.id),
                                  selectionMode: selectionMode)
                            .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                            .onTapGesture {
                                if selectionMode {
                                    toggleSelection(photo)
                                } else {
                                    selected = photo
                                }
                            }
                            .onLongPressGesture {
                                guard !selectionMode else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                selectionMode = true
                                selectedPhotoIds = [photo.id]
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await remove([photo]) }
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

    private var albumHeader: some View {
        HStack(spacing: LookTheme.Spacing.medium) {
            if let cover = photos.first {
                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: cover.id, size: 256))
                    .frame(width: 88, height: 88)
                    .clipped()
            } else {
                LookTheme.ColorToken.elevated
                    .overlay { Image(systemName: "rectangle.stack").foregroundStyle(LookTheme.ColorToken.accent) }
                    .frame(width: 88, height: 88)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("ALBUM")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(LookTheme.ColorToken.warning)
                Text(albumName)
                    .font(LookTheme.Typography.title)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .lineLimit(2)
                Text(photos.count == 1 ? "1 frame" : "\(photos.count.formatted()) frames")
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(LookTheme.Spacing.small)
        .background(LookTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Toolbar & selection

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selectionMode {
                Button("Done") {
                    selectionMode = false
                    selectedPhotoIds.removeAll()
                }
            } else {
                Menu {
                    Button {
                        selectionMode = true
                    } label: {
                        Label("Select Photos", systemImage: "checkmark.circle")
                    }
                    .disabled(photos.isEmpty)
                    Button {
                        showEditAlbum = true
                    } label: {
                        Label("Rename Album", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Album actions")
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            Button {
                Task { await remove(selectedPhotos) }
            } label: {
                Label(isRemovingSelection ? "Removing…" : "Remove",
                      systemImage: "minus.circle")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(LookTheme.ColorToken.danger)
            .disabled(selectedPhotoIds.isEmpty || isRemovingSelection)
            .accessibilityLabel("Remove selected photos from this album")

            Button {
                favoriteSelection()
            } label: {
                Label("Favorite", systemImage: "heart")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(LookTheme.ColorToken.accent)
            .disabled(selectedPhotoIds.isEmpty || isFavoritingSelection)
            .accessibilityLabel("Mark selected photos as favorites")

            Button {
                shareSelection()
            } label: {
                Label(isPreparingShare ? "Preparing…" : "Share",
                      systemImage: "square.and.arrow.up")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(LookTheme.ColorToken.accent)
            .disabled(selectedPhotoIds.isEmpty || isPreparingShare)
            .accessibilityLabel("Share selected photos")
        }
        .padding(.horizontal, LookTheme.Spacing.medium)
        .padding(.vertical, LookTheme.Spacing.small)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.bottom, LookTheme.Spacing.tight)
        .accessibilityElement(children: .contain)
    }

    private var selectionSummary: String {
        let count = selectedPhotoIds.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private func toggleSelection(_ photo: Photo) {
        if selectedPhotoIds.contains(photo.id) {
            selectedPhotoIds.remove(photo.id)
        } else {
            selectedPhotoIds.insert(photo.id)
        }
    }

    // MARK: - Actions

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

    private func remove(_ toRemove: [Photo]) async {
        guard !toRemove.isEmpty, !isRemovingSelection else { return }
        isRemovingSelection = true
        defer { isRemovingSelection = false }
        var removed: [Photo] = []
        for photo in toRemove {
            do {
                _ = try await APIClient.shared.removePhotoFromAlbum(albumId: album.id, photoId: photo.id)
                removed.append(photo)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        guard !removed.isEmpty else { return }
        let removedIds = Set(removed.map(\.id))
        photos.removeAll { removedIds.contains($0.id) }
        selectedPhotoIds.subtract(removedIds)
        if photos.isEmpty { selectionMode = false }
        await store.loadAlbums()

        let albumId = album.id
        toast = LookToast(
            message: removed.count == 1
                ? "Removed from \(albumName)"
                : "Removed \(removed.count) from \(albumName)",
            undo: {
                Task {
                    for photo in removed {
                        _ = try? await APIClient.shared.addPhotoToAlbum(albumId: albumId, photoId: photo.id)
                    }
                    await loadPhotos()
                    await store.loadAlbums()
                }
            }
        )
    }

    private func favoriteSelection() {
        let targets = selectedPhotos
        guard !targets.isEmpty, !isFavoritingSelection else { return }
        let newlyFavorited = targets.filter { $0.isFavorite != true }.map(\.id)
        isFavoritingSelection = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            for photo in targets {
                _ = await store.setFavorite(photo.id, to: true)
            }
            isFavoritingSelection = false
            await loadPhotos()
            toast = LookToast(
                message: targets.count == 1 ? "Added to favorites" : "Added \(targets.count) to favorites",
                undo: newlyFavorited.isEmpty ? nil : {
                    Task {
                        for id in newlyFavorited {
                            _ = await store.setFavorite(id, to: false)
                        }
                        await loadPhotos()
                    }
                }
            )
        }
    }

    private func shareSelection() {
        let targets = selectedPhotos
        guard !targets.isEmpty, !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            var urls: [URL] = []
            for photo in targets {
                guard let data = try? await APIClient.shared.downloadJPEGData(photo.id) else { continue }
                let name = (photo.filename as NSString).deletingPathExtension + ".jpg"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: url)
                urls.append(url)
            }
            guard !urls.isEmpty else { return }
            shareItem = SelectionShareItem(urls: urls)
        }
    }
}
