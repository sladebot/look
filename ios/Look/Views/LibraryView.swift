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
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    libraryHeader

                    if let message = actionMessage ?? store.errorMessage {
                        LookStatusBanner(
                            title: "Library update failed",
                            message: message,
                            tone: .error,
                            actionTitle: "Retry",
                            action: { Task { await reloadLibrary() } }
                        )
                    }

                    LibraryPanelSection(title: "Browse") {
                        NavigationLink {
                            MapBrowseView()
                        } label: {
                            LibraryCollectionRow(
                                icon: "map.fill",
                                title: "Map",
                                subtitle: "Browse photos with saved locations.",
                                badge: "Places",
                                tint: LookTheme.ColorToken.cyan
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    LibraryPanelSection(
                        title: "Albums",
                        trailing: "\(store.albums.count)"
                    ) {
                        if store.albums.isEmpty {
                            LibraryEmptyPanel(
                                title: "No albums yet",
                                message: "Create albums to collect hand-picked sets of photos.",
                                systemImage: "rectangle.stack"
                            )
                        } else {
                            VStack(spacing: LookTheme.Spacing.small) {
                                ForEach(store.albums) { album in
                                    NavigationLink(destination: AlbumDetail(album: album)) {
                                        LibraryCollectionRow(
                                            icon: "rectangle.stack.fill",
                                            title: album.name,
                                            subtitle: album.description?.nilIfBlank ?? "Manual photo collection.",
                                            badge: photoCountText(album.photoCount),
                                            tint: LookTheme.ColorToken.graphite
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
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

                    LibraryPanelSection(
                        title: "Smart Albums",
                        trailing: "\(store.smartCollections.count)"
                    ) {
                        if store.smartCollections.isEmpty {
                            LibraryEmptyPanel(
                                title: "No smart albums yet",
                                message: "Build rules that keep matching photos grouped automatically.",
                                systemImage: "sparkles.rectangle.stack"
                            )
                        } else {
                            VStack(spacing: LookTheme.Spacing.small) {
                                ForEach(store.smartCollections) { collection in
                                    NavigationLink(destination: SmartAlbumDetail(collection: collection)) {
                                        LibraryCollectionRow(
                                            icon: "sparkles.rectangle.stack.fill",
                                            title: collection.name,
                                            subtitle: collection.description?.nilIfBlank ?? "Rule-based collection.",
                                            badge: "Smart",
                                            tint: LookTheme.ColorToken.amber
                                        )
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

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    LookTheme.eyebrow("Collections")
                    Text("Organize the library")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LookTheme.ColorToken.graphite)
                }
                Spacer()
            }

            HStack(spacing: LookTheme.Spacing.small) {
                LibraryMetric(title: "Albums", value: "\(store.albums.count)", tint: LookTheme.ColorToken.graphite)
                LibraryMetric(title: "Smart", value: "\(store.smartCollections.count)", tint: LookTheme.ColorToken.amber)
            }
        }
        .lookPanel()
    }

    private func photoCountText(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? "1 photo" : "\(count) photos"
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

private struct LibraryPanelSection<Content: View>: View {
    let title: String
    var trailing: String?
    let content: Content

    init(title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack {
                LookTheme.eyebrow(title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            content
        }
    }
}

private struct LibraryCollectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String?
    let tint: Color

    var body: some View {
        HStack(spacing: LookTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: LookTheme.Spacing.tight)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.11), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(LookTheme.Spacing.medium)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.mist, lineWidth: 1)
        }
        .lookFilmRail(color: tint)
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LookTheme.Spacing.small)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
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
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(LookTheme.Spacing.medium)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                .stroke(LookTheme.ColorToken.mist, lineWidth: 1)
        }
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
                            LookChip(title: photos.count == 1 ? "1 photo" : "\(photos.count) photos", systemImage: "photo", tint: LookTheme.ColorToken.amber)
                            Spacer()
                        }
                        .padding(.horizontal, LookTheme.Spacing.tight)

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                PhotoCard(photo: photo)
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
