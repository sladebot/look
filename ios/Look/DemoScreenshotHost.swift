#if DEBUG
import SwiftUI
import UIKit
import CoreImage

enum LookDemoScreenshots {
    static let launchArgument = "--look-demo-screenshots"
    static let scenarioEnvironmentKey = "LOOK_DEMO_SCREEN"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var scenario: DemoScenario {
        DemoScenario(rawValue: ProcessInfo.processInfo.environment[scenarioEnvironmentKey] ?? "") ?? .gallery
    }
}

enum DemoScenario: String, CaseIterable {
    case connection
    case sync
    case gallery
    case multiselect
    case detail
    case library
    case search
    case settings

    var fileName: String {
        switch self {
        case .connection: return "01_tailnet_connection"
        case .sync: return "02_sync_progress"
        case .gallery: return "03_main_gallery"
        case .multiselect: return "04_long_press_multiselect"
        case .detail: return "05_photo_detail_tags"
        case .library: return "06_library_albums"
        case .search: return "07_search_mock_library"
        case .settings: return "08_settings_tailnet"
        }
    }
}

private enum DemoTab: String {
    case photos
    case library
    case search
    case settings
}

struct DemoScreenshotHost: View {
    @StateObject private var store = PhotoStore()
    private let scenario = LookDemoScreenshots.scenario

    init() {
        UserDefaults.standard.set(true, forKey: ConnectionSetupStorage.hasSuccessfulConnectionKey)
        UserDefaults.standard.set("http://studio.tailnet-name.ts.net:5678", forKey: ConnectionSetupStorage.serverURLKey)
    }

    var body: some View {
        Group {
            switch scenario {
            case .connection:
                ConnectionSetupView(onConnectionEstablished: {})
            case .detail:
                PhotoDetail(photo: DemoData.heroPhoto)
                    .environmentObject(store)
            case .sync:
                DemoWorkflowFrame(selected: .photos, title: "Photos", subtitle: "Syncing 1,856 photos") {
                    DemoGalleryWorkflow(syncing: true, selectedPhotoIds: [])
                }
            case .gallery:
                DemoWorkflowFrame(selected: .photos, title: "Photos", subtitle: "Private library over Tailscale") {
                    DemoGalleryWorkflow(syncing: false, selectedPhotoIds: [])
                }
            case .multiselect:
                DemoWorkflowFrame(selected: .photos, title: "4 Selected", subtitle: "Long-press any photo to select") {
                    DemoGalleryWorkflow(
                        syncing: false,
                        selectedPhotoIds: Set(DemoData.photos.prefix(4).map(\.id))
                    )
                }
            case .library:
                tabShell(selected: .library, photosView: PhotosGrid())
            case .search:
                DemoWorkflowFrame(selected: .search, title: "Search", subtitle: "Find by filename, tag, camera, or path") {
                    DemoSearchWorkflow()
                }
            case .settings:
                tabShell(selected: .settings, photosView: PhotosGrid())
            }
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .task {
            store.applyDemoData(syncing: scenario == .sync)
        }
    }

    private func tabShell(selected: DemoTab, photosView: PhotosGrid) -> some View {
        TabView(selection: .constant(selected)) {
            photosView
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
                .tag(DemoTab.photos)

            LibraryView()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label("Collections", systemImage: "rectangle.stack") }
                .tag(DemoTab.library)

            SearchView(initialQuery: "kyoto temple", initialResults: Array(DemoData.photos.prefix(18)))
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label("Find", systemImage: "magnifyingglass") }
                .tag(DemoTab.search)

            SettingsView()
                .ignoresSafeArea(.container, edges: .bottom)
                .tabItem { Label("Server", systemImage: "server.rack") }
                .tag(DemoTab.settings)
        }
        .tint(LookTheme.ColorToken.accentControl)
        .background(LookTheme.ColorToken.canvas.ignoresSafeArea())
        .toolbarBackground(.automatic, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct DemoWorkflowFrame<Content: View>: View {
    let selected: DemoTab
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LookTheme.ColorToken.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DemoTabBar(selected: selected)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: LookTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LookTheme.Typography.title)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            LookChip(title: "Tailscale", systemImage: "checkmark.circle.fill", tint: LookTheme.ColorToken.success)

            Button {} label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.accent)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.top, LookTheme.Spacing.small)
        .padding(.bottom, LookTheme.Spacing.medium)
        .background(.regularMaterial)
    }
}

