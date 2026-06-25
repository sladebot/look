import XCTest
@testable import Look

final class NavigationDataDecodingTests: XCTestCase {
    func testAlbumListDecodesCountsAndDetailPhotosForLibraryNavigation() throws {
        let data = """
        {
          "albums": [
            {
              "id": "album-1",
              "name": "Favorites",
              "description": "Hand picked",
              "photo_count": 2,
              "source": "manual",
              "photos": [
                {
                  "id": "photo-1",
                  "filename": "a.jpg",
                  "filepath": "/library/a.jpg",
                  "created_at": "2026-06-01T12:00:00Z"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AlbumListResponse.self, from: data)

        XCTAssertEqual(response.albums.count, 1)
        XCTAssertEqual(response.albums[0].id, "album-1")
        XCTAssertEqual(response.albums[0].photoCount, 2)
        XCTAssertEqual(response.albums[0].photos?.map(\.filename), ["a.jpg"])
    }

    func testSmartCollectionsDecodeRuleMetadataAndPhotosForSmartAlbumNavigation() throws {
        let data = """
        {
          "collections": [
            {
              "id": "smart-1",
              "name": "iPhone",
              "description": "Camera model contains iPhone",
              "rule_spec": "{\\"field\\":\\"camera\\",\\"operator\\":\\"contains\\",\\"value\\":\\"iPhone\\"}",
              "last_evaluated_at": "2026-06-02T09:30:00Z",
              "photos": [
                {
                  "id": "photo-iphone",
                  "filename": "phone.jpg",
                  "filepath": "/library/phone.jpg",
                  "mime_type": "image/jpeg"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SmartCollectionsResponse.self, from: data)

        XCTAssertEqual(response.collections.count, 1)
        XCTAssertEqual(response.collections[0].id, "smart-1")
        XCTAssertEqual(response.collections[0].ruleSpec?.contains("camera"), true)
        XCTAssertEqual(response.collections[0].photos?.first?.id, "photo-iphone")
    }

    func testWatchListDecodesFlexibleActiveValuesForSettingsToolsNavigation() throws {
        let data = """
        {
          "directories": [
            {"path": "/photos/active-bool", "added_at": "2026-06-01T00:00:00Z", "active": true},
            {"path": "/photos/active-int", "active": 1},
            {"path": "/photos/inactive-int", "active": 0},
            {"path": "/photos/default-active"}
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(WatchListResponse.self, from: data)

        XCTAssertEqual(response.directories.map(\.path), [
            "/photos/active-bool",
            "/photos/active-int",
            "/photos/inactive-int",
            "/photos/default-active"
        ])
        XCTAssertEqual(response.directories.map(\.active), [true, true, false, true])
    }

    func testTaskAndMigrationResponsesDecodeSettingsToolPayloads() throws {
        let data = """
        {
          "tasks": [
            {
              "task_id": "task-1",
              "task_type": "dedup_scan",
              "status": "running",
              "created_at": "2026-06-01T00:00:00Z",
              "progress": {"phase": "hashing", "current": 4, "total": 10}
            }
          ]
        }
        """.data(using: .utf8)!

        let tasks = try JSONDecoder().decode(TaskListResponse.self, from: data)
        XCTAssertEqual(tasks.tasks.first?.id, "task-1")
        XCTAssertEqual(tasks.tasks.first?.progress?["phase"]?.stringValue, "hashing")
        XCTAssertEqual(tasks.tasks.first?.progress?["current"]?.intValue, 4)

        let migrationData = """
        {
          "current_version": 3,
          "pending": [
            {"version": 4, "description": "Add GPS columns", "has_rollback": true}
          ],
          "all_registered": []
        }
        """.data(using: .utf8)!

        let migrations = try JSONDecoder().decode(MigrationStatusResponse.self, from: migrationData)
        XCTAssertEqual(migrations.currentVersion, 3)
        XCTAssertEqual(migrations.pending.first?.id, 4)
        XCTAssertEqual(migrations.pending.first?.hasRollback, true)
    }
}
