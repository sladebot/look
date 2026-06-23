import SwiftUI
import MapKit

struct PhotoDetail: View {
    let photo: Photo
    @EnvironmentObject var store: PhotoStore
    @State private var photoTags: [String] = []
    @State private var suggestions: [String] = []
    @State private var newTag = ""
    @State private var showFullScreen = false
    @State private var isAutoTagging = false
    @State private var isLoadingTags = false
    @State private var isLoadingSuggestions = false
    @State private var tagAction: PhotoDetailAction?
    @State private var showAddToAlbum = false
    @State private var showTagHistory = false
    @State private var statusMessage: String?
    @State private var isDownloading = false
    @State private var shareItem: ShareItem?

    private let imageSaver = ImageSaver()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageSection
                    metadataSection
                    if photo.hasLocation { mapSection }
                    Divider()
                    tagsSection
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddToAlbum = true } label: {
                            Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                        }
                        Button { Task { await saveJPEG() } } label: {
                            Label("Save JPEG to Photos", systemImage: "square.and.arrow.down")
                        }
                        if photo.filename.lowercased().hasSuffix(".arw")
                            || photo.filename.lowercased().hasSuffix(".cr2")
                            || photo.filename.lowercased().hasSuffix(".nef")
                            || photo.filename.lowercased().hasSuffix(".dng") {
                            Button { Task { await shareRAW() } } label: {
                                Label("Export RAW Original", systemImage: "doc.badge.arrow.up")
                            }
                        }
                        Button { showTagHistory = true } label: {
                            Label("Tag History", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isDownloading {
                    ProgressView("Downloading…")
                        .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                } else if let activeTagAction = tagAction, activeTagAction.isLoading {
                    ProgressView(activeTagAction.loadingMessage)
                        .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                } else if let statusMessage {
                    Text(statusMessage)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                        .task {
                            do {
                                try await Task.sleep(nanoseconds: 2_500_000_000)
                            } catch {
                                return
                            }
                            self.statusMessage = nil
                        }
                }
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                ZStack(alignment: .topTrailing) {
                    FullScreenImage(photo: photo)
                    Button { showFullScreen = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title).foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showAddToAlbum) { AddToAlbumSheet(photo: photo) }
            .sheet(isPresented: $showTagHistory) { TagHistoryView(photoId: photo.id) }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
            .task {
                await loadTags()
                await loadSuggestions()
            }
        }
    }

    // MARK: - Sections

    private var imageSection: some View {
        CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 512), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220)
            .cornerRadius(12)
            .onTapGesture { showFullScreen = true }
        .padding(.horizontal)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(photo.filename).font(.title2).fontWeight(.bold)
                if photo.isFavorite == true {
                    Image(systemName: "heart.fill").foregroundColor(.pink)
                }
            }
            if let date = PhotoDetailMetadataFormatter.displayDate(from: photo.createdAt) {
                Label(date, systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            }
            if let w = photo.width, let h = photo.height {
                Label(PhotoDetailMetadataFormatter.dimensions(width: w, height: h), systemImage: "viewfinder")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let camera = PhotoDetailMetadataFormatter.camera(make: photo.exif?.make, model: photo.exif?.model) {
                Label(camera, systemImage: "camera").font(.caption).foregroundColor(.secondary)
            }
            if let fileDetails = PhotoDetailMetadataFormatter.fileDetails(filename: photo.filename,
                                                                         mimeType: photo.mimeType,
                                                                         fileSize: photo.fileSize) {
                Label(fileDetails,
                      systemImage: "internaldrive").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location").font(.headline)
            if let lat = photo.latitude, let lon = photo.longitude {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                    Marker(photo.filename, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
                .frame(height: 180)
                .cornerRadius(12)
                .allowsHitTesting(false)
                Text(String(format: "%.5f, %.5f", lat, lon))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.headline)

            HStack {
                TextField("Add tag...", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let tag = newTag.trimmingCharacters(in: .whitespaces)
                    guard !tag.isEmpty else { return }
                    Task {
                        await addTag(tag)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty || tagAction != nil)
            }

            Button {
                Task {
                    await autoTag()
                }
            } label: {
                HStack {
                    if isAutoTagging { ProgressView().scaleEffect(0.7) }
                    Text("Auto-tag from EXIF")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAutoTagging)

            if photoTags.isEmpty {
                Text("No tags").font(.caption).foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(photoTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption)
                            Button {
                                Task {
                                    await removeTag(tag)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
                            .disabled(tagAction != nil)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }

            // Suggested tags (not yet applied)
            let pending = suggestions.filter { !photoTags.contains($0) }
            if !pending.isEmpty {
                Text("Suggestions").font(.subheadline).padding(.top, 4)
                FlowLayout(spacing: 6) {
                    ForEach(pending, id: \.self) { tag in
                        Button {
                            Task {
                                await addTag(tag)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle").font(.caption2)
                                Text(tag).font(.caption)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(tagAction != nil)
                    }
                }
            }

            if isLoadingTags || isLoadingSuggestions {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(isLoadingTags ? "Loading tags…" : "Loading suggestions…")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Data

    private func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }
        do {
            photoTags = try await fetchTags()
        } catch {
            showMessage("Could not load tags: \(error.localizedDescription)")
        }
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        do {
            let resp = try await APIClient.shared.tagSuggestions(photo.id)
            suggestions = resp.suggestions
        } catch {
            showMessage("Could not load suggestions: \(error.localizedDescription)")
        }
    }

    private func addTag(_ tag: String) async {
        tagAction = .adding(tag)
        defer { tagAction = nil }
        do {
            let response = try await APIClient.shared.addTag(photo.id, tag: tag)
            if let tags = response.tags {
                photoTags = tags
            } else if !photoTags.contains(tag) {
                photoTags.append(tag)
            }
            newTag = ""
            showMessage("Added tag \"\(tag)\"")
        } catch {
            showMessage("Could not add \"\(tag)\": \(error.localizedDescription)")
        }
    }

    private func removeTag(_ tag: String) async {
        tagAction = .removing(tag)
        defer { tagAction = nil }
        do {
            try await APIClient.shared.removeTag(photo.id, tag: tag)
            photoTags.removeAll { $0 == tag }
            showMessage("Removed tag \"\(tag)\"")
        } catch {
            showMessage("Could not remove \"\(tag)\": \(error.localizedDescription)")
        }
    }

    private func autoTag() async {
        isAutoTagging = true
        tagAction = .autoTagging
        defer {
            isAutoTagging = false
            tagAction = nil
        }
        do {
            let response = try await APIClient.shared.autoTag(photo.id)
            do {
                photoTags = try await fetchTags()
            } catch {
                showMessage("Auto-tag completed, but tags could not refresh: \(error.localizedDescription)")
                return
            }
            let added = response.tagsAdded?.count ?? 0
            showMessage(added == 0 ? "No new EXIF tags found" : "Added \(added) EXIF tag\(added == 1 ? "" : "s")")
        } catch {
            showMessage("Auto-tag failed: \(error.localizedDescription)")
        }
    }

    private func saveJPEG() async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.downloadJPEGData(photo.id)
            guard let image = UIImage(data: data) else {
                showMessage("Could not read image"); return
            }
            imageSaver.save(image) { error in
                let message = error == nil ? "Saved to Photos" : "Save failed: \(error!.localizedDescription)"
                Task { @MainActor in
                    showMessage(message)
                }
            }
        } catch {
            showMessage("Download failed: \(error.localizedDescription)")
        }
    }

    private func shareRAW() async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.downloadRawData(photo.id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(photo.filename)
            try data.write(to: url)
            shareItem = ShareItem(url: url)
            showMessage("RAW original ready to share")
        } catch {
            showMessage("RAW export failed: \(error.localizedDescription)")
        }
    }

    private func showMessage(_ message: String) {
        statusMessage = message
    }

    private func fetchTags() async throws -> [String] {
        let response = try await APIClient.shared.photoTags(photo.id)
        return response.tags ?? []
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum PhotoDetailAction: Equatable {
    case adding(String)
    case removing(String)
    case autoTagging

    var isLoading: Bool { true }

    var loadingMessage: String {
        switch self {
        case .adding(let tag): return "Adding \"\(tag)\"…"
        case .removing(let tag): return "Removing \"\(tag)\"…"
        case .autoTagging: return "Auto-tagging…"
        }
    }
}

private enum PhotoDetailMetadataFormatter {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func displayDate(from raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let date = parseDate(raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dimensions(width: Int, height: Int) -> String {
        "\(width.formatted()) x \(height.formatted()) px"
    }

    static func camera(make: String?, model: String?) -> String? {
        let make = normalized(make)
        let model = normalized(model)

        switch (make, model) {
        case let (make?, model?) where model.localizedCaseInsensitiveContains(make):
            return model
        case let (make?, model?):
            return "\(make) \(model)"
        case let (make?, nil):
            return make
        case let (nil, model?):
            return model
        default:
            return nil
        }
    }

    static func fileDetails(filename: String, mimeType: String?, fileSize: Int?) -> String? {
        var details: [String] = []
        let ext = URL(fileURLWithPath: filename).pathExtension.uppercased()
        if !ext.isEmpty { details.append(ext) }
        if let mime = normalized(mimeType) { details.append(mime) }
        if let fileSize {
            details.append(byteFormatter.string(fromByteCount: Int64(fileSize)))
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy:MM:dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

/// UIKit share sheet bridge for exporting RAW originals to Files / other apps.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Simple wrapping flow layout for tag pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
