import XCTest
@testable import Look

final class GalleryLayoutTests: XCTestCase {
    func testJustifiedRowsFillCompletedRowsAndPreservePhotoOrder() throws {
        let photos = try TestFixtures.photos(6)

        let rows = PhotoLayout.rows(
            for: photos,
            width: 360,
            target: 120,
            spacing: 2,
            aspect: { photo in
                CGFloat(photo.width ?? 1) / CGFloat(photo.height ?? 1)
            }
        )

        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.flatMap { $0.items.map(\.photo.id) }, photos.map(\.id))

        for row in rows.dropLast() {
            let occupiedWidth = row.items.reduce(CGFloat.zero) { $0 + $1.width }
                + CGFloat(row.items.count - 1) * 2
            XCTAssertEqual(occupiedWidth, 360, accuracy: 0.5)
            XCTAssertGreaterThan(row.height, 0)
        }
    }

    func testLastRowDoesNotOverStretchWhenItCannotFillContainer() throws {
        let photos = [
            try TestFixtures.photo(id: "one", width: 400, height: 400),
            try TestFixtures.photo(id: "two", width: 400, height: 400)
        ]

        let rows = PhotoLayout.rows(
            for: photos,
            width: 1_000,
            target: 120,
            spacing: 8,
            aspect: { _ in 1 }
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].height, 120, accuracy: 0.01)
        XCTAssertEqual(rows[0].items.map(\.width), [120, 120], accuracy: 0.01)
    }

    func testZeroWidthProducesNoRows() throws {
        let photos = try TestFixtures.photos(3)

        let rows = PhotoLayout.rows(
            for: photos,
            width: 0,
            target: 120,
            spacing: 2,
            aspect: { _ in 1 }
        )

        XCTAssertTrue(rows.isEmpty)
    }

    func testLayoutHandlesMissingOrInvalidAspectRatios() throws {
        let photos = [
            try TestFixtures.photo(id: "missing", width: nil, height: nil),
            try TestFixtures.photo(id: "zero-height", width: 400, height: 0),
            try TestFixtures.photo(id: "wide", width: 6000, height: 2000)
        ]

        let rows = PhotoLayout.rows(
            for: photos,
            width: 320,
            target: 100,
            spacing: 4,
            aspect: { photo in
                guard let width = photo.width, let height = photo.height, height > 0 else {
                    return 1
                }
                return CGFloat(width) / CGFloat(height)
            }
        )

        XCTAssertEqual(rows.flatMap { $0.items.map(\.photo.id) }, ["missing", "zero-height", "wide"])
        XCTAssertTrue(rows.allSatisfy { $0.height.isFinite && $0.height > 0 })
        XCTAssertTrue(rows.flatMap(\.items).allSatisfy { $0.width.isFinite && $0.width > 0 })
    }
}

private func XCTAssertEqual(
    _ expression1: @autoclosure () throws -> [CGFloat],
    _ expression2: @autoclosure () throws -> [CGFloat],
    accuracy: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertEqual(left, right, accuracy: accuracy, file: file, line: line)
        }
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
