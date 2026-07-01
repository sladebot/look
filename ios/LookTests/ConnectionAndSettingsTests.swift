import XCTest
@testable import Look

@MainActor
final class ConnectionAndSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetConnectionDefaults()
    }

    override func tearDown() {
        resetConnectionDefaults()
        super.tearDown()
    }

    func testConnectionDefaultsMatchProductionTailnetRoute() throws {
        let url = try APIClient.thumbnailURL(
            baseURL: ConnectionSetupStorage.defaultServerURL,
            photoId: "photo-id",
            size: 512
        )

        XCTAssertEqual(ConnectionSetupStorage.defaultServerURL, "http://studio.taila3f2b.ts.net:5678")
        XCTAssertEqual(url.absoluteString, "http://studio.taila3f2b.ts.net:5678/api/thumbnails/photo-id?size=512")
    }

    func testConfiguredBaseURLTrimsSettingsInput() {
        UserDefaults.standard.set("  http://100.86.254.112:5678  ", forKey: ConnectionSetupStorage.serverURLKey)

        let client = APIClient()

        XCTAssertEqual(client.configuredBaseURL, "http://100.86.254.112:5678")
        XCTAssertEqual(client.fullImageURL(for: "photo-id").absoluteString, "http://100.86.254.112:5678/api/full/photo-id")
        XCTAssertEqual(client.previewImageURL(for: "photo-id").absoluteString, "http://100.86.254.112:5678/api/preview/photo-id?size=1600")
    }

    func testPreviewImageURLPercentEncodesPhotoIds() throws {
        let url = try APIClient.previewImageURL(
            baseURL: "http://studio.taila3f2b.ts.net:5678",
            photoId: "raw photo/1",
            size: 1600
        )

        XCTAssertEqual(url.absoluteString, "http://studio.taila3f2b.ts.net:5678/api/preview/raw%20photo%2F1?size=1600")
    }

    func testPhotoStoreBooleanSettingsSupportServerRepresentations() {
        let store = PhotoStore()
        store.serverSettings = [
            "smart_albums_enabled": "true",
            "dedup_enabled": "1",
            "tag_history_enabled": "yes",
            "auto_tag_gps": "false",
            "auto_tag_camera": "0"
        ]

        XCTAssertTrue(store.boolSetting("smart_albums_enabled"))
        XCTAssertTrue(store.boolSetting("dedup_enabled"))
        XCTAssertTrue(store.boolSetting("tag_history_enabled"))
        XCTAssertFalse(store.boolSetting("auto_tag_gps"))
        XCTAssertFalse(store.boolSetting("auto_tag_camera"))
        XCTAssertFalse(store.boolSetting("missing"))
    }

    func testAutoSyncToggleIsIdempotentForSettingsControl() {
        let store = PhotoStore()

        store.startAutoSync()
        store.startAutoSync()
        XCTAssertTrue(store.autoSyncEnabled)

        store.stopAutoSync()
        store.stopAutoSync()
        XCTAssertFalse(store.autoSyncEnabled)
    }

    private func resetConnectionDefaults() {
        for domain in ["com.sladebot.look", "com.sladebot.lookTests", Bundle.main.bundleIdentifier].compactMap(\.self) {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults.standard.removeObject(forKey: ConnectionSetupStorage.serverURLKey)
        UserDefaults.standard.removeObject(forKey: ConnectionSetupStorage.hasSuccessfulConnectionKey)
        UserDefaults.standard.synchronize()
    }
}
