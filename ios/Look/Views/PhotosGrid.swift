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
    let title: String
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

    // Scrubber
    @State private var scrubbing = false
    @State private var scrubFraction: CGFloat = 0
    @State private var scrubTitle = ""

    private let spacing = LookTheme.Spacing.hairline

    private var selectedPhotos: [Photo] {
        store.photos.filter { selectedPhotoIds.contains($0.id) }
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
        return order.map { key in
            PhotoSection(id: key, title: sectionTitle(forKey: key), photos: buckets[key] ?? [])
        }
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
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .lookScreenBackground()
            .toolbarBackground(LookTheme.ColorToken.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(LookTheme.ColorToken.paper, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
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
        }
    }

    // MARK: Gallery

    private func gallery(_ secs: [PhotoSection]) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let horizontalInset = LookTheme.Spacing.tight * 2
            let contentWidth = max(1, width - horizontalInset)
            let target = max(104, contentWidth / (width > 600 ? 4.8 : 3.35))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LookTheme.Spacing.tight, pinnedViews: [.sectionHeaders]) {
                        statusBanner

                        if store.isSyncing {
                            syncStatusStrip
                                .padding(.horizontal, LookTheme.Spacing.screen)
                                .padding(.top, LookTheme.Spacing.small)
                        }

                        ForEach(secs) { section in
                            Section {
                                ForEach(PhotoLayout.rows(for: section.photos, width: contentWidth,
                                                         target: target, spacing: spacing,
                                                         aspect: photoAspect)) { row in
                                    HStack(spacing: spacing) {
                                        ForEach(row.items) { item in
                                            cell(item, rowHeight: row.height)
                                        }
                                    }
                                }
                                .padding(.horizontal, LookTheme.Spacing.tight)
                            } header: {
                                sectionHeader(section)
                            }
                            .id(section.id)
                        }

                        galleryFooter
                    }
                    .padding(.top, LookTheme.Spacing.tight)
                }
                .background(LookTheme.ColorToken.darkroom.opacity(0.04))
                .refreshable { await store.syncNow() }
                .overlay(alignment: .trailing) { scrubber(secs, proxy: proxy) }
            }
        }
    }

    // MARK: Scrubber

    private func scrubber(_ secs: [PhotoSection], proxy: ScrollViewProxy) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let thumbY = max(0, min(h - 40, scrubFraction * h - 20))
            ZStack(alignment: .topTrailing) {
                if scrubbing {
                    Text(scrubTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LookTheme.ColorToken.graphite)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                        .offset(x: -34, y: thumbY)
                        .transition(.opacity)
                }
                Capsule()
                    .fill((scrubbing ? LookTheme.ColorToken.cyan : LookTheme.ColorToken.graphite).opacity(scrubbing ? 0.95 : 0.34))
                    .frame(width: 5, height: 40)
                    .padding(.trailing, 3)
                    .offset(y: thumbY)
                    .contentShape(Rectangle().inset(by: -16))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                scrubbing = true
                                let frac = min(max(v.location.y / h, 0), 1)
                                scrubFraction = frac
                                let idx = min(secs.count - 1, max(0, Int(frac * CGFloat(secs.count))))
                                scrubTitle = secs[idx].title
                                proxy.scrollTo(secs[idx].id, anchor: .top)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.3)) { scrubbing = false }
                            }
                    )
            }
        }
        .frame(width: 44)
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
                    .font(.caption2.weight(.bold))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: photo, selected: isSelected))
        .accessibilityHint(selectionMode ? "Double tap to \(isSelected ? "remove from" : "add to") selection" : "Double tap to open photo")
        .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
        .onAppear { store.loadMoreIfNeeded(currentPhoto: photo) }
        .onTapGesture {
            if selectionMode { toggleSelection(photo) } else { selectedPhoto = photo }
        }
        .contextMenu {
            Button {
                selectedPhotoIds = [photo.id]
                showAddToAlbum = true
            } label: {
                Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
            }
        }
    }

    private func sectionHeader(_ section: PhotoSection) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: LookTheme.Spacing.small) {
            Text(section.title.uppercased())
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(LookTheme.ColorToken.graphite.opacity(0.72))

            Text("\(section.photos.count)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(LookTheme.ColorToken.graphite.opacity(0.55))
                .monospacedDigit()

            Spacer()
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.top, LookTheme.Spacing.medium)
        .padding(.bottom, LookTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LookTheme.ColorToken.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LookTheme.ColorToken.mist)
                .frame(height: 1)
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
                title: store.photos.isEmpty ? "No photos yet" : "No matches",
                systemImage: store.photos.isEmpty ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle",
                message: store.photos.isEmpty ? "Import photos on the server to begin." : "Adjust the filter to return to the full library.",
                actionTitle: store.photos.isEmpty ? "Sync Library" : nil,
                action: store.photos.isEmpty ? { Task { await store.syncNow() } } : nil
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

    private var galleryFooter: some View {
        VStack(spacing: LookTheme.Spacing.small) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(footerText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            if !store.isSyncing, let message = store.lastSyncMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if store.hasMorePhotos && !store.isLoading {
                Label("More photos load as you scroll", systemImage: "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LookTheme.Spacing.large)
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

    private var footerText: String {
        if filter == .all {
            return "\(store.photos.count) of \(store.totalPhotos) photos loaded"
        }
        return "\(visiblePhotos.count) matching, \(store.photos.count) of \(store.totalPhotos) photos loaded"
    }

    private var syncStatusStrip: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(spacing: LookTheme.Spacing.small) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LookTheme.ColorToken.cyan)
                    .frame(width: 16)

                Text("Syncing library")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let fraction = store.syncProgressFraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Text("Working")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Text(store.syncProgressMessage ?? "Importing and updating thumbnails")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Button {
                    store.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
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
            .font(.caption)
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
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private var selectionActionBar: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                Text("\(visiblePhotos.count) visible")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if selectionMode {
                Button("Cancel") {
                    selectionMode = false
                    selectedPhotoIds.removeAll()
                }
            }
        }
        ToolbarItem(placement: .principal) {
            if selectionMode {
                Text(selectionSummary)
                    .font(.headline)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if selectionMode {
                Button(allVisiblePhotosSelected ? "Clear" : "All") {
                    toggleVisibleSelection()
                }
                .disabled(visiblePhotos.isEmpty)
            } else {
                Button("Select") {
                    selectionMode = true
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
                    Image(systemName: "ellipsis.circle")
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

private func dayKey(_ photo: Photo) -> String {
    let date = photoDate(photo)
    if date == .distantPast { return "unknown" }
    return dayKeyFormatter.string(from: date)
}

private func sectionTitle(forKey key: String) -> String {
    guard key != "unknown", let date = dayKeyFormatter.date(from: key) else { return "Undated" }
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let f = DateFormatter()
    if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
        f.dateFormat = "EEEE, MMM d"
    } else {
        f.dateFormat = "EEEE, MMM d, yyyy"
    }
    return f.string(from: date)
}

// MARK: - Immersive viewer

struct NativePhotoViewer: View {
    let photos: [Photo]
    let initialPhoto: Photo

    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String
    @State private var showInfo = false
    @State private var showAddToAlbum = false
    @State private var chromeHidden = false

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

            TabView(selection: $currentId) {
                ForEach(photos) { photo in
                    FullScreenImage(
                        photo: photo,
                        onTap: { withAnimation(.easeInOut(duration: 0.2)) { chromeHidden.toggle() } },
                        onDismiss: { dismiss() },
                        onInfo: { showInfo = true }
                    )
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .accessibilityLabel("Close viewer")

            VStack(alignment: .leading, spacing: 2) {
                Text(currentPhoto.filename)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Menu {
                Button { showAddToAlbum = true } label: {
                    Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                }
                Button { showInfo = true } label: {
                    Label("Info & Tags", systemImage: "info.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .accessibilityLabel("Photo actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.35))
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filmstripPhotos) { photo in
                        CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256),
                                        maxPixel: 162)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(photo.id == currentId ? .white : .clear, lineWidth: 2)
                            }
                            .id(photo.id)
                            .onTapGesture { withAnimation { currentId = photo.id } }
                            .accessibilityLabel(filmstripAccessibilityLabel(for: photo))
                            .accessibilityAddTraits(photo.id == currentId ? [.isImage, .isSelected] : .isImage)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.black.opacity(0.45))
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
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
