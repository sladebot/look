import SwiftUI

private enum LookTab: String, CaseIterable, Identifiable {
    case photos
    case library
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .library: return "Library"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .photos: return "photo.on.rectangle.angled"
        case .library: return "rectangle.stack"
        case .search: return "magnifyingglass"
        case .settings: return "gear"
        }
    }
}

#if DEBUG
/// Screenshot-only navigation driver: lets tooling open any screen of the real
/// app (live server data, no demo mocks) via launch environment variables,
/// since `simctl` cannot synthesize taps.
///   LOOK_UI_TAB    photos | library | search | settings
///   LOOK_UI_ROUTE  one of the cases below
enum LookUIScreenshotRoute: String, Identifiable {
    case viewer, detail, addToAlbum, tagHistory, map, albumDetail, smartAlbum
    case dedup, tasks, watchlist, tagCleanup, migrations, createAlbum, createSmartAlbum

    var id: String { rawValue }

    var presentsAsSheet: Bool {
        switch self {
        case .detail, .addToAlbum, .tagHistory, .createAlbum, .createSmartAlbum:
            return true
        default:
            return false
        }
    }

    static var requested: LookUIScreenshotRoute? {
        ProcessInfo.processInfo.environment["LOOK_UI_ROUTE"]
            .flatMap(LookUIScreenshotRoute.init(rawValue:))
    }
}
#endif

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var initialConnectionCheckCompleted = false
    @State private var didLoadApplicationData = false
    @State private var selectedTab: LookTab = .photos
    #if DEBUG
    @State private var screenshotSheetRoute: LookUIScreenshotRoute?
    @State private var screenshotCoverRoute: LookUIScreenshotRoute?
    #endif

    init() {
        #if DEBUG
        if let tab = ProcessInfo.processInfo.environment["LOOK_UI_TAB"]
            .flatMap(LookTab.init(rawValue:)) {
            _selectedTab = State(initialValue: tab)
        }
        #endif
    }

    var body: some View {
        Group {
            if !hasSuccessfulConnection {
                ConnectionSetupView {
                    initialConnectionCheckCompleted = true
                    await loadApplicationDataIfNeeded()
                }
            } else if !initialConnectionCheckCompleted {
                ConnectionCheckingView()
            } else if !store.serverConnected {
                ConnectionSetupView {
                    initialConnectionCheckCompleted = true
                    await loadApplicationDataIfNeeded()
                }
            } else {
                appTabs
                    .task {
                        await loadApplicationDataIfNeeded()
                    }
            }
        }
        .tint(LookTheme.ColorToken.accentControl)
        .preferredColorScheme(.dark)
        .task {
            await performInitialConnectionCheck()
        }
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            PhotosGrid()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label(LookTab.photos.title, systemImage: LookTab.photos.systemImage) }
                .tag(LookTab.photos)

            LibraryView()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label(LookTab.library.title, systemImage: LookTab.library.systemImage) }
                .tag(LookTab.library)

            SearchView()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label(LookTab.search.title, systemImage: LookTab.search.systemImage) }
                .tag(LookTab.search)

            SettingsView()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label(LookTab.settings.title, systemImage: LookTab.settings.systemImage) }
                .tag(LookTab.settings)
        }
        .tint(LookTheme.ColorToken.accentControl)
        .background(LookTheme.ColorToken.paper.ignoresSafeArea())
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .ignoresSafeArea(.container, edges: .bottom)
        .preferredColorScheme(.dark)
        #if DEBUG
        .task { await activateScreenshotRouteIfNeeded() }
        .sheet(item: $screenshotSheetRoute) { route in
            screenshotDestination(route)
        }
        .fullScreenCover(item: $screenshotCoverRoute) { route in
            screenshotDestination(route)
        }
        #endif
    }

    #if DEBUG
    private func activateScreenshotRouteIfNeeded() async {
        guard let route = LookUIScreenshotRoute.requested else { return }
        for _ in 0..<60 {
            if store.serverConnected && !store.photos.isEmpty { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        switch route {
        case .albumDetail, .addToAlbum:
            await store.loadAlbums()
        case .smartAlbum:
            await store.loadSmartCollections()
        default:
            break
        }
        if route.presentsAsSheet {
            screenshotSheetRoute = route
        } else {
            screenshotCoverRoute = route
        }
    }

    @ViewBuilder
    private func screenshotDestination(_ route: LookUIScreenshotRoute) -> some View {
        switch route {
        case .viewer:
            if let first = store.photos.first {
                NativePhotoViewer(photos: store.photos, initialPhoto: first)
            }
        case .detail:
            if let first = store.photos.first {
                PhotoDetail(photo: first)
            }
        case .addToAlbum:
            if let first = store.photos.first {
                AddToAlbumSheet(photo: first)
            }
        case .tagHistory:
            if let first = store.photos.first {
                TagHistoryView(photoId: first.id)
            }
        case .map:
            NavigationStack { MapBrowseView() }
        case .albumDetail:
            if let album = store.albums.first {
                NavigationStack { AlbumDetail(album: album) }
            }
        case .smartAlbum:
            if let collection = store.smartCollections.first {
                NavigationStack { SmartAlbumDetail(collection: collection) }
            }
        case .dedup:
            NavigationStack { DedupView() }
        case .tasks:
            NavigationStack { TasksView() }
        case .watchlist:
            NavigationStack { WatchListView() }
        case .tagCleanup:
            NavigationStack { TagCleanupView() }
        case .migrations:
            NavigationStack { MigrationsView() }
        case .createAlbum:
            CreateAlbumSheet()
        case .createSmartAlbum:
            CreateSmartAlbumSheet()
        }
    }
    #endif

    private func performInitialConnectionCheck() async {
        guard !initialConnectionCheckCompleted else { return }
        guard hasSuccessfulConnection else {
            initialConnectionCheckCompleted = true
            store.stopAutoSync()
            return
        }

        await store.checkConnection()
        initialConnectionCheckCompleted = true

        if store.serverConnected {
            await loadApplicationDataIfNeeded()
        } else {
            store.stopAutoSync()
        }
    }

    private func loadApplicationDataIfNeeded() async {
        guard store.serverConnected, !didLoadApplicationData else { return }
        didLoadApplicationData = true
        await store.loadPhotos(reset: true)
        store.startAutoSync()
    }
}

private struct ConnectionCheckingView: View {
    var body: some View {
        VStack(spacing: LookTheme.Spacing.large) {
            LookLoadingState(
                title: "Checking Look server",
                message: "Confirming the saved Tailscale route before opening your library."
            )

            LookStatusBanner(
                title: "Private-network first",
                message: "If this device is away from your Tailscale network, Look will ask you to reconnect before showing library tabs.",
                tone: .info
            )
            .padding(.horizontal, LookTheme.Spacing.screen)
        }
        .lookScreenBackground()
    }
}
