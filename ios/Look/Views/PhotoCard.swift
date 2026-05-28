import SwiftUI

struct PhotoCard: View {
    let photo: Photo

    var body: some View {
        AsyncImage(url: APIClient.shared.thumbnailURL(for: photo.id, size: 256)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            case .failure:
                Color.gray.opacity(0.2)
                    .overlay(Image(systemName: "photo.badge.exclamationmark").foregroundColor(.gray))
            case .empty:
                Color.gray.opacity(0.1)
                    .overlay(ProgressView())
            @unknown default:
                Color.gray.opacity(0.1)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .cornerRadius(8)
    }
}
