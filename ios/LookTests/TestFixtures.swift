import Foundation
import XCTest
@testable import Look

enum TestFixtures {
    static func photo(
        id: String = "photo-1",
        filename: String = "IMG_0001.JPG",
        filepath: String = "/library/IMG_0001.JPG",
        width: Int? = 4000,
        height: Int? = 3000,
        mimeType: String? = "image/jpeg",
        createdAt: String? = "2026-06-01T12:00:00Z",
        isFavorite: Bool? = false
    ) throws -> Photo {
        var fields: [String] = [
            #""id": "\#(id)""#,
            #""filename": "\#(filename)""#,
            #""filepath": "\#(filepath)""#
        ]

        if let width { fields.append(#""width": \#(width)"#) }
        if let height { fields.append(#""height": \#(height)"#) }
        if let mimeType { fields.append(#""mime_type": "\#(mimeType)""#) }
        if let createdAt { fields.append(#""created_at": "\#(createdAt)""#) }
        if let isFavorite { fields.append(#""is_favorite": \#(isFavorite)"#) }

        let json = "{\(fields.joined(separator: ","))}"
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(Photo.self, from: data)
    }

    static func photos(_ count: Int) throws -> [Photo] {
        try (0..<count).map { index in
            try photo(
                id: "photo-\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                filepath: "/library/IMG_\(index).JPG",
                width: index.isMultiple(of: 2) ? 4000 : 3000,
                height: index.isMultiple(of: 2) ? 3000 : 4000,
                createdAt: "2026-06-\(String(format: "%02d", (index % 9) + 1))T12:00:00Z",
                isFavorite: index.isMultiple(of: 3)
            )
        }
    }
}
