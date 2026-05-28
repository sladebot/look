import SwiftUI

struct AlbumsList: View {
    @EnvironmentObject var store: PhotoStore

    var body: some View {
        NavigationStack {
            Group {
                if store.albums.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack").font(.largeTitle).foregroundColor(.secondary)
                        Text("No albums").font(.headline)
                        Text("Create albums on the Look server").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    List(store.albums) { album in
                        NavigationLink(destination: AlbumDetail(album: album)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(album.name).font(.body)
                                if let desc = album.description, !desc.isEmpty {
                                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                if let count = album.photoCount {
                                    Text("\(count) photos").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Albums")
            .task { await store.loadAlbums() }
            .refreshable { await store.loadAlbums() }
        }
    }
}
