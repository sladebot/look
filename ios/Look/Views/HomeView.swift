import SwiftUI

/// The archive's front door. Instead of dropping the user into an endless
/// chronological scroll, the home page answers the questions a self-hosted
/// archive actually gets asked: what's new (Latest), what happened today in
/// past years (On this day), how do I reach a moment years back (Browse by
/// month), and the working sets one tap away (Favorites / RAW).
/// The full chronology lives one tap in, via "All photos".
struct HomeView: View {
    @EnvironmentObject var store: PhotoStore

    @State private var months: [MonthBucket] = []
    @State private var onThisDay: [Photo] = []
    @State private var selectedLatest: Photo?
    @State private var selectedMemory: Photo?
    @Namespace private var viewerZoomNamespace

    private var latestPhotos: [Photo] {
        Array(store.photos.prefix(18))
    }

    private var heroPhotos: [Photo] {
        Array(latestPhotos.prefix(5))
    }

    private var recentPhotos: [Photo] {
        Array(latestPhotos.dropFirst(min(5, latestPhotos.count)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.photos.isEmpty {
                    LookLoadingState(title: "Loading library",
                                     message: "Talking to your Look server.")
                } else if !store.serverConnected {
                    LookEmptyState(
                        title: "Server unavailable",
                        systemImage: "wifi.slash",
                        message: "Check the Server tab or retry the connection.",
                        actionTitle: "Retry",
                        action: { Task { await store.checkConnection() } }
                    )
                } else if store.photos.isEmpty {
                    LookEmptyState(
                        title: "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        message: "Import photos on the server to begin.",
                        actionTitle: "Sync Library",
                        action: { Task { await store.syncNow() } }
                    )
                } else {
                    home
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .lookScreenBackground()
            .toolbarColorScheme(.dark, for: .tabBar)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Sections

    private var home: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header

                if store.isSyncing {
                    syncLine
                }

                archiveHero

                libraryShortcuts

                if !onThisDay.isEmpty {
                    onThisDaySection
                }

                recentSection

                if !months.isEmpty { monthsSection }
            }
            .padding(.horizontal, LookTheme.Spacing.screen)
            .padding(.top, LookTheme.Spacing.small)
            .padding(.bottom, 108)
        }
        .refreshable {
            await store.syncNow()
            await loadArchiveIndex()
        }
        .task { await loadArchiveIndex() }
        .fullScreenCover(item: $selectedLatest) { photo in
            NativePhotoViewer(photos: latestPhotos, initialPhoto: photo)
                .modifier(LookZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
        }
        .fullScreenCover(item: $selectedMemory) { photo in
            NativePhotoViewer(photos: onThisDay, initialPhoto: photo)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Look")
                    .font(LookTheme.Typography.display)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                Text(vitals)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: LookTheme.Spacing.small)

            Menu {
                Button {
                    Task { await store.syncNow() }
                } label: {
                    Label(store.isSyncing ? "Syncing" : "Scan for new photos",
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

    /// "1,846 photos · updated 2 hours ago" — the self-hoster's first question.
    private var vitals: String {
        let count = store.totalPhotos > 0 ? store.totalPhotos : store.photos.count
        var parts = ["\(count.formatted()) photos"]
        if let syncedAt = store.lastAutoSyncAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append("updated \(formatter.localizedString(for: syncedAt, relativeTo: .now))")
        } else {
            parts.append("Private library")
        }
        return parts.joined(separator: " · ")
    }

    private var syncLine: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            ProgressView()
                .controlSize(.small)
                .tint(LookTheme.ColorToken.accent)
            Text(store.syncProgressFraction.map { "Syncing · \(Int(($0 * 100).rounded()))%" }
                 ?? store.syncProgressMessage ?? "Syncing library")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var archiveHero: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATEST FROM YOUR ARCHIVE")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(LookTheme.ColorToken.warning)
                    Text("Recently added")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                }
                Spacer()
                NavigationLink("See all") { PhotosGrid(isRootPage: false) }
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.accent)
            }

            GeometryReader { proxy in
                let gap: CGFloat = 3
                let leftWidth = proxy.size.width * 0.62
                HStack(spacing: gap) {
                    heroTile(at: 0, width: leftWidth, height: 286)
                    VStack(spacing: gap) {
                        heroTile(at: 1, width: proxy.size.width - leftWidth - gap, height: 141.5)
                        HStack(spacing: gap) {
                            heroTile(at: 2, width: (proxy.size.width - leftWidth - gap * 2) / 2, height: 141.5)
                            heroTile(at: 3, width: (proxy.size.width - leftWidth - gap * 2) / 2, height: 141.5)
                        }
                    }
                }
            }
            .frame(height: 286)
            .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 7) {
                    Rectangle().fill(LookTheme.ColorToken.warning).frame(width: 18, height: 2)
                    Text("\(heroPhotos.count.formatted()) NEW FRAMES")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.72))
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func heroTile(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if heroPhotos.indices.contains(index) {
            let photo = heroPhotos[index]
            CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 512))
                .frame(width: width, height: height)
                .clipped()
                .contentShape(Rectangle())
                .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                .onTapGesture { selectedLatest = photo }
                .accessibilityLabel("Open \(photo.filename)")
        } else {
            LookTheme.ColorToken.surface
                .frame(width: width, height: height)
        }
    }

    private var libraryShortcuts: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            archiveShortcut(title: "All photos", detail: store.totalPhotos.formatted(), icon: "rectangle.stack") {
                PhotosGrid(isRootPage: false)
            }
            archiveShortcut(title: "Favorites", detail: "Saved frames", icon: "heart") {
                PhotosGrid(isRootPage: false, initialFilter: .favorites)
            }
            archiveShortcut(title: "RAW", detail: "Originals", icon: "camera.aperture") {
                PhotosGrid(isRootPage: false, initialFilter: .raw)
            }
        }
    }

    private func archiveShortcut<Destination: View>(title: String, detail: String, icon: String,
                                                     @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.accent)
                Text(title)
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(LookTheme.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                LookTheme.sectionHeader("Continue browsing")
                Spacer()
                NavigationLink {
                    PhotosGrid(isRootPage: false)
                } label: {
                    HStack(spacing: 3) {
                        Text("All photos")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.accent)
                }
                .accessibilityLabel("All photos, full library")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(recentPhotos) { photo in
                        CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256))
                            .frame(width: 128, height: 166)
                            .clipped()
                            .contentShape(Rectangle())
                            .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                            .onTapGesture { selectedLatest = photo }
                            .accessibilityLabel("Open \(photo.filename)")
                    }
                }
            }
        }
    }

    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            LookTheme.sectionHeader("On this day")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LookTheme.Spacing.small) {
                    ForEach(onThisDay) { photo in
                        Button {
                            selectedMemory = photo
                        } label: {
                            CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256))
                                .frame(width: 116, height: 116)
                                .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.thumbnail, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    if let year = year(of: photo) {
                                        Text(year)
                                            .font(LookTheme.Typography.captionEmphasis)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.black.opacity(0.55), in: Capsule())
                                            .padding(5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo from \(year(of: photo) ?? "a past year")")
                    }
                }
            }
        }
    }

    private var monthsSection: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            LookTheme.sectionHeader("Browse by month")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: LookTheme.Spacing.small) {
                    ForEach(months.prefix(12)) { bucket in
                        NavigationLink {
                            MonthDetailView(bucket: bucket)
                        } label: {
                            MonthCard(bucket: bucket)
                                .frame(width: 184)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadArchiveIndex() async {
        async let monthsTask = try? APIClient.shared.photoMonths().months
        let now = Calendar.current.dateComponents([.month, .day, .year], from: .now)
        async let memoriesTask = try? APIClient.shared.photosOnThisDay(
            month: now.month ?? 1, day: now.day ?? 1, excludeYear: now.year
        ).photos
        months = (await monthsTask) ?? []
        onThisDay = (await memoriesTask) ?? []
    }

    private func year(of photo: Photo) -> String? {
        guard let created = photo.createdAt, created.count >= 4 else { return nil }
        return String(created.prefix(4))
    }
}

// MARK: - Month card

private struct MonthCard: View {
    let bucket: MonthBucket

    private static let inFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let outFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private var title: String {
        guard let date = Self.inFormatter.date(from: bucket.month) else { return bucket.month }
        return Self.outFormatter.string(from: date)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = bucket.coverPhotoId {
                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: cover, size: 512))
                    .frame(height: 110)
                    .clipped()
            } else {
                LookTheme.ColorToken.surface
                    .frame(height: 110)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.62)],
                           startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(.white)
                Text(bucket.count == 1 ? "1 photo" : "\(bucket.count.formatted()) photos")
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(LookTheme.Spacing.small)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(bucket.count) photos")
    }
}