private struct DemoGalleryWorkflow: View {
    let syncing: Bool
    let selectedPhotoIds: Set<String>

    private var selectionMode: Bool { !selectedPhotoIds.isEmpty }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(1, geo.size.width - LookTheme.Spacing.tight * 2)
            let target = max(118, contentWidth / (geo.size.width > 900 ? 6.2 : 3.2))

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: LookTheme.Spacing.tight) {
                    if syncing {
                        DemoSyncStrip()
                            .padding(.horizontal, LookTheme.Spacing.screen)
                            .padding(.top, LookTheme.Spacing.small)
                    }

                    DemoDateStrip(title: "Monday, Jun 8", count: 600)

                    ForEach(PhotoLayout.rows(
                        for: Array(DemoData.photos.prefix(42)),
                        width: contentWidth,
                        target: target,
                        spacing: LookTheme.Spacing.hairline,
                        aspect: demoPhotoAspect
                    )) { row in
                        HStack(spacing: LookTheme.Spacing.hairline) {
                            ForEach(row.items) { item in
                                DemoPhotoTile(
                                    photo: item.photo,
                                    isSelected: selectedPhotoIds.contains(item.photo.id),
                                    selectionMode: selectionMode
                                )
                                .frame(width: item.width, height: row.height)
                            }
                        }
                        .padding(.horizontal, LookTheme.Spacing.tight)
                    }
                }
                .padding(.top, LookTheme.Spacing.tight)
                .padding(.bottom, 18)
            }
            .background(LookTheme.ColorToken.canvas)
        }
    }
}

private func demoPhotoAspect(_ photo: Photo) -> CGFloat {
    if let width = photo.width, let height = photo.height, width > 0, height > 0 {
        return CGFloat(width) / CGFloat(height)
    }
    return 1
}

private struct DemoSearchWorkflow: View {
    private let results = Array(DemoData.photos.prefix(24))

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                HStack(spacing: LookTheme.Spacing.small) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("kyoto temple")
                        .font(.body)
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                    Spacer()
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LookTheme.ColorToken.accent)
                }
                .lookTextInput()

                VStack(alignment: .leading, spacing: 3) {
                    LookTheme.sectionHeader("Results")
                    Text("24 photos for \"kyoto temple\"")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 4)], spacing: 4) {
                    ForEach(results) { photo in
                        DemoPhotoTile(photo: photo, isSelected: false, selectionMode: false)
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
            }
            .padding(LookTheme.Spacing.screen)
            .padding(.bottom, 18)
        }
        .background(LookTheme.ColorToken.canvas)
    }
}

private struct DemoDateStrip: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
            Text(title)
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.primaryText)
            Spacer()
            Text("\(count) photos")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.vertical, LookTheme.Spacing.medium)
        .background(LookTheme.ColorToken.canvas)
    }
}

private struct DemoSyncStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(spacing: LookTheme.Spacing.small) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(LookTheme.Typography.captionEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.accent)
                Text("Syncing library")
                    .font(LookTheme.Typography.secondaryEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                Spacer()
                Text("60%")
                    .font(LookTheme.Typography.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }

            Text("Processing 1,122 of 1,856 mock photos")
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)

            DemoProgressBar(value: 0.60)
        }
        .padding(.horizontal, LookTheme.Spacing.medium)
        .padding(.vertical, LookTheme.Spacing.small)
        .frame(minHeight: 72)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.card, style: .continuous)
                .stroke(LookTheme.ColorToken.accent.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct DemoProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LookTheme.ColorToken.elevated)
                Capsule()
                    .fill(LookTheme.ColorToken.accent)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * value)))
            }
        }
        .frame(height: 6)
    }
}

