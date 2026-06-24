import XCTest
@testable import Look

final class ModelDecodingTests: XCTestCase {
    func testPhotoDecodesServerSnakeCaseAndFlexibleValues() throws {
        let data = """
        {
          "id": "photo-1",
          "filename": "IMG_0001.JPG",
          "filepath": "/library/IMG_0001.JPG",
          "file_size": 2048,
          "mime_type": "image/jpeg",
          "created_at": "2026-06-01T12:00:00Z",
          "has_thumbnail": 1,
          "is_favorite": "yes",
          "gps_lat": 12.3,
          "gps_lon": 45.6,
          "exif": "{\\"make\\":\\"Apple\\",\\"model\\":\\"iPhone\\",\\"gps\\":{\\"lat\\":40.7128,\\"lon\\":-74.0060}}"
        }
        """.data(using: .utf8)!

        let photo = try JSONDecoder().decode(Photo.self, from: data)

        XCTAssertEqual(photo.id, "photo-1")
        XCTAssertEqual(photo.fileSize, 2048)
        XCTAssertEqual(photo.mimeType, "image/jpeg")
        XCTAssertEqual(photo.hasThumbnail, true)
        XCTAssertEqual(photo.isFavorite, true)
        XCTAssertEqual(photo.exif?.make, "Apple")
        XCTAssertEqual(photo.latitude ?? .nan, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(photo.longitude ?? .nan, -74.0060, accuracy: 0.0001)
        XCTAssertTrue(photo.hasLocation)
    }

    func testPhotoUsesTopLevelGpsWhenExifGpsIsMissing() throws {
        let data = """
        {
          "id": "photo-2",
          "filename": "scan.jpg",
          "filepath": "/library/scan.jpg",
          "has_thumbnail": false,
          "is_favorite": 0,
          "gps_lat": 34.0522,
          "gps_lon": -118.2437,
          "exif": {"make": "Nikon", "model": "Zf"}
        }
        """.data(using: .utf8)!

        let photo = try JSONDecoder().decode(Photo.self, from: data)

        XCTAssertEqual(photo.hasThumbnail, false)
        XCTAssertEqual(photo.isFavorite, false)
        XCTAssertEqual(photo.exif?.model, "Zf")
        XCTAssertEqual(photo.latitude ?? .nan, 34.0522, accuracy: 0.0001)
        XCTAssertEqual(photo.longitude ?? .nan, -118.2437, accuracy: 0.0001)
        XCTAssertTrue(photo.hasLocation)
    }

    func testJSONValueDecodesNestedTaskPayloads() throws {
        let data = """
        {
          "task_id": "task-1",
          "task_type": "import",
          "status": "running",
          "progress": {
            "completed": 7,
            "percent": 87.5,
            "stages": ["scan", "thumbnail"],
            "active": true
          },
          "result": null
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(TaskInfo.self, from: data)

        XCTAssertEqual(task.id, "task-1")
        XCTAssertEqual(task.taskType, "import")
        XCTAssertEqual(task.progress?["completed"]?.intValue, 7)
        XCTAssertEqual(task.progress?["percent"]?.stringValue, "87.5")
        XCTAssertEqual(task.progress?["stages"]?.arrayValue?.count, 2)
        XCTAssertEqual(task.progress?["active"]?.stringValue, "true")
        XCTAssertNil(task.result)
    }

    func testJSONValueDecodesTaskResultObject() throws {
        let data = """
        {
          "task_id": "task-2",
          "task_type": "import",
          "status": "completed",
          "progress": null,
          "result": {
            "imported": 12,
            "errors": 1,
            "ok": true
          }
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(TaskInfo.self, from: data)

        XCTAssertEqual(task.id, "task-2")
        XCTAssertNil(task.progress)
        XCTAssertEqual(task.result?["imported"]?.intValue, 12)
        XCTAssertEqual(task.result?["errors"]?.intValue, 1)
        XCTAssertEqual(task.result?["ok"]?.stringValue, "true")
    }
}
