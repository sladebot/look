import SwiftUI

struct PhotosGrid: View {
    @EnvironmentObject var store: PhotoStore
    @State private var selectedPhoto: Photo?

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.photos.isEmpty {
                    VStack {
                        ProgressView()
                        Text("Loading photos...").font(.caption).foregroundColor(.secondary)
                    }
                } else if !store.serverConnected {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash").font(.largeTitle).foregroundColor(.secondary)
                        Text("Cannot connect to Look server")
                            .font(.headline)
                        Text("Check server URL in Settings")
                            .font(.caption).foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await store.checkConnection() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if store.photos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundColor(.secondary)
                        Text("No photos found")
                            .font(.headline)
                        Text("Import photos on the Look server first")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.photos) { photo in
                                PhotoCard(photo: photo)
                                    .onAppear { store.loadMoreIfNeeded(currentPhoto: photo) }
                                    .onTapGesture { selectedPhoto = photo }
                            }
                        }
                        .padding(2)

                        if store.isLoading {
                            ProgressView().padding()
                        }
                    }
                    .refreshable {
                        await store.syncNow()
                    }
                }
            }
            .navigationTitle("Look")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.syncNow() }
                    } label: {
                        if store.isSyncing {
                            ProgressView()
                        } else {
                            Label("Sync & Import", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(store.isSyncing)
                    .accessibilityLabel("Sync and import photos")
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetail(photo: photo)
            }
        }
    }
}
