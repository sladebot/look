import SwiftUI

// MARK: - Sectioning + justified layout
//
// Aspect ratios come straight from the DB (backfilled for RAW). Keeping this a
// pure function — rather than an @Published store updated per decoded thumbnail
// — is what keeps scrolling smooth: the grid never re-justifies mid-scroll.
private func photoAspect(_ photo: Photo) -> CGFloat {
    if let w = photo.width, let h = photo.height, w > 0, h > 0 {
        return CGFloat(w) / CGFloat(h)
    }
    return 1.0
}

struct PhotoSection: Identifiable {
    let id: String
    let photos: [Photo]
}

struct JustifiedRow: Identifiable {
    let id = UUID()
    let items: [JustifiedItem]
    let height: CGFloat
}

struct JustifiedItem: Identifiable {
    var id: String { photo.id }
    let photo: Photo
    let width: CGFloat
}

enum PhotoLayout {
    /// Greedy justified packing: fill each row to the container width at a
    /// shared row height, scaling the last row down so it never over-stretches.
    static func rows(for photos: [Photo],
                     width: CGFloat,
                     target: CGFloat,
                     spacing: CGFloat,
                     aspect: (Photo) -> CGFloat) -> [JustifiedRow] {
        guard width > 0 else { return [] }
        var rows: [JustifiedRow] = []
        var current: [Photo] = []
        var aspectSum: CGFloat = 0

        func flush(stretch: Bool) {
            guard !current.isEmpty else { return }
            let gaps = CGFloat(current.count - 1) * spacing
            var height = (width - gaps) / max(aspectSum, 0.0001)
            if !stretch { height = min(height, target) }
            let items = current.map { JustifiedItem(photo: $0, width: aspect($0) * height) }
            rows.append(JustifiedRow(items: items, height: height))
            current = []
            aspectSum = 0
        }

        for photo in photos {
            current.append(photo)
            aspectSum += aspect(photo)
            let gaps = CGFloat(current.count - 1) * spacing
            if aspectSum * target + gaps >= width {
                flush(stretch: true)
            }
        }
        flush(stretch: false)
        return rows
    }
}

// MARK: - Photos tab

