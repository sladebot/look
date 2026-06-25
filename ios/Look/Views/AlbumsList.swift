import SwiftUI

struct AlbumsList: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    if let message = store.errorMessage {
                        LookStatusBanner(
                            title: "Could not load albums",
                            message: message,
                            tone: .error,
                            actionTitle: "Retry",
                            action: { Task { await store.loadAlbums() } }
                        )
                    }

                    if store.albums.isEmpty {
                        LookEmptyState(
                            title: "No albums",
                            systemImage: "rectangle.stack",
                            message: "Create albums to collect hand-picked sets of photos."
                        )
                        .lookPanel(inset: 0)
                        .frame(minHeight: 320)
                    } else {
                        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                            LookTheme.eyebrow("\(store.albums.count) Albums")
                            ForEach(store.albums) { album in
                                NavigationLink(destination: AlbumDetail(album: album)) {
                                    AlbumListRow(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
            .navigationTitle("Albums")
            .task { await store.loadAlbums() }
            .refreshable { await store.loadAlbums() }
        }
    }
}

private struct AlbumListRow: View {
    let album: Album

    private var subtitle: String {
        if let description = album.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        return "Manual photo collection."
    }

    private var countText: String? {
        guard let count = album.photoCount else { return nil }
        return count == 1 ? "1 photo" : "\(count) photos"
    }

    var body: some View {
        HStack(spacing: LookTheme.Spacing.medium) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LookTheme.ColorToken.graphite)
                .frame(width: 42, height: 42)
                .background(LookTheme.ColorToken.graphite.opacity(0.12), in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: LookTheme.Spacing.tight)

            if let countText {
                Text(countText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LookTheme.ColorToken.graphite.opacity(0.10), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(LookTheme.Spacing.medium)
        .lookInsetSurface()
        .lookFilmRail(color: LookTheme.ColorToken.graphite)
        .accessibilityElement(children: .combine)
    }
}
