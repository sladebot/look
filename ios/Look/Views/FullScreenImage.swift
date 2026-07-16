import SwiftUI
import UIKit
import ImageIO

struct FullScreenImage: View {
    let photo: Photo
    var isActive = true
    var canGoPrevious = false
    var canGoNext = false
    /// Single tap (disambiguated from the double-tap zoom) — used to toggle chrome.
    var onTap: () -> Void = {}
    /// Swipe down at fit scale.
    var onDismiss: () -> Void = {}
    /// Swipe up at fit scale.
    var onInfo: () -> Void = {}
    /// Swipe right at fit scale.
    var onPrevious: () -> Void = {}
    /// Swipe left at fit scale.
    var onNext: () -> Void = {}

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    // Loaded via keyed requests; AsyncImage cannot attach the API key header used
    // by the review proxy / authenticated server path.
    @State private var uiImage: UIImage?
    @State private var loadFailed = false
    @State private var isLoadingPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dismissThreshold: CGFloat = 110
    private let navigationThreshold: CGFloat = 72

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let uiImage {
                    imageView(uiImage)
                } else if loadFailed {
                    failureState
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .background(LookTheme.ColorToken.backdrop)
        .task(id: "\(photo.id)|\(isActive)") {
            guard isActive else { return }
            await loadDisplayImage()
        }
    }

    private func imageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(x: offset.width + dragOffset.width,
                    y: offset.height + dragOffset.height)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1.0 {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { scale = 1.0; offset = .zero }
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            } else {
                                dragOffset = constrainedFitScaleDrag(value.translation)
                            }
                        }
                        .onEnded { value in
                            if scale > 1.0 {
                                lastOffset = offset
                                return
                            }
                            handleFitScaleDragEnd(value)
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    if scale > 1.0 {
                        scale = 1.0; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5
                    }
                }
            }
            .onTapGesture(count: 1) { onTap() }
            .overlay(alignment: .bottom) {
                if isLoadingPreview {
                    ProgressView()
                        .tint(.white)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                        .padding(.bottom, 26)
                        .accessibilityLabel("Loading full quality preview")
                }
            }
    }

    private func constrainedFitScaleDrag(_ translation: CGSize) -> CGSize {
        let dx = translation.width
        let dy = translation.height
        if abs(dx) > abs(dy) {
            let canNavigate = (dx > 0 && canGoPrevious) || (dx < 0 && canGoNext)
            return CGSize(width: canNavigate ? dx : dx * 0.18, height: 0)
        }
        return CGSize(width: 0, height: dy)
    }

    private func handleFitScaleDragEnd(_ value: DragGesture.Value) {
        let predicted = value.predictedEndTranslation
        let dx = predicted.width
        let dy = predicted.height

        if abs(dx) > abs(dy), abs(dx) > navigationThreshold {
            if dx < 0, canGoNext {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { dragOffset = .zero }
                onNext()
                return
            }
            if dx > 0, canGoPrevious {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { dragOffset = .zero }
                onPrevious()
                return
            }
        } else if abs(dy) > dismissThreshold {
            if dy > 0 {
                onDismiss()
            } else {
                onInfo()
            }
        }

        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { dragOffset = .zero }
    }

    private var failureState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("Failed to load image")
                .font(LookTheme.Typography.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func loadDisplayImage() async {
        uiImage = nil
        loadFailed = false
        isLoadingPreview = true

        let lowResURL = APIClient.shared.thumbnailURL(for: photo.id, size: 512)
        if let image = await PreviewImageLoader.shared.image(
            for: lowResURL,
            maxPixel: 1_100,
            retryQueued: false
        ) {
            guard !Task.isCancelled else { return }
            uiImage = image
        }

        let previewURL = APIClient.shared.previewImageURL(for: photo.id, size: 1600)
        if let image = await PreviewImageLoader.shared.image(
            for: previewURL,
            maxPixel: 2_400,
            retryQueued: true,
            attempts: 7
        ) {
            guard !Task.isCancelled else { return }
            uiImage = image
            isLoadingPreview = false
            return
        }

        guard !Task.isCancelled else { return }
        isLoadingPreview = false
        if uiImage == nil {
            loadFailed = true
        }
    }
}

actor PreviewImageLoader {
    static let shared = PreviewImageLoader()

    private let session: URLSession
    private let cache: NSCache<NSString, UIImage>
    private var inflight: [NSString: Task<UIImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 180 * 1024 * 1024
        self.cache = cache
    }

    func image(
        for url: URL,
        maxPixel: CGFloat,
        retryQueued: Bool,
        attempts: Int = 1
    ) async -> UIImage? {
        let key = "\(url.absoluteString)|\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let task = inflight[key] {
            return await task.value
        }

        let task = Task<UIImage?, Never> { [session] in
            var delay: UInt64 = 300_000_000
            let totalAttempts = max(1, attempts)

            for attempt in 0..<totalAttempts {
                if Task.isCancelled { return nil }

                var request = APIClient.shared.imageRequest(for: url)
                request.timeoutInterval = 30

                guard let (data, response) = try? await session.data(for: request),
                      let http = response as? HTTPURLResponse,
                      http.statusCode < 400 else {
                    return nil
                }

                if http.value(forHTTPHeaderField: "X-Look-Preview") == "queued" {
                    guard retryQueued, attempt < totalAttempts - 1 else { return nil }
                    try? await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 1_800_000_000)
                    continue
                }

                return Self.downsample(data, maxPixel: maxPixel)
            }

            return nil
        }

        inflight[key] = task
        let image = await task.value
        inflight.removeValue(forKey: key)

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixel))
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}