struct PhotosGrid: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPhoto: Photo?
    @State private var selectionMode = false
    @State private var selectedPhotoIds: Set<String> = []
    @State private var showAddToAlbum = false
    @State private var showCreateAlbum = false
    @State private var filter = PhotoGridFilter.all
    @State private var sort = PhotoGridSort.newest
    @State private var selectionShare: SelectionShareItem?
    @State private var toast: LookToast?
    @State private var isPreparingSelectionShare = false
    @State private var isFavoritingSelection = false
    @Namespace private var viewerZoomNamespace
    /// Grid density, adjusted by pinching: 0 = dense, 1 = default, 2 = large.
    @AppStorage("photos_grid_zoom_step") private var gridZoomStep = 1

    private let spacing = LookTheme.Spacing.hairline
    private static let gridZoomFactors: [CGFloat] = [0.72, 1.0, 1.42]

    private var gridZoomFactor: CGFloat {
        Self.gridZoomFactors[min(max(gridZoomStep, 0), Self.gridZoomFactors.count - 1)]
    }

    private var selectedPhotos: [Photo] {
        store.photos.filter { selectedPhotoIds.contains($0.id) }
    }

    /// Root usage (the Photos tab of old) owns its NavigationStack and hides
    /// the navigation bar behind the in-scroll header. Pushed usage ("All
    /// photos" / quick sets from Home) renders inside the parent stack with a
    /// regular navigation bar.
    let isRootPage: Bool

    init(initialSelectedPhotoIds: Set<String> = [],
         isRootPage: Bool = true,
         initialFilter: PhotoGridFilter = .all) {
        self.isRootPage = isRootPage
        _selectionMode = State(initialValue: !initialSelectedPhotoIds.isEmpty)
        _selectedPhotoIds = State(initialValue: initialSelectedPhotoIds)
        _filter = State(initialValue: initialFilter)
    }

    private var selectedVisibleCount: Int {
        visiblePhotos.reduce(0) { count, photo in
            count + (selectedPhotoIds.contains(photo.id) ? 1 : 0)
        }
    }

    private var allVisiblePhotosSelected: Bool {
        !visiblePhotos.isEmpty && selectedVisibleCount == visiblePhotos.count
    }

    private var visiblePhotos: [Photo] {
        let filtered = store.photos.filter { photo in
            switch filter {
            case .all: return true
            case .favorites: return photo.isFavorite == true
            case .raw: return photo.mimeType == "image/x-raw"
            case .jpeg: return photo.mimeType != "image/x-raw"
            }
        }
        return filtered.sorted { lhs, rhs in
            switch sort {
            case .newest: return photoDate(lhs) > photoDate(rhs)
            case .oldest: return photoDate(lhs) < photoDate(rhs)
            case .name: return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
        }
    }

    /// Group photos into day buckets, preserving the active sort order.
    private var sections: [PhotoSection] {
        var order: [String] = []
        var buckets: [String: [Photo]] = [:]
        for photo in visiblePhotos {
            let key = dayKey(photo)
            if buckets[key] == nil { buckets[key] = []; order.append(key) }
            buckets[key]?.append(photo)
        }
        return order.map { key in PhotoSection(id: key, photos: buckets[key] ?? []) }
    }

    var body: some View {
        // Group once per body eval (cheap now that there's no per-thumbnail
        // @Published churn), then thread the result through the subviews.
        let secs = sections

        let core = Group {
            Group {
                if store.isLoading && store.photos.isEmpty {
                    loadingState
                } else if !store.serverConnected {
                    disconnectedState
                } else if secs.isEmpty {
                    emptyState
                } else {
                    gallery(secs)
                }
            }
            // Root: the photos are the page — no navigation bar; the in-scroll
            // header is the only chrome. Pushed: a regular inline-title bar.
            .toolbar(isRootPage ? .hidden : .visible, for: .navigationBar)
            .navigationTitle(isRootPage ? "" : pushedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isRootPage && !selectionMode {
                        Button("Select") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectionMode = true
                        }
                        .disabled(visiblePhotos.isEmpty)
                    } else if !isRootPage && selectionMode {
                        Button("Cancel") {
                            selectionMode = false
                            selectedPhotoIds.removeAll()
                        }
                    }
                }
            }
            .lookScreenBackground()
            .toolbarColorScheme(.dark, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if selectionMode {
                    selectionActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectionMode)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedPhotoIds.count)
            .fullScreenCover(item: $selectedPhoto) { photo in
                NativePhotoViewer(photos: visiblePhotos, initialPhoto: photo)
                    .modifier(LookZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
            }
            .sheet(isPresented: $showAddToAlbum, onDismiss: {
                selectionMode = false
                selectedPhotoIds.removeAll()
            }) {
                AddToAlbumSheet(photos: selectedPhotos)
            }
            .sheet(isPresented: $showCreateAlbum) {
                CreateAlbumSheet()
            }
            .sheet(item: $selectionShare) { item in
                ShareSheet(items: item.urls)
            }
            .lookToast($toast, bottomPadding: selectionMode ? 92 : 96)
            #if DEBUG
            .task(id: store.photos.count) { applyScreenshotSelectionIfNeeded() }
            #endif
        }

        return Group {
            if isRootPage {
                NavigationStack { core }
            } else {
                core
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var pushedTitle: String {
        filter == .all ? "All photos" : filter.title
    }

    #if DEBUG
    /// Screenshot tooling hook: LOOK_UI_SELECT_COUNT=N pre-selects the first N
    /// visible photos so multi-select can be captured without synthetic taps.
    private func applyScreenshotSelectionIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["LOOK_UI_SELECT_COUNT"],
              let count = Int(raw), count > 0,
              selectedPhotoIds.isEmpty, !visiblePhotos.isEmpty else { return }
        selectionMode = true
        selectedPhotoIds = Set(visiblePhotos.prefix(count).map(\.id))
    }
    #endif

    // MARK: Gallery

    private func gallery(_ secs: [PhotoSection]) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let horizontalInset = LookTheme.Spacing.tight * 2
            let contentWidth = max(1, width - horizontalInset)
            let target = targetRowHeight(containerWidth: width, contentWidth: contentWidth)
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: LookTheme.Spacing.tight,
                           pinnedViews: .sectionHeaders) {
                    if isRootPage {
                        pageHeader
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.small)
                    }

                    statusBanner

                    if filter != .all {
                        activeFilterStrip
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.tight)
                    }

                    if store.isSyncing {
                        syncInlineStatus
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.tight)
                    }

                    ForEach(secs) { section in
                        Section {
                            sectionGrid(section, contentWidth: contentWidth, containerWidth: width, target: target)
                                .padding(.horizontal, LookTheme.Spacing.tight)
                                .id(section.id)
                        } header: {
                            PhotoDateStrip(
                                title: displayDayTitle(for: section.id),
                                count: section.photos.count
                            )
                        }
                    }

                }
                .padding(.top, LookTheme.Spacing.tight)
                .padding(.bottom, 108)
                .background(LookTheme.ColorToken.canvas)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .background(LookTheme.ColorToken.canvas)
            .refreshable { await store.syncNow() }
            .simultaneousGesture(
                MagnificationGesture()
                    .onEnded { value in
                        let newStep: Int
                        if value > 1.18 {
                            newStep = min(gridZoomStep + 1, Self.gridZoomFactors.count - 1)
                        } else if value < 0.85 {
                            newStep = max(gridZoomStep - 1, 0)
                        } else {
                            return
                        }
                        guard newStep != gridZoomStep else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            gridZoomStep = newStep
                        }
                    }
            )
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(LookTheme.ColorToken.canvas.ignoresSafeArea())
    }

    /// Row height derives from the available width so cells stay in a sane
    /// size band at any container width (iPad full screen, Split View, Slide
    /// Over), instead of hardcoding a column count. Regular widths target
    /// ~180pt cells (HIG-comfortable); compact widths keep the denser phone
    /// layout. Pinch density scales the result in both regimes.
    private func targetRowHeight(containerWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        if containerWidth >= 700 {
            let columns = max(3, (contentWidth / 180).rounded())
            let base = (contentWidth - (columns - 1) * spacing) / columns
            return max(120, base * gridZoomFactor)
        }
        return max(88, contentWidth / 3.35 * gridZoomFactor)
    }

    @ViewBuilder
    private func sectionGrid(_ section: PhotoSection,
                             contentWidth: CGFloat,
                             containerWidth: CGFloat,
                             target: CGFloat) -> some View {
        if shouldUseUniformGrid(for: section, containerWidth: containerWidth) {
            uniformSectionGrid(section.photos, contentWidth: contentWidth, containerWidth: containerWidth)
        } else {
            justifiedSectionGrid(section.photos, contentWidth: contentWidth, target: target)
        }
    }

    private func shouldUseUniformGrid(for section: PhotoSection, containerWidth: CGFloat) -> Bool {
        containerWidth < 700 && visiblePhotos.count <= 24 && section.photos.count <= 18
    }

    @ViewBuilder
    private func uniformSectionGrid(_ photos: [Photo], contentWidth: CGFloat, containerWidth: CGFloat) -> some View {
        let baseColumns = containerWidth < 430 ? 3 : 4
        let columns = max(2, baseColumns + (gridZoomStep == 0 ? 1 : gridZoomStep == 2 ? -1 : 0))
        let cellWidth = floor((contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))

        ForEach(Array(stride(from: 0, to: photos.count, by: columns)), id: \.self) { start in
            let end = min(start + columns, photos.count)
            let rowPhotos = Array(photos[start..<end])
            HStack(spacing: spacing) {
                ForEach(rowPhotos) { photo in
                    cell(JustifiedItem(photo: photo, width: cellWidth), rowHeight: cellWidth)
                }
                if rowPhotos.count < columns {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func justifiedSectionGrid(_ photos: [Photo], contentWidth: CGFloat, target: CGFloat) -> some View {
        ForEach(PhotoLayout.rows(for: photos, width: contentWidth,
                                 target: target, spacing: spacing,
                                 aspect: photoAspect)) { row in
            HStack(spacing: spacing) {
                ForEach(row.items) { item in
                    cell(item, rowHeight: row.height)
                }
            }
        }
    }

    private func cell(_ item: JustifiedItem, rowHeight: CGFloat) -> some View {
        let photo = item.photo
        let isSelected = selectedPhotoIds.contains(photo.id)
        return CachedThumbnail(
            url: APIClient.shared.thumbnailURL(for: photo.id, size: 512),
            contentMode: .fill,
            maxPixel: rowHeight * 3
        )
        .frame(width: item.width, height: rowHeight)
        .background(LookTheme.ColorToken.backdrop)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if photo.isFavorite == true && !selectionMode {
                LookFavoriteBadge()
                    .padding(5)
            }
        }
        .overlay(alignment: .topLeading) {
            if !selectionMode {
                Text(photo.fileExtension.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(LookTheme.ColorToken.backdrop.opacity(0.82))
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if isSelected {
                Color.black.opacity(0.18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectionMode {
                LookSelectionBadge(isSelected: isSelected)
                    .padding(6)
            }
        }
        .overlay {
            if isSelected {
                Rectangle()
                    .strokeBorder(LookTheme.ColorToken.accent, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: photo, selected: isSelected))
        .accessibilityHint(selectionMode ? "Double tap to \(isSelected ? "remove from" : "add to") selection" : "Double tap to open photo")
        .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
        .onAppear { store.loadMoreIfNeeded(currentPhoto: photo) }
        .onTapGesture {
            if selectionMode { toggleSelection(photo) } else { selectedPhoto = photo }
        }
        .onLongPressGesture {
            guard !selectionMode else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectionMode = true
            selectedPhotoIds = [photo.id]
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            LookLoadingState(
                title: "Loading library",
                message: store.isSyncing ? "Sync is still running." : "Preparing the contact sheet."
            )
            if store.isSyncing {
                syncInlineStatus
                    .padding(.horizontal, LookTheme.Spacing.screen)
            }
        }
        .lookScreenBackground()
    }

    private var disconnectedState: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            LookEmptyState(
                title: "Server unavailable",
                systemImage: "wifi.slash",
                message: "Check Settings or retry the connection.",
                actionTitle: "Retry",
                action: { Task { await store.checkConnection() } }
            )
            if let message = store.errorMessage, !message.isEmpty {
                LookStatusBanner(
                    title: "Connection failed",
                    message: message,
                    tone: .error
                )
                .padding(.horizontal, LookTheme.Spacing.screen)
                .padding(.bottom, LookTheme.Spacing.screen)
            }
        }
        .lookScreenBackground()
    }

    private var emptyState: some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            LookEmptyState(
                title: store.photos.isEmpty ? "No photos yet" : "No \(filter.title.lowercased()) photos",
                systemImage: store.photos.isEmpty ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle",
                message: store.photos.isEmpty ? "Import photos on the server to begin." : "Nothing in the library matches the \(filter.title) filter.",
                actionTitle: store.photos.isEmpty ? "Sync Library" : "Show All Photos",
                action: store.photos.isEmpty
                    ? { Task { await store.syncNow() } }
                    : { withAnimation { filter = .all } }
            )
            if let message = store.errorMessage, !message.isEmpty {
                errorStatusStrip(message)
                    .padding(.horizontal, LookTheme.Spacing.screen)
            } else if let message = store.lastSyncMessage, isSyncWarning(message) {
                syncWarningStrip(message)
                    .padding(.horizontal, LookTheme.Spacing.screen)
            }
            if store.isSyncing {
                syncInlineStatus
                    .padding(.horizontal, LookTheme.Spacing.screen)
                    .padding(.bottom, LookTheme.Spacing.screen)
            }
        }
        .lookScreenBackground()
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let message = store.errorMessage, !message.isEmpty {
            errorStatusStrip(message)
                .padding(.horizontal, LookTheme.Spacing.screen)
                .padding(.bottom, LookTheme.Spacing.small)
        } else if let message = store.lastSyncMessage, isSyncWarning(message) {
            syncWarningStrip(message)
                .padding(.horizontal, LookTheme.Spacing.screen)
                .padding(.bottom, LookTheme.Spacing.small)
        }
    }

    private func errorStatusStrip(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LookTheme.ColorToken.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library needs attention")
                        .font(LookTheme.Typography.secondaryEmphasis)
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Button {
                    store.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(LookTheme.Typography.headline)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }

            HStack(spacing: LookTheme.Spacing.small) {
                Button {
                    Task {
                        await store.checkConnection()
                        await store.loadPhotos(reset: true)
                    }
                } label: {
                    Label("Retry Load", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await store.syncNow() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(store.isSyncing)
            }
            .font(LookTheme.Typography.secondary)
        }
        .padding(LookTheme.Spacing.medium)
        .background(LookTheme.ColorToken.elevated,
                    in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous)
                .stroke(LookTheme.ColorToken.danger.opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func syncWarningStrip(_ message: String) -> some View {
        LookStatusBanner(
            title: "Sync completed with issues",
            message: message,
            tone: .warning,
            actionTitle: "Retry",
            action: store.isSyncing ? nil : { Task { await store.syncNow() } }
        )
    }

    /// Visible reminder that the grid is filtered, with a one-tap way out —
    /// otherwise an active Favorites/RAW filter silently "hides" the library.
    private var activeFilterStrip: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            LookChip(title: "\(filter.title) only",
                     systemImage: filter.systemImage,
                     tint: LookTheme.ColorToken.accent)
            Text(visiblePhotos.count == 1 ? "1 photo" : "\(visiblePhotos.count) photos")
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
            Spacer()
            Button("Show All") {
                withAnimation { filter = .all }
            }
            .font(LookTheme.Typography.secondaryEmphasis)
            .buttonStyle(.bordered)
            .tint(LookTheme.ColorToken.accent)
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .combine)
    }

    /// Bottom selection bar: count in .headline plus fully labeled actions.
    /// ViewThatFits drops to a vertical stack when Dynamic Type or narrow
    /// widths would clip the horizontal row.
    private var selectionActionBar: some View {
        VStack(spacing: LookTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
                Text(selectionSummary)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: LookTheme.Spacing.tight)

                Button(allVisiblePhotosSelected ? "Deselect All" : "Select All") {
                    toggleVisibleSelection()
                }
                .font(LookTheme.Typography.secondaryEmphasis)
                .tint(LookTheme.ColorToken.accent)
                .disabled(visiblePhotos.isEmpty)
                .frame(minHeight: 44)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LookTheme.Spacing.small) {
                    selectionActionButtons
                }
                VStack(spacing: LookTheme.Spacing.small) {
                    selectionActionButtons
                }
            }
        }
        .padding(LookTheme.Spacing.medium)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous)
                .stroke(LookTheme.ColorToken.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.bottom, LookTheme.Spacing.tight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        Button {
            showAddToAlbum = true
        } label: {
            Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                .font(LookTheme.Typography.secondaryEmphasis)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .tint(LookTheme.ColorToken.accentControl)
        .disabled(selectedPhotoIds.isEmpty)

        Button {
            favoriteSelectedPhotos()
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
            shareSelectedPhotos()
        } label: {
            Label(isPreparingSelectionShare ? "Preparing…" : "Share",
                  systemImage: "square.and.arrow.up")
                .font(LookTheme.Typography.secondaryEmphasis)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(LookTheme.ColorToken.accent)
        .disabled(selectedPhotoIds.isEmpty || isPreparingSelectionShare)
        .accessibilityLabel(isPreparingSelectionShare ? "Preparing photos to share" : "Share selected photos")
    }

    private func favoriteSelectedPhotos() {
        let ids = selectedPhotoIds
        guard !ids.isEmpty, !isFavoritingSelection else { return }
        // Only photos that weren't already favorites get reverted by Undo.
        let newlyFavorited = selectedPhotos.filter { $0.isFavorite != true }.map(\.id)
        isFavoritingSelection = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            for id in ids {
                _ = await store.setFavorite(id, to: true)
            }
            isFavoritingSelection = false
            toast = LookToast(
                message: ids.count == 1 ? "Added to favorites" : "Added \(ids.count) to favorites",
                undo: newlyFavorited.isEmpty ? nil : {
                    Task {
                        for id in newlyFavorited {
                            _ = await store.setFavorite(id, to: false)
                        }
                    }
                }
            )
        }
    }

    private func shareSelectedPhotos() {
        let photosToShare = selectedPhotos
        guard !photosToShare.isEmpty, !isPreparingSelectionShare else { return }
        isPreparingSelectionShare = true
        Task {
            defer { isPreparingSelectionShare = false }
            var urls: [URL] = []
            for photo in photosToShare {
                guard let data = try? await APIClient.shared.downloadJPEGData(photo.id) else { continue }
                let name = (photo.filename as NSString).deletingPathExtension + ".jpg"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: url)
                urls.append(url)
            }
            guard !urls.isEmpty else { return }
            selectionShare = SelectionShareItem(urls: urls)
        }
    }

    private var selectionSummary: String {
        let count = selectedPhotoIds.count
        return count == 1 ? "1 photo selected" : "\(count) photos selected"
    }

    private var navigationSubtitle: String {
        if selectionMode {
            return "\(selectedVisibleCount) of \(visiblePhotos.count) visible"
        }
        if store.isSyncing {
            return "Syncing \(store.totalPhotos.formatted()) photos"
        }
        let count = store.totalPhotos > 0 ? store.totalPhotos : visiblePhotos.count
        let filterContext = filter == .all ? "Private library" : filter.title
        return "\(count.formatted()) photos • \(filterContext)"
    }

    // MARK: Toolbar

    /// Large in-scroll header: the only chrome the page carries.
    /// Browse: title + count with quiet Select / menu. Selection: summary + Cancel.
    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionMode ? selectionSummary : "Photos")
                    .font(LookTheme.Typography.display)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .contentTransition(.numericText())
                Text(navigationSubtitle)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: LookTheme.Spacing.small)

            if selectionMode {
                Button("Cancel") {
                    selectionMode = false
                    selectedPhotoIds.removeAll()
                }
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.accent)
            } else {
                Button("Select") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectionMode = true
                }
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.accent)
                .disabled(visiblePhotos.isEmpty)
                .accessibilityHint("Enters selection mode")

                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(PhotoGridFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Picker("Sort", selection: $sort) {
                        ForEach(PhotoGridSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Divider()
                    Button { showCreateAlbum = true } label: {
                        Label("New Album", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        Task { await store.syncNow() }
                    } label: {
                        Label(store.isSyncing ? "Syncing" : "Sync and Import",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.isSyncing)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .frame(width: 40, height: 40, alignment: .trailing)
                        .overlay(alignment: .topTrailing) {
                            if store.isSyncing {
                                Circle()
                                    .fill(LookTheme.ColorToken.accent)
                                    .frame(width: 7, height: 7)
                            }
                        }
                }
                .accessibilityLabel("More options")
            }
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(LookTheme.ColorToken.warning)
                .frame(width: 30, height: 3)
                .offset(y: -8)
                .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.18), value: selectionMode)
    }

    /// One quiet line replaces the old 72pt sync card.
    private var syncInlineStatus: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            ProgressView()
                .controlSize(.small)
                .tint(LookTheme.ColorToken.accent)
            Text(syncInlineText)
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var syncInlineText: String {
        if let fraction = store.syncProgressFraction {
            let percent = Int((fraction * 100).rounded())
            return "Syncing · \(percent)%"
        }
        return store.syncProgressMessage ?? "Syncing library"
    }

    private func toggleSelection(_ photo: Photo) {
        if selectedPhotoIds.contains(photo.id) {
            selectedPhotoIds.remove(photo.id)
        } else {
            selectedPhotoIds.insert(photo.id)
        }
    }

    private func toggleVisibleSelection() {
        if allVisiblePhotosSelected {
            selectedPhotoIds.subtract(visiblePhotos.map(\.id))
        } else {
            selectedPhotoIds.formUnion(visiblePhotos.map(\.id))
        }
    }

    private func isSyncWarning(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("error") || lowercased.contains("failed")
    }

    private func accessibilityLabel(for photo: Photo, selected: Bool) -> String {
        var parts = [photo.filename]
        if photo.isFavorite == true { parts.append("favorite") }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

/// Day header, pinned while its section scrolls. Instead of a full-width bar,
/// the title and count sit in compact capsule scrims (.thinMaterial just behind
/// the text) so they stay legible as photos pass underneath without striping
/// the grid — the difference is most visible on iPad's wide rows.
private struct PhotoDateStrip: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            Text("●")
                .font(.system(size: 7))
                .foregroundStyle(LookTheme.ColorToken.warning)
                .accessibilityHidden(true)
            Text(title)
                .font(LookTheme.Typography.captionEmphasis)
                .foregroundStyle(LookTheme.ColorToken.primaryText)

            Spacer(minLength: LookTheme.Spacing.small)

            Text(String(format: "%02d EXP", count))
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.vertical, LookTheme.Spacing.tight)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LookTheme.ColorToken.separator).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) photos")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Filter / sort

