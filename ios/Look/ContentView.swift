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

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var initialConnectionCheckCompleted = false
    @State private var didLoadApplicationData = false
    @State private var selectedTab: LookTab = .photos

    init() {}

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
        .tint(LookTheme.ColorToken.cyan)
        .background(LookTheme.ColorToken.paper.ignoresSafeArea())
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .ignoresSafeArea(.container, edges: .bottom)
        .preferredColorScheme(.dark)
    }

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
