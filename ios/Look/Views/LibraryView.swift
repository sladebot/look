import SwiftUI

/// Combined "Library" tab: manual albums, smart albums, and a map entry.
/// This is also where Smart Albums are finally surfaced in the UI.
struct LibraryView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var showCreateAlbum = false
    @State private var showCreateSmart = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MapBrowseView()
                    } label: {
                        Label("Map", systemImage: "map")
                    }
                }

                Section("Albums") {
                    if store.albums.isEmpty {
                        Text("No albums yet").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(store.albums) { album in
                        NavigationLink(destination: AlbumDetail(album: album)) {
                            HStack {
                                Image(systemName: "rectangle.stack")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(album.name)
                                    if let count = album.photoCount {
                                        Text("\(count) photos")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { store.albums[$0].id }
                        Task { for id in ids { await store.deleteAlbum(id) } }
                    }
                }

                Section("Smart Albums") {
                    if store.smartCollections.isEmpty {
                        Text("No smart albums yet").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(store.smartCollections) { collection in
                        NavigationLink(destination: SmartAlbumDetail(collection: collection)) {
                            HStack {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading) {
                                    Text(collection.name)
                                    if let desc = collection.description, !desc.isEmpty {
                                        Text(desc).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { store.smartCollections[$0].id }
                        Task { for id in ids { await store.deleteSmartCollection(id) } }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCreateAlbum = true } label: {
                            Label("New Album", systemImage: "rectangle.stack.badge.plus")
                        }
                        Button { showCreateSmart = true } label: {
                            Label("New Smart Album", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await store.loadAlbums()
                await store.loadSmartCollections()
            }
            .refreshable {
                await store.loadAlbums()
                await store.loadSmartCollections()
            }
            .sheet(isPresented: $showCreateAlbum) {
                CreateAlbumSheet()
            }
            .sheet(isPresented: $showCreateSmart) {
                CreateSmartAlbumSheet()
            }
        }
    }
}

// MARK: - Smart album detail (grid of matched photos)

struct SmartAlbumDetail: View {
    let collection: SmartCollection
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var selected: Photo?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if photos.isEmpty {
                ContentUnavailableView("No matching photos", systemImage: "sparkles",
                                       description: Text("This smart album's rules matched nothing."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            PhotoCard(photo: photo).onTapGesture { selected = photo }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        _ = try? await APIClient.shared.evalSmartCollection(collection.id)
                        await load()
                    }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let detail = try? await APIClient.shared.smartCollectionDetail(collection.id) {
            photos = detail.photos ?? []
        }
    }
}

// MARK: - Create sheets

struct CreateAlbumSheet: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saving = true
                        Task {
                            await store.createAlbum(name: name.trimmingCharacters(in: .whitespaces),
                                                    description: description)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }
}

struct CreateSmartAlbumSheet: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var field = "camera"
    @State private var op = "contains"
    @State private var value = ""
    @State private var saving = false

    private let fields = ["camera", "tag", "keyword", "is_favorite"]
    private let ops = ["contains", "equals", "has", "has_any", "regex"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Smart Album") {
                    TextField("Name", text: $name)
                }
                Section("Rule") {
                    Picker("Field", selection: $field) {
                        ForEach(fields, id: \.self) { Text($0) }
                    }
                    Picker("Operator", selection: $op) {
                        ForEach(ops, id: \.self) { Text($0) }
                    }
                    TextField("Value (e.g. Canon)", text: $value)
                }
                Section {
                    Text("Photos matching this rule are added automatically.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Smart Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saving = true
                        let rule = "{\"rules\":[{\"field\":\"\(field)\",\"op\":\"\(op)\",\"value\":\"\(value)\"}]}"
                        Task {
                            await store.createSmartCollection(
                                name: name.trimmingCharacters(in: .whitespaces),
                                description: "", ruleSpec: rule)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }
}
