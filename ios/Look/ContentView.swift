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

    init() {
        let paper = UIColor(red: 31 / 255, green: 35 / 255, blue: 39 / 255, alpha: 1)
        let graphite = UIColor(red: 238 / 255, green: 243 / 255, blue: 246 / 255, alpha: 1)
        let cyan = UIColor(red: 46 / 255, green: 168 / 255, blue: 255 / 255, alpha: 1)

        // Keep chrome on the same quiet surface as the gallery. The previous
        // default material turned the top region white and the tab bar glassy
        // over thumbnails, which made the contact-sheet surface feel split.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = paper
        tab.shadowColor = UIColor.black.withAlphaComponent(0.10)
        tab.stackedLayoutAppearance.selected.iconColor = cyan
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: cyan]
        tab.stackedLayoutAppearance.normal.iconColor = graphite.withAlphaComponent(0.70)
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: graphite.withAlphaComponent(0.70)]
        tab.inlineLayoutAppearance = tab.stackedLayoutAppearance
        tab.compactInlineLayoutAppearance = tab.stackedLayoutAppearance
        UITabBar.appearance().isTranslucent = false
        UITabBar.appearance().backgroundColor = paper
        UITabBar.appearance().barTintColor = paper
        UITabBar.appearance().tintColor = cyan
        UITabBar.appearance().unselectedItemTintColor = graphite.withAlphaComponent(0.70)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = paper
        nav.shadowColor = UIColor.black.withAlphaComponent(0.35)
        nav.largeTitleTextAttributes = [.foregroundColor: graphite]
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
        ZStack(alignment: .bottom) {
            activeTabView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)

            lookTabBar
        }
        .tint(LookTheme.ColorToken.cyan)
        .background(LookTheme.ColorToken.paper.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var activeTabView: some View {
        switch selectedTab {
        case .photos:
            PhotosGrid()
        case .library:
            LibraryView()
        case .search:
            SearchView()
        case .settings:
            SettingsView()
        }
    }

    private var lookTabBar: some View {
        HStack(spacing: 0) {
            ForEach(LookTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .frame(height: 28)
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? LookTheme.ColorToken.graphite : LookTheme.ColorToken.graphite.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(LookTheme.ColorToken.graphite.opacity(0.13))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .background(LookTheme.ColorToken.paper.opacity(0.80))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LookTheme.ColorToken.mist.opacity(0.45))
                .frame(height: 1)
        }
        .ignoresSafeArea(.container, edges: .bottom)
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
