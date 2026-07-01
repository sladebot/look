import SwiftUI
import UIKit
import ImageIO

struct PhotoCard: View {
    let photo: Photo
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256), contentMode: .fill)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.thumbnail, style: .continuous))
            .background(LookTheme.ColorToken.darkroom)
            .overlay(alignment: .bottomLeading) {
                if photo.isFavorite == true && !selectionMode {
                    Image(systemName: "heart.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                }
            }
            .overlay {
                if isSelected {
                    Color.black.opacity(0.16)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.9),
                                         isSelected ? LookTheme.ColorToken.cyan : .black.opacity(0.38))
                        .padding(6)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(LookTheme.ColorToken.cyan)
                        .frame(width: 5)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: LookTheme.Radius.thumbnail, style: .continuous)
                        .stroke(LookTheme.ColorToken.cyan, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(selectionMode ? "Double tap to \(isSelected ? "remove from" : "add to") selection" : "Double tap to open photo")
            .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
    }

    private var accessibilityLabel: String {
        var parts = [photo.filename]
        if photo.isFavorite == true { parts.append("favorite") }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Efficient thumbnail loader
//
// Memory is the bottleneck with ~1800 photos: decoding every 512px JPEG at full
// size would blow up. This loader downsamples each image to the pixel size it's
// actually displayed at (via ImageIO, which avoids decoding the full bitmap) and
// keeps results in a bounded in-memory NSCache so scrolling back is instant
// without unbounded growth. Raw bytes stay in the shared on-disk URLCache.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inflight: [NSString: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 500
        cache.totalCostLimit = 96 * 1024 * 1024   // ~96 MB of decoded pixels

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024)
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<UIImage?, Never> { [session] in
            var request = APIClient.shared.imageRequest(for: url)
            request.timeoutInterval = 30
            guard let (data, _) = try? await session.data(for: request),
                  let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
            return image
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result {
            let cost = Int(result.size.width * result.size.height * 4)
            cache.setObject(result, forKey: key, cost: cost)
        }
        return result
    }

    func clear() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
        inflight.removeAll()
    }

    /// Decode + downsample in one pass without materializing the full-size bitmap.
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 64),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

struct CachedThumbnail: View {
    let url: URL
    var contentMode: ContentMode = .fill
    /// Cap on decoded pixel size (longest edge). Keeps grid cells from decoding
    /// far more detail than they display. Defaults to the screen's larger edge.
    var maxPixel: CGFloat = 600
    /// Called once the underlying image decodes, with its pixel size. Lets a
    /// justified-grid layout learn real aspect ratios even when the DB lacks them.
    var onDecode: ((CGSize) -> Void)? = nil

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            #if DEBUG
            if LookDemoScreenshots.isActive {
                Image(uiImage: LookDemoMockImage.image(identifier: url.absoluteString, size: CGSize(width: maxPixel, height: maxPixel)))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                remoteThumbnailBody
            }
            #else
            remoteThumbnailBody
            #endif
        }
    }

    private var remoteThumbnailBody: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else if failed {
                Color(.systemGray5)
                    .overlay(Image(systemName: "photo.badge.exclamationmark").foregroundColor(.secondary))
            } else {
                Color(.systemGray6)
                    .overlay(ProgressView().tint(.secondary))
                    .task(id: url) { await load() }
            }
        }
    }

    private func load() async {
        #if DEBUG
        if LookDemoScreenshots.isActive { return }
        #endif
        let loaded = await ThumbnailLoader.shared.image(for: url, maxPixel: maxPixel)
        await MainActor.run {
            if let loaded {
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                failed = false
                onDecode?(loaded.size)
            } else {
                failed = true
            }
        }
    }
}
