import SwiftUI

@main
struct LookApp: App {
    @StateObject private var store = PhotoStore()

    init() {
        #if DEBUG
        // Screenshot tooling: apply connection state from the launch environment
        // (simctl `defaults write` is unreliable across fresh simulators).
        let environment = ProcessInfo.processInfo.environment
        if let url = environment["LOOK_UI_SERVER_URL"], !url.isEmpty {
            UserDefaults.standard.set(url, forKey: ConnectionSetupStorage.serverURLKey)
        }
        if let connected = environment["LOOK_UI_CONNECTED"] {
            UserDefaults.standard.set(connected == "1",
                                      forKey: ConnectionSetupStorage.hasSuccessfulConnectionKey)
        }
        #endif
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
