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
    @State private var status: PhotoDetailStatus?
    @State private var isDownloading = false
    @State private var shareItem: ShareItem?

    private let imageSaver = ImageSaver()
    private var isRawOriginal: Bool { Self.rawExtensions.contains(photo.fileExtension) }
    private static let rawExtensions: Set<String> = ["arw", "cr2", "nef", "dng"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageSection
                    VStack(alignment: .leading, spacing: 16) {
                        titleSection
                        actionRowsSection
                        metadataSection
                        if photo.hasLocation { mapSection }
                        tagsSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 28)
                }
            }
            .background(Color(.systemGroupedBackground))
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
                        if isRawOriginal {
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
                    .accessibilityLabel("More photo actions")
                }
            }
            .overlay(alignment: .bottom) {
                if isDownloading {
                    PhotoDetailStatusBanner(kind: .progress, message: "Downloading…")
                } else if let activeTagAction = tagAction, activeTagAction.isLoading {
                    PhotoDetailStatusBanner(kind: .progress, message: activeTagAction.loadingMessage)
                } else if let status {
                    PhotoDetailStatusBanner(kind: status.kind, message: status.message)
                        .task {
                            do {
                                try await Task.sleep(nanoseconds: 2_500_000_000)
                            } catch {
                                return
                            }
                            if self.status == status {
                                self.status = nil
                            }
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
        Button {
            showFullScreen = true
        } label: {
            PhotoDetailImage(url: APIClient.shared.fullImageURL(for: photo.id),
                             accessibilityLabel: "Open full screen preview for \(photo.filename)")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full screen preview for \(photo.filename)")
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(photo.filename)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .accessibilityLabel("Filename, \(photo.filename)")
                if photo.isFavorite == true {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.pink)
                        .accessibilityLabel("Favorite")
                }
            }
            if let date = PhotoDetailMetadataFormatter.displayDate(from: photo.createdAt) {
                Label(date, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Created \(date)")
            }
        }
    }

    private var actionRowsSection: some View {
        PhotoDetailPanel {
            VStack(spacing: 0) {
                PhotoDetailActionRow(systemImage: "rectangle.stack.badge.plus",
                                     title: "Add to Album",
                                     detail: "Organize this photo") {
                    showAddToAlbum = true
                }

                PhotoDetailSeparator()

                PhotoDetailActionRow(systemImage: "square.and.arrow.down",
                                     title: "Save JPEG",
                                     detail: "Download to Photos",
                                     isWorking: isDownloading) {
                    Task { await saveJPEG() }
                }
                .disabled(isDownloading)

                if isRawOriginal {
                    PhotoDetailSeparator()
                    PhotoDetailActionRow(systemImage: "doc.badge.arrow.up",
                                         title: "Export RAW Original",
                                         detail: photo.fileExtension.uppercased(),
                                         isWorking: isDownloading) {
                        Task { await shareRAW() }
                    }
                    .disabled(isDownloading)
                }

                PhotoDetailSeparator()

                PhotoDetailActionRow(systemImage: "clock.arrow.circlepath",
                                     title: "Tag History",
                                     detail: "Review tag changes") {
                    showTagHistory = true
                }
            }
        }
    }

    private var metadataSection: some View {
        PhotoDetailPanel(header: "Metadata") {
            VStack(spacing: 0) {
                if let w = photo.width, let h = photo.height {
                    PhotoDetailInfoRow(systemImage: "viewfinder",
                                       title: "Dimensions",
                                       value: PhotoDetailMetadataFormatter.dimensions(width: w, height: h))
                    PhotoDetailSeparator()
                }

                if let camera = PhotoDetailMetadataFormatter.camera(make: photo.exif?.make, model: photo.exif?.model) {
                    PhotoDetailInfoRow(systemImage: "camera",
                                       title: "Camera",
                                       value: camera)
                    PhotoDetailSeparator()
                }

                if let fileDetails = PhotoDetailMetadataFormatter.fileDetails(filename: photo.filename,
                                                                              mimeType: photo.mimeType,
                                                                              fileSize: photo.fileSize) {
                    PhotoDetailInfoRow(systemImage: "internaldrive",
                                       title: "File",
                                       value: fileDetails)
                    PhotoDetailSeparator()
                }

                PhotoDetailInfoRow(systemImage: "doc.text",
                                   title: "Path",
                                   value: photo.filepath)
            }
        }
    }

    private var mapSection: some View {
        PhotoDetailPanel(header: "Location") {
            if let lat = photo.latitude, let lon = photo.longitude {
                VStack(alignment: .leading, spacing: 12) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                        Marker(photo.filename, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Map showing photo location")

                    PhotoDetailInfoRow(systemImage: "location",
                                       title: "Coordinates",
                                       value: String(format: "%.5f, %.5f", lat, lon))
                }
            }
        }
    }

    private var tagsSection: some View {
        PhotoDetailPanel(header: "Tags") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            newTagField
                            addTagButton
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            newTagField
                            addTagButton
                        }
                    }

                    Button {
                        Task {
                            await autoTag()
                        }
                    } label: {
                        Label {
                            Text(isAutoTagging ? "Auto-tagging…" : "Auto-tag from EXIF")
                        } icon: {
                            if isAutoTagging {
                                ProgressView()
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAutoTagging)
                    .accessibilityLabel("Auto-tag from EXIF")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Applied")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if photoTags.isEmpty {
                        PhotoDetailEmptyState(systemImage: "tag",
                                              text: "No tags applied")
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(photoTags, id: \.self) { tag in
                                HStack(spacing: 6) {
                                    Text(tag)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Button {
                                        Task {
                                            await removeTag(tag)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .imageScale(.small)
                                    }
                                    .disabled(tagAction != nil)
                                    .accessibilityLabel("Remove \(tag)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                if !pendingSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        FlowLayout(spacing: 8) {
                            ForEach(pendingSuggestions, id: \.self) { tag in
                                Button {
                                    Task {
                                        await addTag(tag)
                                    }
                                } label: {
                                    Label(tag, systemImage: "plus.circle")
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(tagAction != nil)
                                .accessibilityLabel("Add suggested tag \(tag)")
                            }
                        }
                    }
                }

                if isLoadingTags || isLoadingSuggestions {
                    Label {
                        Text(isLoadingTags ? "Loading tags…" : "Loading suggestions…")
                    } icon: {
                        ProgressView()
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(isLoadingTags ? "Loading tags" : "Loading suggestions")
                }
            }
        }
    }

    private var pendingSuggestions: [String] {
        suggestions.filter { !photoTags.contains($0) }
    }

    private var newTagField: some View {
        TextField("Add tag", text: $newTag)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onSubmit { submitNewTag() }
            .accessibilityLabel("New tag")
    }

    private var addTagButton: some View {
        Button {
            submitNewTag()
        } label: {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(newTag.trimmed.isEmpty || tagAction != nil)
        .accessibilityLabel("Add tag")
    }

    // MARK: - Data

    private func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }
        do {
            photoTags = try await fetchTags()
        } catch {
            showError("Could not load tags: \(error.localizedDescription)")
        }
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        do {
            let resp = try await APIClient.shared.tagSuggestions(photo.id)
            suggestions = resp.suggestions
        } catch {
            showError("Could not load suggestions: \(error.localizedDescription)")
        }
    }

    private func submitNewTag() {
        let tag = newTag.trimmed
        guard !tag.isEmpty else { return }
        Task {
            await addTag(tag)
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
            showSuccess("Added tag \"\(tag)\"")
        } catch {
            showError("Could not add \"\(tag)\": \(error.localizedDescription)")
        }
    }

    private func removeTag(_ tag: String) async {
        tagAction = .removing(tag)
        defer { tagAction = nil }
        do {
            try await APIClient.shared.removeTag(photo.id, tag: tag)
            photoTags.removeAll { $0 == tag }
            showSuccess("Removed tag \"\(tag)\"")
        } catch {
            showError("Could not remove \"\(tag)\": \(error.localizedDescription)")
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
                showError("Auto-tag completed, but tags could not refresh: \(error.localizedDescription)")
                return
            }
            let added = response.tagsAdded?.count ?? 0
            showSuccess(added == 0 ? "No new EXIF tags found" : "Added \(added) EXIF tag\(added == 1 ? "" : "s")")
        } catch {
            showError("Auto-tag failed: \(error.localizedDescription)")
        }
    }

    private func saveJPEG() async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.downloadJPEGData(photo.id)
            guard let image = UIImage(data: data) else {
                showError("Could not read image"); return
            }
            imageSaver.save(image) { error in
                let message = error == nil ? "Saved to Photos" : "Save failed: \(error!.localizedDescription)"
                Task { @MainActor in
                    if error == nil {
                        showSuccess(message)
                    } else {
                        showError(message)
                    }
                }
            }
        } catch {
            showError("Download failed: \(error.localizedDescription)")
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
            showSuccess("RAW original ready to share")
        } catch {
            showError("RAW export failed: \(error.localizedDescription)")
        }
    }

    private func showSuccess(_ message: String) {
        status = PhotoDetailStatus(kind: .success, message: message)
    }

    private func showError(_ message: String) {
        status = PhotoDetailStatus(kind: .error, message: message)
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

private struct PhotoDetailImage: View {
    let url: URL
    let accessibilityLabel: String
    @ScaledMetric(relativeTo: .body) private var imageHeight: CGFloat = 320

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black)

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                        Text("Unable to load preview")
                            .font(.callout)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(max(imageHeight, 260), 440))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PhotoDetailPanel<Content: View>: View {
    let header: String?
    let content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct PhotoDetailActionRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                if isWorking {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private struct PhotoDetailInfoRow: View {
    let systemImage: String
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    titleLabel
                    valueLabel
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    titleLabel
                    valueLabel
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private var titleLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 24)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
        }
    }

    private var valueLabel: some View {
        Text(value)
            .font(.body)
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PhotoDetailSeparator: View {
    var body: some View {
        Divider()
            .padding(.leading, 40)
    }
}

private struct PhotoDetailEmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundColor(.secondary)
            .padding(.vertical, 6)
            .accessibilityLabel(text)
    }
}

private struct PhotoDetailStatus: Equatable {
    let id = UUID()
    let kind: PhotoDetailStatusKind
    let message: String
}

private enum PhotoDetailStatusKind {
    case success
    case error
    case progress

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .progress: return "arrow.down.circle"
        }
    }

    var tint: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .progress: return .accentColor
        }
    }
}

private struct PhotoDetailStatusBanner: View {
    let kind: PhotoDetailStatusKind
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            if kind == .progress {
                ProgressView()
            } else {
                Image(systemName: kind.systemImage)
                    .foregroundColor(kind.tint)
            }

            Text(message)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(kind.tint.opacity(0.35), lineWidth: 1)
        )
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
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

private extension Photo {
    var fileExtension: String {
        URL(fileURLWithPath: filename).pathExtension.lowercased()
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
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
