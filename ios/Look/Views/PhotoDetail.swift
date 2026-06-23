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
    @State private var showAddToAlbum = false
    @State private var showTagHistory = false
    @State private var downloadMessage: String?
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
                } else if let downloadMessage {
                    Text(downloadMessage)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding()
                        .task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            self.downloadMessage = nil
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
            if let date = photo.createdAt {
                Label(date, systemImage: "calendar").font(.caption).foregroundColor(.secondary)
            }
            if let w = photo.width, let h = photo.height {
                Label("\(w) × \(h)", systemImage: "viewfinder").font(.caption).foregroundColor(.secondary)
            }
            if let make = photo.exif?.make, let model = photo.exif?.model {
                Label("\(make) \(model)", systemImage: "camera").font(.caption).foregroundColor(.secondary)
            }
            if let size = photo.fileSize {
                Label(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
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
                        _ = try? await APIClient.shared.addTag(photo.id, tag: tag)
                        await loadTags()
                        newTag = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                isAutoTagging = true
                Task {
                    _ = try? await APIClient.shared.autoTag(photo.id)
                    await loadTags()
                    isAutoTagging = false
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
                                    _ = try? await APIClient.shared.removeTag(photo.id, tag: tag)
                                    await loadTags()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
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
                                _ = try? await APIClient.shared.addTag(photo.id, tag: tag)
                                await loadTags()
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
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Data

    private func loadTags() async {
        if let resp = try? await APIClient.shared.photoTags(photo.id) {
            photoTags = resp.tags ?? []
        }
    }

    private func loadSuggestions() async {
        if let resp = try? await APIClient.shared.tagSuggestions(photo.id) {
            suggestions = resp.suggestions
        }
    }

    private func saveJPEG() async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.downloadJPEGData(photo.id)
            guard let image = UIImage(data: data) else {
                downloadMessage = "Could not read image"; return
            }
            imageSaver.save(image) { error in
                downloadMessage = error == nil ? "Saved to Photos" : "Save failed: \(error!.localizedDescription)"
            }
        } catch {
            downloadMessage = "Download failed"
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
        } catch {
            downloadMessage = "RAW export failed"
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
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
