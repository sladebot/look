import SwiftUI

@main
struct LookApp: App {
    @StateObject private var store = PhotoStore()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "LookThumbnailCache"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.checkConnection()
                    await store.loadPhotos(reset: true)
                    store.startAutoSync()
                }
        }
    }
}
