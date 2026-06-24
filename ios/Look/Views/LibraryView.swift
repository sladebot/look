import SwiftUI

/// Combined "Library" tab: manual albums, smart albums, and a map entry.
/// This is also where Smart Albums are finally surfaced in the UI.
struct LibraryView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var showCreateAlbum = false
    @State private var showCreateSmart = false
    @State private var pendingDeletion: LibraryDeletion?
    @State private var actionMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let message = actionMessage ?? store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task { await reloadLibrary() }
                        }
                        .font(.caption)
                    }
                }

                Section("Browse") {
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
                        let albums = indexSet.map { store.albums[$0] }
                        pendingDeletion = .albums(albums)
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
                        let collections = indexSet.map { store.smartCollections[$0] }
                        pendingDeletion = .smartCollections(collections)
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
                await reloadLibrary()
            }
            .refreshable {
                await reloadLibrary()
            }
            .sheet(isPresented: $showCreateAlbum) {
                CreateAlbumSheet()
            }
            .sheet(isPresented: $showCreateSmart) {
                CreateSmartAlbumSheet()
            }
            .alert(item: $pendingDeletion) { deletion in
                Alert(
                    title: Text(deletion.title),
                    message: Text(deletion.message),
                    primaryButton: .destructive(Text("Delete")) {
                        Task { await delete(deletion) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func reloadLibrary() async {
        actionMessage = nil
        await store.loadAlbums()
        await store.loadSmartCollections()
    }

    private func delete(_ deletion: LibraryDeletion) async {
        actionMessage = nil
        do {
            switch deletion {
            case .albums(let albums):
                for album in albums {
                    _ = try await APIClient.shared.deleteAlbum(album.id)
                }
                await store.loadAlbums()
            case .smartCollections(let collections):
                for collection in collections {
                    _ = try await APIClient.shared.deleteSmartCollection(collection.id)
                }
                await store.loadSmartCollections()
            }
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private enum LibraryDeletion: Identifiable {
    case albums([Album])
    case smartCollections([SmartCollection])

    var id: String {
        switch self {
        case .albums(let albums): return "albums-\(albums.map(\.id).joined(separator: ","))"
        case .smartCollections(let collections): return "smart-\(collections.map(\.id).joined(separator: ","))"
        }
    }

    var title: String {
        switch self {
        case .albums(let albums): return albums.count == 1 ? "Delete Album?" : "Delete Albums?"
        case .smartCollections(let collections): return collections.count == 1 ? "Delete Smart Album?" : "Delete Smart Albums?"
        }
    }

    var message: String {
        switch self {
        case .albums(let albums):
            return albums.count == 1
                ? "This removes \"\(albums[0].name)\" from the library. Photos are not deleted."
                : "This removes \(albums.count) albums from the library. Photos are not deleted."
        case .smartCollections(let collections):
            return collections.count == 1
                ? "This removes \"\(collections[0].name)\" and its saved rules. Photos are not deleted."
                : "This removes \(collections.count) smart albums and their saved rules. Photos are not deleted."
        }
    }
}

// MARK: - Smart album detail (grid of matched photos)

struct SmartAlbumDetail: View {
    let collection: SmartCollection
    @EnvironmentObject var store: PhotoStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var isEvaluating = false
    @State private var errorMessage: String?
    @State private var selected: Photo?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Could not load smart album", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await load() }
                    }
                }
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
                        await evaluate()
                        await load()
                    }
                } label: {
                    if isEvaluating {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isEvaluating)
            }
        }
        .task { await load() }
        .fullScreenCover(item: $selected) { photo in
            NativePhotoViewer(photos: photos, initialPhoto: photo)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await APIClient.shared.smartCollectionDetail(collection.id)
            photos = detail.photos ?? []
        } catch {
            photos = []
            errorMessage = error.localizedDescription
        }
    }

    private func evaluate() async {
        isEvaluating = true
        errorMessage = nil
        defer { isEvaluating = false }
        do {
            _ = try await APIClient.shared.evalSmartCollection(collection.id)
        } catch {
            errorMessage = error.localizedDescription
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
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func create() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            _ = try await APIClient.shared.createAlbum(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await store.loadAlbums()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateSmartAlbumSheet: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var field: SmartAlbumRuleField = .camera
    @State private var op: SmartAlbumRuleOperator = .contains
    @State private var value = ""
    @State private var favoriteValue = true
    @State private var saving = false
    @State private var errorMessage: String?

    private var availableOperators: [SmartAlbumRuleOperator] {
        field.operators
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!field.requiresTextValue || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Smart Album") {
                    TextField("Name", text: $name)
                }
                Section("Rule") {
                    Picker("Field", selection: $field) {
                        ForEach(SmartAlbumRuleField.allCases) { field in
                            Text(field.title).tag(field)
                        }
                    }
                    .onChange(of: field) { _, newValue in
                        op = newValue.operators.first ?? .equals
                        value = ""
                    }
                    Picker("Operator", selection: $op) {
                        ForEach(availableOperators) { op in
                            Text(op.title).tag(op)
                        }
                    }
                    if field == .isFavorite {
                        Toggle("Favorite", isOn: $favoriteValue)
                    } else {
                        TextField(field.placeholder, text: $value)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                Section {
                    Text("Photos matching this rule are added automatically.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Smart Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func create() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let ruleSpec = try SmartAlbumRuleSpec(
                field: field,
                op: op,
                textValue: value.trimmingCharacters(in: .whitespacesAndNewlines),
                boolValue: favoriteValue
            ).encodedString()
            _ = try await APIClient.shared.createSmartCollection(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: "",
                ruleSpec: ruleSpec
            )
            await store.loadSmartCollections()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum SmartAlbumRuleField: String, CaseIterable, Identifiable {
    case camera
    case tag
    case keyword
    case isFavorite = "is_favorite"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .tag: return "Tag"
        case .keyword: return "Keyword"
        case .isFavorite: return "Favorite"
        }
    }

    var placeholder: String {
        switch self {
        case .camera: return "Camera make or model"
        case .tag: return "Tag name"
        case .keyword: return "Keyword"
        case .isFavorite: return ""
        }
    }

    var operators: [SmartAlbumRuleOperator] {
        switch self {
        case .camera: return [.contains, .equals, .regex]
        case .tag: return [.has, .hasAny, .equals]
        case .keyword: return [.contains, .equals, .regex]
        case .isFavorite: return [.equals]
        }
    }

    var requiresTextValue: Bool { self != .isFavorite }
}

private enum SmartAlbumRuleOperator: String, CaseIterable, Identifiable {
    case contains
    case equals
    case has
    case hasAny = "has_any"
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains: return "Contains"
        case .equals: return "Equals"
        case .has: return "Has"
        case .hasAny: return "Has any"
        case .regex: return "Regex"
        }
    }
}

private struct SmartAlbumRuleSpec: Encodable {
    let rules: [Rule]

    init(field: SmartAlbumRuleField, op: SmartAlbumRuleOperator, textValue: String, boolValue: Bool) {
        rules = [
            Rule(
                field: field.rawValue,
                op: op.rawValue,
                value: field == .isFavorite ? .bool(boolValue) : .string(textValue)
            )
        ]
    }

    func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SmartAlbumRuleError.encodingFailed
        }
        return string
    }

    struct Rule: Encodable {
        let field: String
        let op: String
        let value: RuleValue
    }

    enum RuleValue: Encodable {
        case string(String)
        case bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }
}

private enum SmartAlbumRuleError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "Could not encode the smart album rule."
    }
}
