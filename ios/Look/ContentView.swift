import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        TabView {
            PhotosGrid()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            AlbumsList()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
