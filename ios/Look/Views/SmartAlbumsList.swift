import SwiftUI

struct SmartAlbumsList: View {
    @EnvironmentObject var store: PhotoStore
    @State private var selectedCollection: SmartCollection?
    @State private var collectionPhotos: [Photo] = []

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.smartCollections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack").font(.largeTitle).foregroundColor(.secondary)
                        Text("No smart albums").font(.headline)
                        Text("Create smart albums on the Look server").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    List(store.smartCollections) { collection in
                        Button(action: { Task { await loadCollectionPhotos(collection) } }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.name).font(.body)
                                if let desc = collection.description, !desc.isEmpty {
                                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Smart Albums")
            .task { await store.loadSmartCollections() }
            .refreshable { await store.loadSmartCollections() }
            .sheet(item: $selectedCollection) { collection in
                NavigationStack {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(collectionPhotos) { photo in
                                NavigationLink(destination: PhotoDetail(photo: photo)) {
                                    PhotoCard(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                    }
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
        if let detail = try? await APIClient.shared.smartCollectionDetail(collection.id) {
            collectionPhotos = detail.photos ?? []
            selectedCollection = collection
        }
    }
}
