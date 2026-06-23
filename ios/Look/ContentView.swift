import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore

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
}