private struct DemoPhotoTile: View {
    let photo: Photo
    let isSelected: Bool
    let selectionMode: Bool

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: LookDemoMockImage.image(identifier: photo.id, size: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .background(LookTheme.ColorToken.backdrop)
                .overlay(alignment: .bottomLeading) {
                    if photo.isFavorite == true && !selectionMode {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                            .padding(6)
                    }
                }
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.18)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.9),
                                             isSelected ? LookTheme.ColorToken.accent : .black.opacity(0.38))
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .padding(6)
                    }
                }
                .overlay(alignment: .leading) {
                    if isSelected {
                        Rectangle()
                            .fill(LookTheme.ColorToken.accent)
                            .frame(width: 5)
                    }
                }
                .overlay {
                    if isSelected {
                        Rectangle()
                            .stroke(LookTheme.ColorToken.accent, lineWidth: 2)
                    }
                }
        }
        .clipped()
    }
}

private struct DemoTabBar: View {
    let selected: DemoTab

    var body: some View {
        HStack(spacing: 0) {
            DemoTabBarItem(tab: .photos, selected: selected == .photos, title: "Photos", systemImage: "photo.on.rectangle.angled")
            DemoTabBarItem(tab: .library, selected: selected == .library, title: "Library", systemImage: "rectangle.stack")
            DemoTabBarItem(tab: .search, selected: selected == .search, title: "Search", systemImage: "magnifyingglass")
            DemoTabBarItem(tab: .settings, selected: selected == .settings, title: "Settings", systemImage: "gear")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

private struct DemoTabBarItem: View {
    let tab: DemoTab
    let selected: Bool
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(selected ? .white : LookTheme.ColorToken.primaryText.opacity(0.78))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            if selected {
                Capsule()
                    .fill(.white.opacity(0.14))
            }
        }
        .accessibilityLabel(title)
    }
}

@MainActor
private extension PhotoStore {
    func applyDemoData(syncing: Bool = false) {
        serverConnected = true
        photos = DemoData.photos
        albums = DemoData.albums
        smartCollections = DemoData.smartCollections
        allTags = DemoData.tags
        totalPhotos = 1856
        currentOffset = photos.count
        hasMorePhotos = false
        isLoading = false
        errorMessage = nil
        autoSyncEnabled = true
        lastSyncMessage = "Library up to date (1,856 photos)"
        lastAutoSyncAt = Date()
        serverSettings = [
            "smart_albums_enabled": "true",
            "dedup_enabled": "false",
            "tag_history_enabled": "true",
            "auto_tag_gps": "true",
            "auto_tag_camera": "true",
        ]

        if syncing {
            isSyncing = true
            syncProgressFraction = 0.60
            syncProgressMessage = "Processing 1,122 of 1,856 mock photos"
            syncTask = TaskInfo(
                taskId: "demo-sync",
                taskType: "import",
                status: "running",
                error: nil,
                createdAt: "2026-06-08T09:42:00",
                completedAt: nil,
                progress: .object([
                    "current": JSONValue.int(1122),
                    "total_scanned": JSONValue.int(1856),
                    "phase": JSONValue.string("processing"),
                ]),
                result: nil
            )
        } else {
            isSyncing = false
            syncProgressFraction = nil
            syncProgressMessage = nil
            syncTask = nil
        }
    }
}

enum DemoData {
    static let heroPhoto = photos[6]

