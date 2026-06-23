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

    private let spacing: CGFloat = 2

    private var selectedPhotos: [Photo] {
        store.photos.filter { selectedPhotoIds.contains($0.id) }
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
            .toolbar { toolbarContent }
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
            let target = max(96, width / (width > 600 ? 4.6 : 3.4))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(secs) { section in
                            Section {
                                ForEach(PhotoLayout.rows(for: section.photos, width: width,
                                                         target: target, spacing: spacing,
                                                         aspect: photoAspect)) { row in
                                    HStack(spacing: spacing) {
                                        ForEach(row.items) { item in
                                            cell(item, rowHeight: row.height)
                                        }
                                    }
                                    .padding(.bottom, spacing)
                                }
                            } header: {
                                sectionHeader(section.title)
                            }
                            .id(section.id)
                        }

                        Text("\(visiblePhotos.count) of \(store.totalPhotos) photos")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)

                        if store.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
                    }
                }
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
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .shadow(radius: 3)
                        .offset(x: -34, y: thumbY)
                        .transition(.opacity)
                }
                Capsule()
                    .fill(Color.secondary.opacity(scrubbing ? 0.95 : 0.3))
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
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if photo.isFavorite == true && !selectionMode {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.9),
                                     isSelected ? .blue : .black.opacity(0.35))
                    .padding(5)
            }
        }
        .overlay {
            if isSelected {
                Rectangle().stroke(.blue, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
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

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    // MARK: States

    private var loadingState: some View {
        VStack {
            ProgressView()
            Text("Loading photos...").font(.caption).foregroundColor(.secondary)
        }
    }

    private var disconnectedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash").font(.largeTitle).foregroundColor(.secondary)
            Text("Cannot connect to Look server").font(.headline)
            Text("Check server URL in Settings").font(.caption).foregroundColor(.secondary)
            Button("Retry") { Task { await store.checkConnection() } }
                .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundColor(.secondary)
            Text(store.photos.isEmpty ? "No photos found" : "No photos match this filter")
                .font(.headline)
            Text(store.photos.isEmpty ? "Import photos on the Look server first" : "Clear filters to see the full library")
                .font(.caption).foregroundColor(.secondary)
        }
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
        ToolbarItem(placement: .topBarTrailing) {
            if selectionMode {
                Button {
                    showAddToAlbum = true
                } label: {
                    Label("Add", systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(selectedPhotoIds.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(selectionMode ? "\(selectedPhotoIds.count) Selected" : "Select") {
                selectionMode.toggle()
                if !selectionMode { selectedPhotoIds.removeAll() }
            }
            .disabled(store.photos.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
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
                    if store.isSyncing {
                        Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Sync & Import", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(store.isSyncing)
            } label: {
                if store.isSyncing { ProgressView() } else { Image(systemName: "ellipsis.circle") }
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.35))
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(photos) { photo in
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
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.black.opacity(0.45))
            .onChange(of: currentId) { id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(currentId, anchor: .center) }
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
