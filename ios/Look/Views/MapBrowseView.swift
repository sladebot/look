import SwiftUI
import MapKit

/// Map of geotagged photos. Plots photos that carry GPS EXIF and lets the user
/// pull "nearby" photos around the current map center via /api/photos/nearby.
struct MapBrowseView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var center = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var selected: Photo?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var geotagged: [Photo] {
        photos.filter { $0.hasLocation }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { _ in
                Map(position: $position) {
                    ForEach(geotagged) { photo in
                        if let lat = photo.latitude, let lon = photo.longitude {
                            Annotation(photo.filename,
                                       coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                PhotoMapCallout(photo: photo) {
                                    selected = photo
                                }
                            }
                        }
                    }
                }
                .onMapCameraChange { ctx in
                    center = ctx.region.center
                }
            }

            VStack(spacing: 8) {
                if let errorMessage {
                    VStack(spacing: 8) {
                        Label("Map search failed", systemImage: "exclamationmark.triangle")
                            .font(.caption.bold())
                        Text(errorMessage)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadNearby() }
                        }
                        .font(.caption)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }
                if isLoading { ProgressView().padding(.bottom, 2) }
                Button {
                    Task { await loadNearby() }
                } label: {
                    Label("Search this area", systemImage: "location.magnifyingglass")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(isLoading)
                Text("\(geotagged.count) geotagged photos")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .overlay {
            if isLoading && !hasLoaded {
                ProgressView("Loading map photos")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if hasLoaded && geotagged.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Label("No geotagged photos", systemImage: "map")
                } description: {
                    Text("Search this area or sync photos that include GPS metadata.")
                } actions: {
                    Button("Search this area") {
                        Task { await loadNearby() }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialPhotos()
        }
        .refreshable { await loadNearby() }
        .sheet(item: $selected) { PhotoDetail(photo: $0) }
    }

    private func loadInitialPhotos() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        if store.photos.isEmpty {
            await store.loadPhotos(reset: true)
        }
        photos = store.photos
        if let storeError = store.errorMessage, photos.isEmpty {
            errorMessage = storeError
        }
        focusFirstGeotaggedPhoto()
    }

    private func loadNearby() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.nearbyPhotos(
                lat: center.latitude, lon: center.longitude, radiusKm: 50)
            // Merge with any already-loaded geotagged photos (dedup by id).
            var seen = Set(photos.map(\.id))
            for p in resp.photos where !seen.contains(p.id) {
                photos.append(p); seen.insert(p.id)
            }
            hasLoaded = true
            focusFirstGeotaggedPhoto()
        } catch {
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    private func focusFirstGeotaggedPhoto() {
        guard let first = geotagged.first, let lat = first.latitude, let lon = first.longitude else {
            return
        }
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)))
    }
}

private struct PhotoMapCallout: View {
    let photo: Photo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 128), maxPixel: 128)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white, lineWidth: 2)
                    }
                    .shadow(radius: 3)
                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(photo.filename)")
    }
}