    static let photos: [Photo] = {
        let sizes: [(Int, Int)] = [
            (4032, 3024), (3024, 4032), (3900, 2600), (2400, 3000), (4096, 2304),
            (3024, 4032), (4032, 3024), (2600, 3900), (4096, 2730), (3024, 3024),
            (4200, 2800), (2800, 4200), (4032, 3024), (2304, 4096), (4096, 3072),
        ]
        let names = [
            "Kyoto ridge 001.jpg", "Temple walkway 014.jpg", "Blue hour harbor.jpg",
            "Cedar path portrait.jpg", "Morning market.jpg", "Torii shadow raw.dng",
            "Golden hour ridge.jpg", "Rain glass study.jpg", "Family archive.jpg",
            "Studio contact sheet.jpg", "Sea wall dusk.jpg", "Garden lantern.jpg",
            "Museum window.jpg", "Forest gate.jpg", "Neon crossing.jpg",
        ]

        return (0..<48).map { index in
            let size = sizes[index % sizes.count]
            let name = names[index % names.count]
            let day = 8 - min(index / 16, 2)
            return Photo(
                id: "demo-photo-\(index)",
                filename: name.replacingOccurrences(of: ".jpg", with: " \(index + 1).jpg"),
                filepath: "/demo/look/\(name)",
                fileSize: 2_400_000 + index * 91_000,
                width: size.0,
                height: size.1,
                mimeType: name.hasSuffix(".dng") ? "image/x-raw" : "image/jpeg",
                createdAt: "2026-06-\(String(format: "%02d", day))T\(String(format: "%02d", 9 + (index % 8))):24:00",
                hasThumbnail: true,
                isFavorite: [2, 6, 11, 19, 27].contains(index),
                exif: EXIFData(make: "Apple", model: "iPhone 17 Pro", datetime: "2026:06:\(String(format: "%02d", day)) 09:24:00", gps: GPSData(lat: 35.0116, lon: 135.7681)),
                gpsLat: 35.0116,
                gpsLon: 135.7681
            )
        }
    }()

    static let albums: [Album] = [
        Album(id: "favorites", name: "Favorites", description: "Hand-picked edits and selects.", photoCount: 184, source: "manual", photos: Array(photos.prefix(8))),
        Album(id: "japan", name: "Japan selects", description: "Travel selects ready to share.", photoCount: 92, source: "manual", photos: Array(photos.dropFirst(8).prefix(8))),
        Album(id: "archive", name: "Family archive", description: "Scans and restored memories.", photoCount: 640, source: "manual", photos: Array(photos.dropFirst(16).prefix(8))),
    ]

    static let smartCollections: [SmartCollection] = [
        SmartCollection(id: "iphone", name: "Shot on iPhone", description: "Auto-updated from camera metadata.", ruleSpec: "{\"rules\":[{\"field\":\"camera\",\"op\":\"contains\",\"value\":\"iPhone\"}]}", lastEvaluatedAt: "2026-06-08T09:48:00", photos: Array(photos.prefix(10))),
        SmartCollection(id: "raw", name: "RAW originals", description: "DNG and camera RAW files.", ruleSpec: "{\"rules\":[{\"field\":\"mime_type\",\"op\":\"equals\",\"value\":\"image/x-raw\"}]}", lastEvaluatedAt: "2026-06-08T09:48:00", photos: Array(photos.dropFirst(5).prefix(6))),
    ]

    static let tags: [TagInfo] = [
        TagInfo(tag: "travel", count: 92),
        TagInfo(tag: "portfolio", count: 36),
        TagInfo(tag: "family", count: 640),
        TagInfo(tag: "landscape", count: 118),
    ]

    static let detailTags = ["travel", "portfolio", "landscape"]
    static let suggestedTags = ["kyoto", "golden hour", "iPhone"]
}

enum LookDemoMockImage {
    static func image(identifier: String, size: CGSize) -> UIImage {
        let width = max(180, min(560, Int(size.width)))
        let height = max(180, min(560, Int(size.height)))
        let cacheKey = "\(identifier)|\(width)x\(height)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        if let bundled = bundledDemoPhoto(identifier: identifier, width: width, height: height) {
            imageCache.setObject(bundled, forKey: cacheKey)
            return bundled
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let seed = abs(identifier.hashValue)

        let raw = renderer.image { context in
            let cg = context.cgContext
            var generator = SeededGenerator(seed: UInt64(seed))
            switch seed % 7 {
            case 0: drawMountainLake(in: cg, width: width, height: height, rng: &generator)
            case 1: drawForestGate(in: cg, width: width, height: height, rng: &generator)
            case 2: drawCityNight(in: cg, width: width, height: height, rng: &generator)
            case 3: drawCoastline(in: cg, width: width, height: height, rng: &generator)
            case 4: drawArchiveRoom(in: cg, width: width, height: height, rng: &generator)
            case 5: drawMarketMorning(in: cg, width: width, height: height, rng: &generator)
            default: drawGardenLantern(in: cg, width: width, height: height, rng: &generator)
            }
            addPhotoFinish(in: cg, width: width, height: height, rng: &generator)
        }
        let finished = photographicFinish(raw, seed: seed)
        imageCache.setObject(finished, forKey: cacheKey)
        return finished
    }