/// Wraps prepared temp-file URLs so the multi-photo share sheet can be
/// presented via `.sheet(item:)`.
struct SelectionShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

enum PhotoGridFilter: String, CaseIterable, Identifiable {
    case all, favorites, raw, jpeg
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .raw: return "RAW"
        case .jpeg: return "JPEG"
        }
    }
    var systemImage: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .favorites: return "heart"
        case .raw: return "camera.aperture"
        case .jpeg: return "photo"
        }
    }
}

private enum PhotoGridSort: String, CaseIterable, Identifiable {
    case newest, oldest, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .name: return "Name"
        }
    }
    var systemImage: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .name: return "textformat"
        }
    }
}

// MARK: - Date helpers

private func photoDate(_ photo: Photo) -> Date {
    guard let raw = photo.createdAt else { return .distantPast }
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: raw) { return date }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let date = formatter.date(from: raw) { return date }
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: raw) ?? .distantPast
}

private let dayKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let displayDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    return f
}()

private let displayDayWithYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return f
}()

private func dayKey(_ photo: Photo) -> String {
    let date = photoDate(photo)
    if date == .distantPast { return "unknown" }
    return dayKeyFormatter.string(from: date)
}

private func displayDayTitle(for key: String) -> String {
    guard key != "unknown", let date = dayKeyFormatter.date(from: key) else {
        return "Unknown date"
    }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
        return displayDayFormatter.string(from: date)
    }
    return displayDayWithYearFormatter.string(from: date)
}

