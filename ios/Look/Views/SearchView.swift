import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var query = ""

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    TextField("Search photos...", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await store.search(query) }
                        }
                    if !query.isEmpty {
                        Button("Clear") {
                            query = ""
                            Task { await store.search("") }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if store.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if store.searchQuery.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
                        Text("Search your photo library").font(.headline)
                        Text("Search by filename, tags, or filepath").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                } else if store.photos.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
                        Text("No results for \"\(store.searchQuery)\"").font(.headline)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.photos) { photo in
                                NavigationLink(destination: PhotoDetail(photo: photo)) {
                                    PhotoCard(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .navigationTitle("Search")
        }
    }
}
