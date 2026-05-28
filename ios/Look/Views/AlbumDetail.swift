import SwiftUI

struct AlbumDetail: View {
    let album: Album
    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundColor(.secondary)
                    Text("No photos in this album").font(.headline)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
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
        .navigationTitle(album.name)
        .task { await loadPhotos() }
    }

    private func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }
        if let detail = try? await APIClient.shared.albumDetail(album.id) {
            photos = detail.photos ?? []
        }
    }
}
