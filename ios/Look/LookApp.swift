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
            #if DEBUG
            if LookDemoScreenshots.isActive {
                DemoScreenshotHost()
            } else {
                ContentView()
                    .environmentObject(store)
            }
            #else
            ContentView()
                .environmentObject(store)
            #endif
        }
    }
}
