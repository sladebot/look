import SwiftUI

struct SmartAlbumsList: View {
    @EnvironmentObject var store: PhotoStore
    @State private var selectedCollection: SmartCollection?
    @State private var collectionPhotos: [Photo] = []
    @State private var loadingCollectionID: String?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    if let message = errorMessage ?? store.errorMessage {
                        LookStatusBanner(
                            title: "Could not load smart albums",
                            message: message,
                            tone: .error,
                            actionTitle: "Retry",
                            action: { Task { await store.loadSmartCollections() } }
                        )
                    }

                    if store.smartCollections.isEmpty {
                        LookEmptyState(
                            title: "No smart albums",
                            systemImage: "sparkles.rectangle.stack",
                            message: "Create smart albums on the Look server to group photos by saved rules."
                        )
                        .lookPanel(inset: 0)
                        .frame(minHeight: 320)
                    } else {
                        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                            LookTheme.eyebrow("\(store.smartCollections.count) Smart Albums")
                            ForEach(store.smartCollections) { collection in
                                Button(action: { Task { await loadCollectionPhotos(collection) } }) {
                                    SmartAlbumListRow(
                                        collection: collection,
                                        isLoading: loadingCollectionID == collection.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(loadingCollectionID != nil)
                            }
                        }
                    }
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
            .navigationTitle("Smart Albums")
            .task { await store.loadSmartCollections() }
            .refreshable { await store.loadSmartCollections() }
            .sheet(item: $selectedCollection) { collection in
                NavigationStack {
                    ScrollView {
                        if collectionPhotos.isEmpty {
                            LookEmptyState(
                                title: "No matching photos",
                                systemImage: "sparkles",
                                message: "This smart album's rules did not match anything yet."
                            )
                        } else {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(collectionPhotos) { photo in
                                    NavigationLink(destination: PhotoDetail(photo: photo)) {
                                        PhotoCard(photo: photo)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(LookTheme.Spacing.small)
                        }
                    }
                    .lookScreenBackground()
                    .navigationTitle(collection.name)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { selectedCollection = nil }
                        }
                    }
                }
            }
        }
    }

    private func loadCollectionPhotos(_ collection: SmartCollection) async {
        loadingCollectionID = collection.id
        errorMessage = nil
        defer { loadingCollectionID = nil }
        do {
            let detail = try await APIClient.shared.smartCollectionDetail(collection.id)
            collectionPhotos = detail.photos ?? []
            selectedCollection = collection
        } catch {
            collectionPhotos = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct SmartAlbumListRow: View {
    let collection: SmartCollection
    let isLoading: Bool

    private var subtitle: String {
        if let description = collection.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        return "Rule-based collection."
    }

    var body: some View {
        HStack(spacing: LookTheme.Spacing.medium) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LookTheme.ColorToken.amber)
                .frame(width: 42, height: 42)
                .background(LookTheme.ColorToken.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: LookTheme.Spacing.tight)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Smart")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LookTheme.ColorToken.amber.opacity(0.12), in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(LookTheme.Spacing.medium)
        .lookInsetSurface()
        .lookFilmRail(color: LookTheme.ColorToken.amber)
        .accessibilityElement(children: .combine)
    }
}