    private static func bundledDemoPhoto(identifier: String, width: Int, height: Int) -> UIImage? {
        let assetIndex = photoIndex(from: identifier)
        let assetName = String(format: "DemoPhoto%02d", assetIndex)
        guard let source = UIImage(named: assetName) else { return nil }

        let targetSize = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))

            let sourceSize = source.size
            let scale = max(targetSize.width / max(1, sourceSize.width),
                            targetSize.height / max(1, sourceSize.height))
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            source.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    private static func photoIndex(from identifier: String) -> Int {
        let number = identifier
            .split(separator: "-")
            .last
            .flatMap { Int($0) } ?? 0
        return (number % 16) + 1
    }

    private static func gradient(_ cg: CGContext, _ colors: [UIColor], width: Int, height: Int, vertical: Bool = true) {
        let cgColors = colors.map(\.cgColor) as CFArray
        let stops = colors.enumerated().map { CGFloat($0.offset) / CGFloat(max(1, colors.count - 1)) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: stops) else { return }
        let end = vertical ? CGPoint(x: 0, y: height) : CGPoint(x: width, y: height)
        cg.drawLinearGradient(gradient, start: .zero, end: end, options: [])
    }

    private static func polygon(_ cg: CGContext, _ points: [CGPoint], fill: UIColor) {
        guard let first = points.first else { return }
        cg.beginPath()
        cg.move(to: first)
        points.dropFirst().forEach { cg.addLine(to: $0) }
        cg.closePath()
        cg.setFillColor(fill.cgColor)
        cg.fillPath()
    }