// MARK: - Immersive viewer

struct NativePhotoViewer: View {
    let photos: [Photo]
    let initialPhoto: Photo

    @EnvironmentObject private var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String
    @State private var showInfo = false
    @State private var showAddToAlbum = false
    @State private var chromeHidden = false
    /// Local favorite state for photos outside store.photos (albums, search).
    @State private var favoriteOverrides: [String: Bool] = [:]
    @State private var shareItem: ShareItem?
    @State private var isPreparingShare = false

    init(photos: [Photo], initialPhoto: Photo) {
        self.photos = photos
        self.initialPhoto = initialPhoto
        _currentId = State(initialValue: initialPhoto.id)
    }

    private var currentIndex: Int {
        photos.firstIndex(where: { $0.id == currentId }) ?? 0
    }

    private var currentPhoto: Photo {
        photos[safe: currentIndex] ?? initialPhoto
    }

    private var filmstripPhotos: [Photo] {
        guard !photos.isEmpty else { return [] }
        let radius = 18
        let lowerBound = max(0, currentIndex - radius)
        let upperBound = min(photos.count, currentIndex + radius + 1)
        return Array(photos[lowerBound..<upperBound])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FullScreenImage(
                photo: currentPhoto,
                isActive: true,
                canGoPrevious: currentIndex > 0,
                canGoNext: currentIndex < photos.count - 1,
                onTap: { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } },
                onDismiss: { dismiss() },
                onInfo: { showInfo = true },
                onPrevious: showPrevious,
                onNext: showNext
            )
            .id(currentPhoto.id)
            .accessibilityAction(.magicTap) {
                withAnimation(.easeInOut(duration: 0.18)) { showNext() }
            }
            .padding(.top, chromeHidden ? 0 : 42)
            .padding(.bottom, chromeHidden ? 0 : 158)
            .animation(.easeInOut(duration: 0.2), value: chromeHidden)
            .ignoresSafeArea()

