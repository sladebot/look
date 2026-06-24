import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var initialConnectionCheckCompleted = false
    @State private var didLoadApplicationData = false

    init() {
        let paper = UIColor(red: 246 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1)
        let graphite = UIColor(red: 39 / 255, green: 43 / 255, blue: 47 / 255, alpha: 1)
        let cyan = UIColor(red: 30 / 255, green: 138 / 255, blue: 255 / 255, alpha: 1)

        // Keep chrome on the same quiet surface as the gallery. The previous
        // default material turned the top region white and the tab bar glassy
        // over thumbnails, which made the contact-sheet surface feel split.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = paper
        tab.shadowColor = UIColor.black.withAlphaComponent(0.10)
        tab.stackedLayoutAppearance.selected.iconColor = cyan
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: cyan]
        tab.stackedLayoutAppearance.normal.iconColor = graphite.withAlphaComponent(0.72)
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: graphite.withAlphaComponent(0.72)]
        tab.inlineLayoutAppearance = tab.stackedLayoutAppearance
        tab.compactInlineLayoutAppearance = tab.stackedLayoutAppearance
        UITabBar.appearance().isTranslucent = false
        UITabBar.appearance().backgroundColor = paper
        UITabBar.appearance().tintColor = cyan
        UITabBar.appearance().unselectedItemTintColor = graphite.withAlphaComponent(0.72)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = paper
        nav.shadowColor = UIColor.black.withAlphaComponent(0.08)
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        nav.titleTextAttributes = [.foregroundColor: graphite]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
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
        .task {
            await performInitialConnectionCheck()
        }
    }

    private var appTabs: some View {
        TabView {
            PhotosGrid()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(LookTheme.ColorToken.cyan)
        .background(LookTheme.ColorToken.paper)
        .toolbarBackground(LookTheme.ColorToken.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
                message: "Confirming the saved Tailnet route before opening your library."
            )

            LookStatusBanner(
                title: "Private-network first",
                message: "If this device is away from your Tailnet, Look will ask you to reconnect before showing library tabs.",
                tone: .info
            )
            .padding(.horizontal, LookTheme.Spacing.screen)
        }
        .lookScreenBackground()
    }
}