    private static func drawMountainLake(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.04, green: 0.13, blue: 0.20, alpha: 1), UIColor(red: 0.19, green: 0.48, blue: 0.62, alpha: 1), UIColor(red: 0.93, green: 0.66, blue: 0.34, alpha: 1)], width: width, height: height)
        UIColor(red: 1, green: 0.73, blue: 0.35, alpha: 0.74).setFill()
        cg.fillEllipse(in: CGRect(x: w * 0.66, y: h * 0.13, width: w * 0.18, height: w * 0.18))
        polygon(cg, [CGPoint(x: -w * 0.1, y: h * 0.58), CGPoint(x: w * 0.22, y: h * 0.26), CGPoint(x: w * 0.52, y: h * 0.58)], fill: UIColor(red: 0.07, green: 0.17, blue: 0.18, alpha: 0.9))
        polygon(cg, [CGPoint(x: w * 0.24, y: h * 0.59), CGPoint(x: w * 0.58, y: h * 0.22), CGPoint(x: w * 1.12, y: h * 0.60)], fill: UIColor(red: 0.05, green: 0.12, blue: 0.18, alpha: 0.92))
        gradient(cg, [UIColor(red: 0.04, green: 0.18, blue: 0.24, alpha: 0.72), UIColor(red: 0.08, green: 0.30, blue: 0.36, alpha: 0.78)], width: width, height: height)
        UIColor(red: 0.01, green: 0.05, blue: 0.06, alpha: 0.62).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.62, width: w, height: h * 0.38))
        for i in 0..<8 {
            let y = h * (0.66 + CGFloat(i) * 0.035)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1.4)
            cg.move(to: CGPoint(x: w * 0.06, y: y))
            cg.addCurve(to: CGPoint(x: w * 0.94, y: y + CGFloat.random(in: -8...8, using: &rng)), control1: CGPoint(x: w * 0.28, y: y - 10), control2: CGPoint(x: w * 0.66, y: y + 10))
            cg.strokePath()
        }
    }

    private static func drawForestGate(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.02, green: 0.11, blue: 0.09, alpha: 1), UIColor(red: 0.08, green: 0.27, blue: 0.17, alpha: 1), UIColor(red: 0.74, green: 0.50, blue: 0.22, alpha: 1)], width: width, height: height)
        UIColor(red: 0.02, green: 0.06, blue: 0.04, alpha: 0.64).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.58, width: w, height: h * 0.42))
        for _ in 0..<18 {
            let x = CGFloat.random(in: -w * 0.1...w * 1.1, using: &rng)
            let lineWidth = CGFloat.random(in: 4...13, using: &rng)
            cg.setStrokeColor(UIColor(red: 0.02, green: 0.05, blue: 0.03, alpha: 0.72).cgColor)
            cg.setLineWidth(lineWidth)
            cg.move(to: CGPoint(x: x, y: 0))
            cg.addLine(to: CGPoint(x: x + CGFloat.random(in: -70...70, using: &rng), y: h))
            cg.strokePath()
        }
        let red = UIColor(red: 0.86, green: 0.16, blue: 0.07, alpha: 0.92)
        red.setFill()
        cg.fill(CGRect(x: w * 0.18, y: h * 0.24, width: w * 0.64, height: h * 0.07))
        cg.fill(CGRect(x: w * 0.24, y: h * 0.31, width: w * 0.09, height: h * 0.50))
        cg.fill(CGRect(x: w * 0.67, y: h * 0.31, width: w * 0.09, height: h * 0.50))
        UIColor.black.withAlphaComponent(0.22).setFill()
        cg.fill(CGRect(x: w * 0.31, y: h * 0.31, width: w * 0.38, height: h * 0.06))
    }

    private static func drawCityNight(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1), UIColor(red: 0.12, green: 0.07, blue: 0.22, alpha: 1), UIColor(red: 0.02, green: 0.04, blue: 0.07, alpha: 1)], width: width, height: height)
        for i in 0..<8 {
            let buildingW = w / 8.2
            let x = CGFloat(i) * buildingW + CGFloat.random(in: -12...12, using: &rng)
            let top = CGFloat.random(in: h * 0.22...h * 0.48, using: &rng)
            UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 0.92).setFill()
            cg.fill(CGRect(x: x, y: top, width: buildingW * 0.9, height: h - top))
            for row in stride(from: top + 18, to: h * 0.72, by: 28) {
                if Bool.random(using: &rng) {
                    UIColor(red: 0.27, green: 0.78, blue: 1.0, alpha: 0.56).setFill()
                } else {
                    UIColor(red: 1.0, green: 0.45, blue: 0.24, alpha: 0.54).setFill()
                }
                cg.fill(CGRect(x: x + buildingW * 0.18, y: row, width: buildingW * 0.16, height: 9))
                cg.fill(CGRect(x: x + buildingW * 0.55, y: row, width: buildingW * 0.16, height: 9))
            }
        }
        UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.8).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.75, width: w, height: h * 0.25))
        for _ in 0..<9 {
            UIColor(red: 0.24, green: 0.73, blue: 1.0, alpha: CGFloat.random(in: 0.28...0.62, using: &rng)).setFill()
            let r = CGFloat.random(in: 18...54, using: &rng)
            cg.fillEllipse(in: CGRect(x: CGFloat.random(in: 0...w, using: &rng), y: CGFloat.random(in: h * 0.62...h * 0.92, using: &rng), width: r, height: r))
        }
    }

    private static func drawCoastline(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.06, green: 0.24, blue: 0.36, alpha: 1), UIColor(red: 0.20, green: 0.59, blue: 0.72, alpha: 1), UIColor(red: 0.96, green: 0.78, blue: 0.46, alpha: 1)], width: width, height: height)
        UIColor(red: 0.02, green: 0.18, blue: 0.26, alpha: 0.74).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.49, width: w, height: h * 0.51))
        UIColor(red: 0.93, green: 0.86, blue: 0.67, alpha: 0.9).setFill()
        cg.move(to: CGPoint(x: 0, y: h * 0.68))
        cg.addCurve(to: CGPoint(x: w, y: h * 0.57), control1: CGPoint(x: w * 0.26, y: h * 0.58), control2: CGPoint(x: w * 0.66, y: h * 0.76))
        cg.addLine(to: CGPoint(x: w, y: h))
        cg.addLine(to: CGPoint(x: 0, y: h))
        cg.closePath()
        cg.fillPath()
        for _ in 0..<7 {
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            cg.setLineWidth(CGFloat.random(in: 2...5, using: &rng))
            let y = CGFloat.random(in: h * 0.52...h * 0.72, using: &rng)
            cg.move(to: CGPoint(x: 0, y: y))
            cg.addCurve(to: CGPoint(x: w, y: y + CGFloat.random(in: -20...20, using: &rng)), control1: CGPoint(x: w * 0.28, y: y - 30), control2: CGPoint(x: w * 0.72, y: y + 30))
            cg.strokePath()
        }
    }

    private static func drawArchiveRoom(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.19, green: 0.13, blue: 0.10, alpha: 1), UIColor(red: 0.55, green: 0.36, blue: 0.22, alpha: 1), UIColor(red: 0.94, green: 0.70, blue: 0.43, alpha: 1)], width: width, height: height)
        UIColor.black.withAlphaComponent(0.20).setFill()
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for row in 0..<4 {
            for col in 0..<5 {
                let x = w * 0.08 + CGFloat(col) * w * 0.18
                let y = h * 0.18 + CGFloat(row) * h * 0.16
                UIColor(red: CGFloat.random(in: 0.58...0.94, using: &rng), green: CGFloat.random(in: 0.47...0.76, using: &rng), blue: CGFloat.random(in: 0.32...0.55, using: &rng), alpha: 0.78).setFill()
                cg.fill(CGRect(x: x, y: y, width: w * 0.13, height: h * 0.10))
            }
        }
        UIColor(red: 0.05, green: 0.04, blue: 0.03, alpha: 0.62).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28))
        UIColor(red: 1.0, green: 0.88, blue: 0.55, alpha: 0.28).setFill()
        cg.fillEllipse(in: CGRect(x: w * 0.58, y: h * 0.08, width: w * 0.32, height: h * 0.18))
    }

    private static func drawMarketMorning(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.18, green: 0.10, blue: 0.07, alpha: 1), UIColor(red: 0.75, green: 0.36, blue: 0.20, alpha: 1), UIColor(red: 0.99, green: 0.77, blue: 0.42, alpha: 1)], width: width, height: height)
        for i in 0..<6 {
            let x = CGFloat(i) * w / 6
            polygon(cg, [CGPoint(x: x - w * 0.08, y: h * 0.32), CGPoint(x: x + w * 0.18, y: h * 0.32), CGPoint(x: x + w * 0.05, y: h * 0.54)], fill: UIColor(red: CGFloat.random(in: 0.55...0.95, using: &rng), green: CGFloat.random(in: 0.12...0.42, using: &rng), blue: CGFloat.random(in: 0.08...0.22, using: &rng), alpha: 0.82))
        }
        UIColor(red: 0.04, green: 0.03, blue: 0.02, alpha: 0.45).setFill()
        cg.fill(CGRect(x: 0, y: h * 0.56, width: w, height: h * 0.44))
        for _ in 0..<10 {
            let x = CGFloat.random(in: 0...w, using: &rng)
            let y = CGFloat.random(in: h * 0.58...h * 0.86, using: &rng)
            UIColor.black.withAlphaComponent(0.38).setFill()
            cg.fillEllipse(in: CGRect(x: x, y: y, width: w * 0.035, height: h * 0.09))
        }
    }

    private static func drawGardenLantern(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        gradient(cg, [UIColor(red: 0.02, green: 0.13, blue: 0.09, alpha: 1), UIColor(red: 0.13, green: 0.32, blue: 0.19, alpha: 1), UIColor(red: 0.44, green: 0.46, blue: 0.25, alpha: 1)], width: width, height: height)
        for _ in 0..<20 {
            UIColor(red: 0.08, green: CGFloat.random(in: 0.26...0.52, using: &rng), blue: 0.13, alpha: CGFloat.random(in: 0.18...0.42, using: &rng)).setFill()
            let r = CGFloat.random(in: w * 0.08...w * 0.24, using: &rng)
            cg.fillEllipse(in: CGRect(x: CGFloat.random(in: -r...w, using: &rng), y: CGFloat.random(in: -r...h * 0.85, using: &rng), width: r, height: r * 0.72))
        }
        let stone = UIColor(red: 0.47, green: 0.46, blue: 0.39, alpha: 0.9)
        stone.setFill()
        cg.fill(CGRect(x: w * 0.45, y: h * 0.44, width: w * 0.10, height: h * 0.36))
        cg.fill(CGRect(x: w * 0.35, y: h * 0.36, width: w * 0.30, height: h * 0.10))
        cg.fill(CGRect(x: w * 0.40, y: h * 0.28, width: w * 0.20, height: h * 0.08))
        UIColor(red: 1.0, green: 0.74, blue: 0.36, alpha: 0.42).setFill()
        cg.fillEllipse(in: CGRect(x: w * 0.36, y: h * 0.33, width: w * 0.28, height: h * 0.24))
    }

    private static func addPhotoFinish(in cg: CGContext, width: Int, height: Int, rng: inout SeededGenerator) {
        let w = CGFloat(width), h = CGFloat(height)
        for _ in 0..<9 {
            cg.setStrokeColor(UIColor.white.withAlphaComponent(CGFloat.random(in: 0.03...0.10, using: &rng)).cgColor)
            cg.setLineWidth(CGFloat.random(in: 1...4, using: &rng))
            let x = CGFloat.random(in: 0...w, using: &rng)
            cg.move(to: CGPoint(x: x, y: 0))
            cg.addLine(to: CGPoint(x: x + CGFloat.random(in: -80...80, using: &rng), y: h))
            cg.strokePath()
        }
        UIColor.black.withAlphaComponent(0.18).setFill()
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        cg.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        cg.fillEllipse(in: CGRect(x: -w * 0.18, y: -h * 0.18, width: w * 0.42, height: h * 0.42))
        cg.fillEllipse(in: CGRect(x: w * 0.76, y: h * 0.78, width: w * 0.40, height: h * 0.36))
    }

    private static func photographicFinish(_ image: UIImage, seed: Int) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let radius = max(image.size.width, image.size.height) > 700 ? 3.2 : 1.6
        let blurred = ciImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: ciImage.extent)
            .applyingFilter("CIPhotoEffectProcess")

        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            let cg = context.cgContext
            if let output = ciContext.createCGImage(blurred, from: ciImage.extent) {
                cg.draw(output, in: CGRect(origin: .zero, size: image.size))
            } else {
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }

            var generator = SeededGenerator(seed: UInt64(seed))
            let w = image.size.width
            let h = image.size.height
            for _ in 0..<Int(w * h / 3200) {
                let alpha = CGFloat.random(in: 0.018...0.052, using: &generator)
                let shade = CGFloat.random(in: 0.35...1.0, using: &generator)
                UIColor(white: shade, alpha: alpha).setFill()
                let x = CGFloat.random(in: 0...w, using: &generator)
                let y = CGFloat.random(in: 0...h, using: &generator)
                cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }

            let vignette = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0.00).cgColor,
                    UIColor.black.withAlphaComponent(0.32).cgColor,
                ] as CFArray,
                locations: [0.58, 1.0]
            )
            if let vignette {
                cg.drawRadialGradient(
                    vignette,
                    startCenter: CGPoint(x: w / 2, y: h / 2),
                    startRadius: min(w, h) * 0.22,
                    endCenter: CGPoint(x: w / 2, y: h / 2),
                    endRadius: max(w, h) * 0.72,
                    options: [.drawsAfterEndLocation]
                )
            }
        }
    }

    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 72 * 1024 * 1024
        return cache
    }()
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x1234abcd : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