            VStack {
                if !chromeHidden { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if !chromeHidden { bottomChrome.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }

            if isPreparingShare {
                preparingShareOverlay
            }
        }
        .statusBarHidden(chromeHidden)
        #if DEBUG
        .task {
            // Screenshot tooling: LOOK_UI_VIEWER_INFO=1 opens the info panel.
            if ProcessInfo.processInfo.environment["LOOK_UI_VIEWER_INFO"] == "1" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                showInfo = true
            }
        }
        #endif
        .sheet(isPresented: $showInfo) {
            // Pull-up info panel: half-height by default so the photo stays
            // visible and swipeable behind it; expands to full when needed.
            PhotoDetail(photo: currentPhoto, embedsInViewer: true)
                .id(currentPhoto.id)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToAlbum) { AddToAlbumSheet(photo: currentPhoto) }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .task(id: currentId) {
            await prefetchAdjacentPreviews()
        }
    }

    private var isCurrentFavorite: Bool {
        if let override = favoriteOverrides[currentId] { return override }
        if let inStore = store.photos.first(where: { $0.id == currentId }) {
            return inStore.isFavorite ?? false
        }
        return currentPhoto.isFavorite ?? false
    }

    private func toggleFavorite() {
        let photoId = currentId
        let newValue = !isCurrentFavorite
        favoriteOverrides[photoId] = newValue
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let accepted = await store.setFavorite(photoId, to: newValue)
            if !accepted {
                favoriteOverrides[photoId] = !newValue
            } else if store.photos.contains(where: { $0.id == photoId }) {
                // Store is now the source of truth; drop the local override so
                // later changes (e.g. from the detail sheet) aren't masked.
                favoriteOverrides[photoId] = nil
            }
        }
    }

    private func shareCurrentPhoto() {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        let photo = currentPhoto
        Task {
            defer { isPreparingShare = false }
            guard let data = try? await APIClient.shared.downloadJPEGData(photo.id) else { return }
            let name = (photo.filename as NSString).deletingPathExtension + ".jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            shareItem = ShareItem(url: url)
        }
    }

    private func showPrevious() {
        guard currentIndex > 0 else { return }
        currentId = photos[currentIndex - 1].id
    }

    private func showNext() {
        guard currentIndex < photos.count - 1 else { return }
        currentId = photos[currentIndex + 1].id
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                .accessibilityLabel("Close viewer")

                Spacer()
            }

            VStack(spacing: 2) {
                Text(currentPhoto.filename)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 60)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.7), .black.opacity(0.62), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    /// Filmstrip plus a labeled action bar, stacked over a shared bottom
    /// gradient. Actions are always-visible 44pt labeled buttons on material —
    /// no menu digging for favorite/share/album/info.
    private var bottomChrome: some View {
        VStack(spacing: LookTheme.Spacing.small) {
            filmstrip
            bottomActionBar
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.45), .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: LookTheme.Spacing.tight) {
            viewerActionButton(
                title: "Favorite",
                systemImage: isCurrentFavorite ? "heart.fill" : "heart",
                iconTint: isCurrentFavorite ? Color.pink : .white,
                accessibility: isCurrentFavorite ? "Remove from favorites" : "Add to favorites"
            ) { toggleFavorite() }

            viewerActionButton(
                title: "Share",
                systemImage: "square.and.arrow.up",
                accessibility: "Share photo",
                disabled: isPreparingShare
            ) { shareCurrentPhoto() }

            viewerActionButton(
                title: "Album",
                systemImage: "rectangle.stack.badge.plus",
                accessibility: "Add to album"
            ) { showAddToAlbum = true }

            viewerActionButton(
                title: "Info",
                systemImage: "info.circle",
                accessibility: "Info and tags"
            ) { showInfo = true }
        }
        .padding(.horizontal, LookTheme.Spacing.small)
        .padding(.vertical, LookTheme.Spacing.tight)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func viewerActionButton(title: String,
                                    systemImage: String,
                                    iconTint: Color = .white,
                                    accessibility: String,
                                    disabled: Bool = false,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(iconTint)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(accessibility)
    }

    /// Material scrim while the share JPEG downloads — replaces the old
    /// caption-sized menu label state.
    private var preparingShareOverlay: some View {
        VStack(spacing: LookTheme.Spacing.small) {
            ProgressView()
                .tint(.white)
            Text("Preparing photo to share…")
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(LookTheme.Spacing.large)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(filmstripPhotos) { photo in
                        CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256),
                                        maxPixel: 162)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(photo.id == currentId ? LookTheme.ColorToken.accent : .clear, lineWidth: 3)
                            }
                            .shadow(color: .black.opacity(photo.id == currentId ? 0.34 : 0), radius: 8, y: 4)
                            .id(photo.id)
                            .onTapGesture { withAnimation { currentId = photo.id } }
                            .accessibilityLabel(filmstripAccessibilityLabel(for: photo))
                            .accessibilityAddTraits(photo.id == currentId ? [.isImage, .isSelected] : .isImage)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 84)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .environment(\.colorScheme, .dark)
            .onChange(of: currentId) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(currentId, anchor: .center) }
        }
    }

    private func filmstripAccessibilityLabel(for photo: Photo) -> String {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else {
            return photo.filename
        }
        let state = photo.id == currentId ? ", selected" : ""
        return "\(photo.filename), \(index + 1) of \(photos.count)\(state)"
    }

    private func prefetchAdjacentPreviews() async {
        guard !photos.isEmpty else { return }
        let lowerBound = max(0, currentIndex - 2)
        let upperBound = min(photos.count, currentIndex + 3)
        let candidates = photos[lowerBound..<upperBound].filter { $0.id != currentId }

        await withTaskGroup(of: Void.self) { group in
            for photo in candidates {
                let url = APIClient.shared.previewImageURL(for: photo.id, size: 1600)
                group.addTask {
                    _ = await PreviewImageLoader.shared.image(
                        for: url,
                        maxPixel: 2_400,
                        retryQueued: true,
                        attempts: 2
                    )
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