// MARK: - Month detail

/// One month of the archive, fetched by date range and shown day-grouped.
struct MonthDetailView: View {
    let bucket: MonthBucket

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: Photo?
    @Namespace private var viewerZoomNamespace

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 2)]

    private var title: String {
        guard let date = MonthDetailView.inFormatter.date(from: bucket.month) else { return bucket.month }
        return MonthDetailView.outFormatter.string(from: date)
    }

    fileprivate static let inFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    fileprivate static let outFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    var body: some View {
        Group {
            if isLoading {
                LookLoadingState(title: "Loading \(title)")
            } else if let errorMessage {
                LookEmptyState(
                    title: "Could not load month",
                    systemImage: "exclamationmark.triangle",
                    message: errorMessage,
                    actionTitle: "Retry",
                    action: { Task { await load() } }
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            PhotoCard(photo: photo)
                                .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                                .onTapGesture { selected = photo }
                        }
                    }
                    .padding(.horizontal, LookTheme.Spacing.tight)
                    .padding(.bottom, LookTheme.Spacing.large)
                }
            }
        }
        .lookScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
                .modifier(LookZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.photos(
                limit: 500,
                startDate: "\(bucket.month)-01",
                endDate: "\(bucket.month)-31T23:59:59"
            )
            photos = response.photos
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
