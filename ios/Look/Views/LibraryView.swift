import SwiftUI

/// "Collections" tab: manual albums and smart albums. (Places moved to Find.)
struct LibraryView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var showCreateAlbum = false
    @State private var showCreateSmart = false
    @State private var pendingDeletion: LibraryDeletion?
    @State private var albumBeingEdited: Album?
    @State private var actionMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    if let message = actionMessage ?? store.errorMessage {
                        LookStatusBanner(
                            title: "Library update failed",
                            message: message,
                            tone: .error,
                            actionTitle: "Retry",
                            action: { Task { await reloadLibrary() } }
                        )
                    }

                    LibraryCollectionSection(
                        title: "Albums",
                        subtitle: "Hand-picked sets from your archive",
                        count: store.albums.count
                    ) {
                        if store.albums.isEmpty {
                            LibraryEmptyPanel(
                                title: "No albums yet",
                                message: "Create albums to collect hand-picked sets of photos.",
                                systemImage: "rectangle.stack"
                            )
                        } else {
                            LazyVGrid(columns: collectionColumns, spacing: LookTheme.Spacing.medium) {
                                ForEach(store.albums) { album in
                                    NavigationLink(destination: AlbumDetail(album: album)) {
                                        LibraryCollectionCard(
                                            title: album.name,
                                            subtitle: album.description?.nilIfBlank ?? "Manual album",
                                            count: album.photoCount,
                                            kind: .album,
                                            coverPhotoId: album.coverPhotoId ?? album.photos?.first?.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            albumBeingEdited = album
                                        } label: {
                                            Label("Rename Album", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            pendingDeletion = .albums([album])
                                        } label: {
                                            Label("Delete Album", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    LibraryCollectionSection(
                        title: "Smart Albums",
                        subtitle: "Collections that update from saved rules",
                        count: store.smartCollections.count
                    ) {
                        if store.smartCollections.isEmpty {
                            LibraryEmptyPanel(
                                title: "No smart albums yet",
                                message: "Build rules that keep matching photos grouped automatically.",
                                systemImage: "sparkles.rectangle.stack"
                            )
                        } else {
                            LazyVGrid(columns: collectionColumns, spacing: LookTheme.Spacing.medium) {
                                ForEach(store.smartCollections) { collection in
                                    NavigationLink(destination: SmartAlbumDetail(collection: collection)) {
                                        SmartCollectionCard(collection: collection)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            pendingDeletion = .smartCollections([collection])
                                        } label: {
                                            Label("Delete Smart Album", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LookNavTitle(
                        title: "Collections",
                        subtitle: "\(store.albums.count) albums • \(store.smartCollections.count) smart"
                    )
                }
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
                            .font(.title3.weight(.semibold))
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
            .sheet(item: $albumBeingEdited) { album in
                EditAlbumSheet(album: album) { _ in
                    await store.loadAlbums()
                }
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

    private var collectionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: LookTheme.Spacing.medium)]
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

private struct LibraryCollectionSection<Content: View>: View {
    let title: String
    let subtitle: String
    let count: Int
    let content: Content

    init(title: String, subtitle: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    LookTheme.sectionHeader(title)
                    Text(subtitle)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                }
                Spacer()
                Text(count.formatted())
                    .font(LookTheme.Typography.captionEmphasis)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LookTheme.ColorToken.surface, in: Capsule())
            }
            content
        }
    }
}

private enum LibraryCollectionKind {
    case album, smart

    var title: String { self == .smart ? "Smart album" : "Album" }
    var icon: String { self == .smart ? "sparkles.rectangle.stack.fill" : "rectangle.stack.fill" }
    var tint: Color { self == .smart ? LookTheme.ColorToken.accent : LookTheme.ColorToken.primaryText }
}

/// The smart-collection list response contains rules but not membership. Load
/// the lightweight detail once so its destination card can show a real cover
/// and count instead of presenting like a settings row.
private struct SmartCollectionCard: View {
    let collection: SmartCollection
    @State private var photos: [Photo]

    init(collection: SmartCollection) {
        self.collection = collection
        _photos = State(initialValue: collection.photos ?? [])
    }

    var body: some View {
        LibraryCollectionCard(
            title: collection.name,
            subtitle: collection.description?.nilIfBlank ?? "Updates automatically from a saved rule",
            count: photos.isEmpty && collection.photos == nil ? nil : photos.count,
            kind: .smart,
            coverPhotoId: photos.first?.id
        )
        .task(id: collection.id) {
            guard collection.photos == nil else { return }
            if let detail = try? await APIClient.shared.smartCollectionDetail(collection.id) {
                photos = detail.photos ?? []
            }
        }
    }
}

private struct LibraryCollectionCard: View {
    let title: String
    let subtitle: String
    let count: Int?
    let kind: LibraryCollectionKind
    var coverPhotoId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let coverPhotoId {
                CachedThumbnail(url: APIClient.shared.thumbnailURL(for: coverPhotoId, size: 512), maxPixel: 512)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fill)
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [kind.tint.opacity(0.18), LookTheme.ColorToken.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: kind.icon)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(kind.tint.opacity(0.82))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 10, contentMode: .fit)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: LookTheme.Spacing.tight) {
                    Text(title)
                        .font(LookTheme.Typography.bodyEmphasis)
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if kind == .smart {
                        Label("Smart", systemImage: "sparkles")
                            .font(LookTheme.Typography.captionEmphasis)
                            .foregroundStyle(kind.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(kind.tint.opacity(0.12), in: Capsule())
                    }
                }
                Text(metadataLine)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .lineLimit(2)
            }
            .padding(LookTheme.Spacing.medium)
        }
        .lookSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(kind.title), \(metadataLine)")
        .accessibilityHint("Opens this collection")
    }

    private var metadataLine: String {
        let countText = count.map { $0 == 1 ? "1 photo" : "\($0) photos" }
        return [countText, subtitle].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct LibraryEmptyPanel: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: LookTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LookTheme.Typography.secondaryEmphasis)
                Text(message)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }
            Spacer()
        }
        .padding(LookTheme.Spacing.medium)
        .lookSurface()
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @Namespace private var viewerZoomNamespace

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 4)]

    var body: some View {
        Group {
            if isLoading {
                LookLoadingState(title: "Loading smart album", message: collection.name)
            } else if let errorMessage {
                VStack(spacing: LookTheme.Spacing.medium) {
                    LookStatusBanner(
                        title: "Could not load smart album",
                        message: errorMessage,
                        tone: .error,
                        actionTitle: "Retry",
                        action: { Task { await load() } }
                    )
                    Spacer(minLength: 0)
                }
                .padding(LookTheme.Spacing.screen)
            } else if photos.isEmpty {
                LookEmptyState(
                    title: "No matching photos",
                    systemImage: "sparkles",
                    message: "This smart album's rules did not match anything yet.",
                    actionTitle: "Evaluate Again",
                    action: {
                        Task {
                            await evaluate()
                            await load()
                        }
                    }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                        HStack {
                            LookChip(title: photos.count == 1 ? "1 photo" : "\(photos.count) photos", systemImage: "photo", tint: LookTheme.ColorToken.accent)
                            Spacer()
                        }
                        .padding(.horizontal, LookTheme.Spacing.tight)

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                PhotoCard(photo: photo)
                                    .modifier(LookZoomSource(id: photo.id, namespace: viewerZoomNamespace))
                                    .onTapGesture { selected = photo }
                            }
                        }
                    }
                    .padding(.horizontal, LookTheme.Spacing.small)
                    .padding(.bottom, LookTheme.Spacing.large)
                }
                .refreshable { await load() }
            }
        }
        .lookScreenBackground()
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
                .modifier(LookZoomTransition(id: photo.id, namespace: viewerZoomNamespace))
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

/// Rename an album (and optionally its description) via PUT /api/albums/{id}.
struct EditAlbumSheet: View {
    let album: Album
    let currentName: String
    let onSaved: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var descriptionText: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(album: Album, currentName: String? = nil, onSaved: @escaping (String) async -> Void) {
        self.album = album
        self.currentName = currentName ?? album.name
        self.onSaved = onSaved
        _name = State(initialValue: currentName ?? album.name)
        _descriptionText = State(initialValue: album.description ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $descriptionText)
                }
                if let errorMessage {
                    Section {
                        LookStatusBanner(title: "Could not save album", message: errorMessage, tone: .error)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Rename Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(trimmedName.isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            _ = try await APIClient.shared.updateAlbum(
                album.id,
                name: trimmedName,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await onSaved(trimmedName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
                        .font(LookTheme.Typography.caption)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
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
