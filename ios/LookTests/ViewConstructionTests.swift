import SwiftUI
import UIKit
import XCTest
@testable import Look

@MainActor
final class ViewConstructionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetConnectionDefaults()
    }

    override func tearDown() {
        resetConnectionDefaults()
        super.tearDown()
    }

    func testConnectionSetupSettingsAndLibraryViewsBuildWithStoreEnvironment() {
        let store = PhotoStore()
        store.albums = [
            Album(id: "album-1", name: "Favorites", description: "Pinned photos", photoCount: 3, source: "manual", photos: nil)
        ]
        store.smartCollections = [
            SmartCollection(id: "smart-1", name: "RAW", description: "Raw files", ruleSpec: nil, lastEvaluatedAt: nil, photos: nil)
        ]

        assertBuilds(ConnectionSetupView(onConnectionEstablished: {}).environmentObject(store))
        assertBuilds(SettingsView().environmentObject(store))
        assertBuilds(LibraryView().environmentObject(store))
        assertBuilds(AddToAlbumSheet(photos: []).environmentObject(store))
    }

    func testGalleryAndPhotoSelectionVisualStatesBuildWithSamplePhotos() throws {
        let store = PhotoStore()
        store.serverConnected = true
        store.photos = try TestFixtures.photos(8)
        store.totalPhotos = 8
        store.hasMorePhotos = false

        assertBuilds(PhotosGrid().environmentObject(store))

        let selectedCard = PhotoCard(
            photo: try TestFixtures.photo(id: "selected", filename: "Selected.JPG", isFavorite: true),
            isSelected: true,
            selectionMode: true
        )
        assertBuilds(selectedCard)

        let unselectedCard = PhotoCard(
            photo: try TestFixtures.photo(id: "unselected", filename: "Unselected.JPG"),
            isSelected: false,
            selectionMode: true
        )
        assertBuilds(unselectedCard)
    }

    func testContentViewBuildsFirstRunConnectionGateAndConnectedAppShell() {
        let firstRunStore = PhotoStore()
        assertBuilds(ContentView().environmentObject(firstRunStore))

        UserDefaults.standard.set(true, forKey: ConnectionSetupStorage.hasSuccessfulConnectionKey)
        let connectedStore = PhotoStore()
        connectedStore.serverConnected = true
        connectedStore.photos = []

        assertBuilds(ContentView().environmentObject(connectedStore))
    }

    private func assertBuilds<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host, file: file, line: line)
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
