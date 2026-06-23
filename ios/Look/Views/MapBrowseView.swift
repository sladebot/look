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
                                Button { selected = photo } label: {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.red)
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
                if isLoading { ProgressView() }
                Button {
                    Task { await loadNearby() }
                } label: {
                    Label("Search this area", systemImage: "location.magnifyingglass")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Text("\(geotagged.count) geotagged photos")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if photos.isEmpty { photos = store.photos }
            if let first = geotagged.first, let lat = first.latitude, let lon = first.longitude {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)))
            }
        }
        .sheet(item: $selected) { PhotoDetail(photo: $0) }
    }

    private func loadNearby() async {
        isLoading = true
        defer { isLoading = false }
        if let resp = try? await APIClient.shared.nearbyPhotos(
            lat: center.latitude, lon: center.longitude, radiusKm: 50) {
            // Merge with any already-loaded geotagged photos (dedup by id).
            var seen = Set(photos.map(\.id))
            for p in resp.photos where !seen.contains(p.id) {
                photos.append(p); seen.insert(p.id)
            }
        }
    }
}
