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

    private let nearbyRadiusKm = 50.0

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
                    LookStatusBanner(
                        title: "Map search failed",
                        message: errorMessage,
                        tone: .error,
                        actionTitle: "Retry"
                    ) {
                        Task { await loadNearby() }
                    }
                    .padding(.horizontal)
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(hasLoaded ? "Searching area" : "Loading map photos")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Button {
                    Task { await loadNearby() }
                } label: {
                    Label("Search this area", systemImage: "location.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(isLoading)

                LookChip(
                    title: "\(geotagged.count) geotagged photo\(geotagged.count == 1 ? "" : "s")",
                    systemImage: "mappin.and.ellipse",
                    tint: LookTheme.ColorToken.graphite
                )
                    .padding(.bottom, 8)
            }
        }
        .overlay {
            if isLoading && !hasLoaded {
                LookLoadingState(title: "Loading map photos", message: "Finding photos with GPS metadata.")
                    .background(.ultraThinMaterial)
            } else if hasLoaded && geotagged.isEmpty && errorMessage == nil {
                LookEmptyState(
                    title: "No geotagged photos",
                    systemImage: "map",
                    message: "Search this area or sync photos that include GPS metadata.",
                    actionTitle: "Search This Area"
                ) {
                    Task { await loadNearby() }
                }
                .background(.ultraThinMaterial)
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
                lat: center.latitude, lon: center.longitude, radiusKm: nearbyRadiusKm)
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
            VStack(spacing: 5) {
                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: photo.id, size: 128), maxPixel: 128)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous)
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white, LookTheme.ColorToken.danger)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(x: 5, y: 5)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 5, y: 3)

                Text(photo.filename)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 96)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(photo.filename)")
    }
}
