import SwiftUI

struct FullScreenImage: View {
    let photo: Photo
    /// Single tap (disambiguated from the double-tap zoom) — used to toggle chrome.
    var onTap: () -> Void = {}
    /// Swipe down at fit scale.
    var onDismiss: () -> Void = {}
    /// Swipe up at fit scale.
    var onInfo: () -> Void = {}

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    private let dismissThreshold: CGFloat = 110

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: APIClient.shared.fullImageURL(for: photo.id)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragOffset.width,
                                y: offset.height + dragOffset.height)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        scale = min(max(scale * delta, 0.5), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        if scale < 1.0 {
                                            withAnimation { scale = 1.0; offset = .zero }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1.0 {
                                            // Pan the zoomed image.
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        } else {
                                            // Track a vertical swipe for dismiss / info.
                                            dragOffset = CGSize(width: 0, height: value.translation.height)
                                        }
                                    }
                                    .onEnded { value in
                                        if scale > 1.0 {
                                            lastOffset = offset
                                            return
                                        }
                                        let dy = value.translation.height
                                        if dy > dismissThreshold {
                                            onDismiss()
                                        } else if dy < -dismissThreshold {
                                            onInfo()
                                        }
                                        withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0; offset = .zero; lastOffset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                        .onTapGesture(count: 1) { onTap() }
                case .failure:
                    VStack {
                        Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                        Text("Failed to load image").font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.black)
    }
}
