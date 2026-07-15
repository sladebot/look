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

    private let latestColumns = [GridItem(.adaptive(minimum: 104), spacing: 2)]
    private let monthColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var latestPhotos: [Photo] {
        Array(store.photos.prefix(12))
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
            VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                header

                if store.isSyncing {
                    syncLine
                }

                latestSection

                if !onThisDay.isEmpty {
                    onThisDaySection
                }

                if months.count > 1 {
                    monthsSection
                }

                quickSets
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
                Text("Photos")
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

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                LookTheme.sectionHeader("Latest")
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

            LazyVGrid(columns: latestColumns, spacing: 2) {
                ForEach(latestPhotos) { photo in
                    PhotoCard(photo: photo)
                        .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                        .onTapGesture { selectedLatest = photo }
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

            LazyVGrid(columns: monthColumns, spacing: 10) {
                ForEach(months) { bucket in
                    NavigationLink {
                        MonthDetailView(bucket: bucket)
                    } label: {
                        MonthCard(bucket: bucket)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickSets: some View {
        HStack(spacing: LookTheme.Spacing.small) {
            NavigationLink {
                PhotosGrid(isRootPage: false, initialFilter: .favorites)
            } label: {
                LookChip(title: "Favorites", systemImage: "heart", tint: LookTheme.ColorToken.accent)
            }
            .buttonStyle(.plain)

            NavigationLink {
                PhotosGrid(isRootPage: false, initialFilter: .raw)
            } label: {
                LookChip(title: "RAW", systemImage: "camera.aperture", tint: LookTheme.ColorToken.accent)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
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
