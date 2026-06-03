import SwiftUI

struct PhotoDetail: View {
    let photo: Photo
    @EnvironmentObject var store: PhotoStore
    @State private var photoTags: [String] = []
    @State private var newTag = ""
    @State private var showFullScreen = false
    @State private var isAutoTagging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Thumbnail tappable for full-screen
                    AsyncImage(url: APIClient.shared.thumbnailURL(for: photo.id, size: 512)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                                .cornerRadius(12)
                                .onTapGesture { showFullScreen = true }
                        case .failure:
                            Color.gray.opacity(0.2).frame(height: 300)
                                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray))
                        case .empty:
                            Color.gray.opacity(0.1).frame(height: 300)
                                .overlay(ProgressView())
                        @unknown default:
                            Color.gray.opacity(0.1).frame(height: 300)
                        }
                    }
                    .padding(.horizontal)

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text(photo.filename).font(.title2).fontWeight(.bold)
                        if let date = photo.createdAt {
                            Label(date, systemImage: "calendar").font(.caption).foregroundColor(.secondary)
                        }
                        if let w = photo.width, let h = photo.height {
                            Label("\(w) × \(h)", systemImage: "viewfinder").font(.caption).foregroundColor(.secondary)
                        }
                        if let make = photo.exif?.make, let model = photo.exif?.model {
                            Label("\(make) \(model)", systemImage: "camera").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    Divider()

                    // Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags").font(.headline)

                        // Add tag
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

                        // Auto-tag
                        Button(action: {
                            isAutoTagging = true
                            Task {
                                _ = try? await APIClient.shared.autoTag(photo.id)
                                await loadTags()
                                isAutoTagging = false
                            }
                        }) {
                            HStack {
                                if isAutoTagging { ProgressView().scaleEffect(0.7) }
                                Text("Auto-tag from EXIF")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAutoTagging)

                        // Tag pills
                        if photoTags.isEmpty {
                            Text("No tags").font(.caption).foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(photoTags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag).font(.caption)
                                        Button(action: {
                                            Task {
                                                _ = try? await APIClient.shared.removeTag(photo.id, tag: tag)
                                                await loadTags()
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill").font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showFullScreen) {
                FullScreenImage(photo: photo)
            }
            .task { await loadTags() }
        }
    }

    private func loadTags() async {
        if let response = try? await APIClient.shared.photoTags(photo.id) {
            photoTags = response.tags ?? []
        }
    }
}

// Simple flow layout for tag pills
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.flatMap { $0 }.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            if let frame = findFrame(for: index, in: rows) {
                subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
            }
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [[CGRect]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGRect]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            let frame = CGRect(x: x, y: 0, width: size.width, height: size.height)
            rows[rows.count - 1].append(frame)
            x += size.width + spacing
        }
        var y: CGFloat = 0
        for i in rows.indices {
            let rowHeight = rows[i].map(\.height).max() ?? 0
            for j in rows[i].indices {
                rows[i][j].origin.y = y
            }
            y += rowHeight + spacing
        }
        return rows
    }

    private func findFrame(for index: Int, in rows: [[CGRect]]) -> CGRect? {
        var count = 0
        for row in rows {
            if index < count + row.count {
                return row[index - count]
            }
            count += row.count
        }
        return nil
    }
}
