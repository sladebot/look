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

    @State private var selectedPhoto: Photo?
    @State private var selectionMode = false
    @State private var selectedPhotoIds: Set<String> = []
    @State private var showAddToAlbum = false
    @State private var showCreateAlbum = false
    @State private var filter = PhotoGridFilter.all
    @State private var sort = PhotoGridSort.newest
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

    init(initialSelectedPhotoIds: Set<String> = []) {
        _selectionMode = State(initialValue: !initialSelectedPhotoIds.isEmpty)
        _selectedPhotoIds = State(initialValue: initialSelectedPhotoIds)
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

        return NavigationStack {
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
            .navigationTitle(selectionMode ? selectionSummary : "Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .lookScreenBackground()
            .toolbarBackground(.automatic, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if selectionMode {
                    selectionActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectionMode)
            .animation(.easeInOut(duration: 0.18), value: selectedPhotoIds.count)
            .fullScreenCover(item: $selectedPhoto) { photo in
                NativePhotoViewer(photos: visiblePhotos, initialPhoto: photo)
                    .modifier(PhotoZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
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
            #if DEBUG
            .task(id: store.photos.count) { applyScreenshotSelectionIfNeeded() }
            #endif
        }
        .ignoresSafeArea(.container, edges: .bottom)
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
                    statusBanner

                    if filter != .all {
                        activeFilterStrip
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.tight)
                    }

                    if store.isSyncing {
                        syncStatusStrip
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.small)
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
                .background(LookTheme.ColorToken.paper)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .background(LookTheme.ColorToken.paper)
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
        .background(LookTheme.ColorToken.paper.ignoresSafeArea())
    }

    private func targetRowHeight(containerWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        return max(88, contentWidth / (containerWidth > 600 ? 4.8 : 3.35) * gridZoomFactor)
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
        .background(LookTheme.ColorToken.darkroom)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if photo.isFavorite == true && !selectionMode {
                Image(systemName: "heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    .padding(6)
            }
        }
        .overlay {
            if isSelected {
                Color.black.opacity(0.18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.9),
                                     isSelected ? LookTheme.ColorToken.cyan : .black.opacity(0.38))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .padding(6)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(LookTheme.ColorToken.cyan)
                    .frame(width: 5)
            }
        }
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(LookTheme.ColorToken.cyan, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .modifier(PhotoZoomSource(id: photo.id, namespace: viewerZoomNamespace))
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
                syncStatusStrip
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
                syncStatusStrip
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

    private var syncStatusStrip: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(spacing: LookTheme.Spacing.small) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(LookTheme.Typography.captionEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.cyan)
                    .frame(width: 16)

                Text("Syncing library")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let fraction = store.syncProgressFraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(LookTheme.Typography.captionEmphasis)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Text("Working")
                        .font(LookTheme.Typography.captionEmphasis)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Text(store.syncProgressMessage ?? "Importing and updating thumbnails")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let fraction = store.syncProgressFraction {
                StableSyncProgressBar(value: fraction)
            } else {
                StableSyncProgressBar(value: nil)
            }
        }
        .padding(.horizontal, LookTheme.Spacing.medium)
        .padding(.vertical, LookTheme.Spacing.small)
        .frame(minHeight: 72, alignment: .center)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.cyan.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorStatusStrip(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LookTheme.ColorToken.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library needs attention")
                        .font(LookTheme.Typography.secondaryEmphasis)
                    Text(message)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Button {
                    store.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
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
        .background(LookTheme.ColorToken.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.danger.opacity(0.26), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func syncWarningStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(LookTheme.ColorToken.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sync completed with issues")
                    .font(LookTheme.Typography.secondaryEmphasis)
                Text(message)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.syncNow() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isSyncing)
            .accessibilityLabel("Retry sync")
        }
        .padding(LookTheme.Spacing.medium)
        .background(LookTheme.ColorToken.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.amber.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Visible reminder that the grid is filtered, with a one-tap way out —
    /// otherwise an active Favorites/RAW filter silently "hides" the library.
    private var activeFilterStrip: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            LookChip(title: "\(filter.title) only",
                     systemImage: filter.systemImage,
                     tint: LookTheme.ColorToken.cyan)
            Text(visiblePhotos.count == 1 ? "1 photo" : "\(visiblePhotos.count) photos")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
            Spacer()
            Button("Show All") {
                withAnimation { filter = .all }
            }
            .font(LookTheme.Typography.captionEmphasis)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectionActionBar: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedPhotoIds.count) selected")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                Text("\(visiblePhotos.count) visible")
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
            }
            .lineLimit(1)

            Spacer(minLength: LookTheme.Spacing.tight)

            Button {
                toggleVisibleSelection()
            } label: {
                Label(allVisiblePhotosSelected ? "Clear" : "Select All",
                      systemImage: allVisiblePhotosSelected ? "xmark.circle" : "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(visiblePhotos.isEmpty)
            .controlSize(.small)

            Button {
                showAddToAlbum = true
            } label: {
                Label("Add", systemImage: "rectangle.stack.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(LookTheme.ColorToken.cyan)
            .disabled(selectedPhotoIds.isEmpty)
            .controlSize(.small)
        }
        .padding(.horizontal, LookTheme.Spacing.medium)
        .padding(.vertical, LookTheme.Spacing.small)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.mist, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.bottom, LookTheme.Spacing.tight)
        .accessibilityElement(children: .contain)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            LookNavTitle(
                title: selectionMode ? selectionSummary : "Photos",
                subtitle: navigationSubtitle
            )
        }
        ToolbarItem(placement: .topBarLeading) {
            if selectionMode {
                Button("Cancel") {
                    selectionMode = false
                    selectedPhotoIds.removeAll()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if selectionMode {
                Button(allVisiblePhotosSelected ? "Clear" : "All") {
                    toggleVisibleSelection()
                }
                .disabled(visiblePhotos.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !selectionMode {
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
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        .overlay(alignment: .topTrailing) {
                            if store.isSyncing {
                                Circle()
                                    .fill(LookTheme.ColorToken.cyan)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
            }
        }
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

/// Opening a photo zooms out of its grid cell (Photos-style) on iOS 18+;
/// earlier systems keep the default cover presentation.
private struct PhotoZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct PhotoZoomTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

/// Day header, pinned while its section scrolls; the material backdrop keeps it
/// legible as photos pass underneath.
private struct PhotoDateStrip: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
            Text(title)
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.graphite)
            Spacer()
            Text(count == 1 ? "1 photo" : "\(count.formatted()) photos")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.vertical, LookTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) photos")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct StableSyncProgressBar: View {
    let value: Double?

    private var clampedValue: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LookTheme.ColorToken.mist)

                if let value {
                    Capsule()
                        .fill(LookTheme.ColorToken.cyan)
                        .frame(width: max(6, proxy.size.width * clampedValue))
                        .animation(nil, value: value)
                } else {
                    Capsule()
                        .fill(LookTheme.ColorToken.cyan.opacity(0.75))
                        .frame(width: max(36, proxy.size.width * 0.28))
                        .offset(x: proxy.size.width * 0.16)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Filter / sort

private enum PhotoGridFilter: String, CaseIterable, Identifiable {
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
    f.dateFormat = "EEEE, MMM d"
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
            .padding(.bottom, chromeHidden ? 0 : 104)
            .animation(.easeInOut(duration: 0.2), value: chromeHidden)
            .ignoresSafeArea()

            VStack {
                if !chromeHidden { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                if !chromeHidden { filmstrip.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
        }
        .statusBarHidden(chromeHidden)
        .sheet(isPresented: $showInfo) { PhotoDetail(photo: currentPhoto) }
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
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Close viewer")

                Spacer()

                HStack(spacing: 10) {
                    Button { toggleFavorite() } label: {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isCurrentFavorite ? Color.pink : .white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(isCurrentFavorite ? "Remove from favorites" : "Add to favorites")

                    Menu {
                        Button { showAddToAlbum = true } label: {
                            Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                        }
                        Button { shareCurrentPhoto() } label: {
                            Label(isPreparingShare ? "Preparing…" : "Share Photo",
                                  systemImage: "square.and.arrow.up")
                        }
                        .disabled(isPreparingShare)
                        Button { showInfo = true } label: {
                            Label("Info & Tags", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.16), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Photo actions")
                }
            }

            VStack(spacing: 2) {
                Text(currentPhoto.filename)
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(LookTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 104)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
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
                                    .stroke(photo.id == currentId ? .white : .clear, lineWidth: 2)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.42), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            }
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
