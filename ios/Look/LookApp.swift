import SwiftUI

@main
struct LookApp: App {
    @StateObject private var store = PhotoStore()

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
