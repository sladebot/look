import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var initialConnectionCheckCompleted = false
    @State private var didLoadApplicationData = false

    init() {
        // Clean, opaque chrome so pinned date headers and the tab bar read
        // crisply over edge-to-edge photos (Google Photos style).
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
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
        .tint(.blue)
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
