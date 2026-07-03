import SwiftUI

// MARK: - Deduplication

struct DedupView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var enabled = false
    @State private var tolerance = 20
    @State private var groups: [[DedupGroupPhoto]] = []
    @State private var status = ""
    @State private var isScanning = false
    @State private var loadedSettings = false
    @State private var pendingMerge: DedupMergeRequest?

    var body: some View {
        List {
            Section("Server Deduplication") {
                Toggle("Deduplication enabled", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        Task { await updateSettings(enabled: newValue) }
                    }
                Stepper("Tolerance: \(tolerance)", value: $tolerance, in: 0...64)
                    .onChange(of: tolerance) { _, newValue in
                        Task { await updateSettings(tolerance: newValue) }
                    }
                Text("Lower tolerance = stricter matching (Hamming distance on perceptual hash).")
                    .font(LookTheme.Typography.caption)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
            }

            if loadedSettings && !enabled {
                Section {
                    LookStatusBanner(
                        title: "Deduplication is disabled",
                        message: "Enable server deduplication before starting a scan.",
                        tone: .warning
                    )
                }
                .listRowSeparator(.hidden)
            }

            Section {
                Button {
                    Task { await scan() }
                } label: {
                    HStack {
                        if isScanning { ProgressView().scaleEffect(0.8) }
                        Text(isScanning ? "Scanning…" : "Scan for duplicates")
                    }
                }
                .disabled(isScanning || !enabled)
                if !status.isEmpty {
                    AdminStatusBanner(message: status)
                }
            }

            if loadedSettings && groups.isEmpty && !isScanning {
                Section {
                    LookEmptyState(
                        title: "No duplicate groups loaded",
                        systemImage: "square.on.square",
                        message: enabled
                            ? "Run a scan to review photos with matching perceptual hashes."
                            : "Enable deduplication to scan the library."
                    )
                    .frame(minHeight: 220)
                }
                .listRowSeparator(.hidden)
            }

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                Section("Group \(index + 1) — \(group.count) photos") {
                    ForEach(group) { photo in
                        HStack {
                            AsyncImage(url: APIClient.shared.thumbnailURL(for: photo.photoId, size: 128)) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.gray.opacity(0.1) }
                            .frame(width: 56, height: 56).clipped().cornerRadius(6)
                            Text(photo.filename ?? photo.photoId)
                                .font(LookTheme.Typography.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Keep") {
                                pendingMerge = DedupMergeRequest(
                                    groupIndex: index,
                                    keepPhotoId: photo.photoId,
                                    filename: photo.filename ?? photo.photoId
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .lookScreenBackground()
        .navigationTitle("Duplicates")
        .task {
            if !loadedSettings {
                do {
                    let s = try await APIClient.shared.dedupSettings()
                    enabled = s.dedupEnabled
                    tolerance = s.dedupTolerance
                    status = ""
                } catch {
                    status = "Could not load settings: \(error.localizedDescription)"
                }
                loadedSettings = true
            }
        }
        .alert(item: $pendingMerge) { request in
            Alert(
                title: Text("Merge Duplicate Group?"),
                message: Text("Keep \"\(request.filename)\" in the library and move every other photo in this duplicate group to the server .trash folder."),
                primaryButton: .destructive(Text("Archive Duplicates")) {
                    Task { await merge(groupIndex: request.groupIndex, keep: request.keepPhotoId) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func updateSettings(enabled: Bool? = nil, tolerance: Int? = nil) async {
        do {
            _ = try await APIClient.shared.updateDedupSettings(enabled: enabled, tolerance: tolerance)
            status = "Settings updated"
        } catch {
            status = "Settings update failed: \(error.localizedDescription)"
        }
    }

    private func scan() async {
        isScanning = true
        status = "Submitting scan…"
        defer { isScanning = false }
        let submit: TaskSubmitResponse
        do {
            submit = try await APIClient.shared.submitDedupScan()
        } catch {
            status = "Failed to start scan: \(error.localizedDescription)"
            return
        }
        guard let taskId = submit.taskId else {
            status = submit.status == "disabled" ? "Enable deduplication first" : "No task id returned"
            return
        }
        status = "Scanning…"
        // Poll task until done.
        for _ in 0..<120 {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let task = try await APIClient.shared.task(taskId)
                if ["completed", "failed", "cancelled"].contains(task.status) {
                    groups = Self.parseGroups(task.result)
                    status = task.status == "completed"
                        ? "Found \(groups.count) duplicate group(s)"
                        : "Scan \(task.status)"
                    return
                }
            } catch is CancellationError {
                status = "Scan polling cancelled"
                return
            } catch {
                status = "Waiting for scan status: \(error.localizedDescription)"
                continue
            }
        }
        status = "Scan timed out"
    }

    private func merge(groupIndex: Int, keep: String) async {
        do {
            guard groups.indices.contains(groupIndex) else {
                status = "Merge failed: duplicate group changed. Scan again."
                return
            }
            _ = try await APIClient.shared.mergeDuplicates(groupId: groupIndex, keepPhotoId: keep)
            groups.remove(at: groupIndex)
            status = "Merged group — duplicates archived to .trash/"
        } catch {
            status = "Merge failed: \(error.localizedDescription)"
        }
    }

    /// Extract `result.groups` (array of arrays of photo objects) from the task blob.
    static func parseGroups(_ result: JSONValue?) -> [[DedupGroupPhoto]] {
        guard let groupsVal = result?["groups"]?.arrayValue else { return [] }
        return groupsVal.compactMap { groupVal in
            groupVal.arrayValue?.compactMap { item -> DedupGroupPhoto? in
                guard let pid = item["photo_id"]?.stringValue else { return nil }
                return DedupGroupPhoto(photoId: pid,
                                       filename: item["filename"]?.stringValue,
                                       filepath: item["filepath"]?.stringValue,
                                       phash: item["phash"]?.stringValue)
            }
        }
    }
}

private struct DedupMergeRequest: Identifiable {
    let groupIndex: Int
    let keepPhotoId: String
    let filename: String
    var id: String { "\(groupIndex)-\(keepPhotoId)" }
}

// MARK: - Background tasks

struct TasksView: View {
    @State private var tasks: [TaskInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingCancel: TaskInfo?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    AdminStatusBanner(message: errorMessage, title: "Could not load tasks", actionTitle: "Retry") {
                        Task { await load() }
                    }
                }
                .listRowSeparator(.hidden)
            }
            if tasks.isEmpty && !isLoading {
                Section {
                    LookEmptyState(
                        title: "No background tasks",
                        systemImage: "list.bullet.rectangle",
                        message: "Scans, imports, and other server jobs will appear here."
                    )
                    .frame(minHeight: 240)
                }
                .listRowSeparator(.hidden)
            }
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.taskType ?? "task").font(LookTheme.Typography.headline)
                        Spacer()
                        LookChip(title: task.status, systemImage: statusIcon(task.status), tint: statusColor(task.status))
                    }
                    if let phase = task.progress?["phase"]?.stringValue {
                        Text("Phase: \(phase)")
                            .font(LookTheme.Typography.caption)
                            .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    }
                    if let cur = task.progress?["current"]?.intValue,
                       let total = task.progress?["total_scanned"]?.intValue, total > 0 {
                        ProgressView(value: Double(cur), total: Double(total))
                    }
                    if let created = task.createdAt {
                        Text(created)
                            .font(LookTheme.Typography.caption)
                            .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    }
                    if ["pending", "running"].contains(task.status) {
                        Button("Cancel", role: .destructive) {
                            pendingCancel = task
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .lookScreenBackground()
        .navigationTitle("Tasks")
        .overlay {
            if isLoading && tasks.isEmpty {
                LookLoadingState(title: "Loading tasks", message: "Checking the server queue.")
                    .background(LookTheme.ColorToken.paper.opacity(0.92))
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(item: $pendingCancel) { task in
            Alert(
                title: Text("Cancel Task?"),
                message: Text("Stop \(task.taskType ?? "task") \(task.taskId). Any work already completed on the server will remain."),
                primaryButton: .destructive(Text("Cancel Task")) {
                    Task { await cancel(task) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func statusColor(_ status: String) -> Color {
        status == "completed" ? .green
            : status == "failed" ? LookTheme.ColorToken.danger
            : status == "running" ? LookTheme.ColorToken.cyan : .secondary
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.octagon.fill"
        case "running": return "arrow.triangle.2.circlepath"
        case "pending": return "clock.fill"
        default: return "circle.fill"
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.tasks()
            tasks = resp.tasks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(_ task: TaskInfo) async {
        do {
            _ = try await APIClient.shared.cancelTask(task.taskId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Watch list

struct WatchListView: View {
    @State private var directories: [WatchDirectory] = []
    @State private var newPath = ""
    @State private var isLoading = true
    @State private var message: String?
    @State private var editingDirectory: WatchDirectory?
    @State private var busyPath: String?
    @State private var pendingRemoval: WatchDirectory?

    var body: some View {
        List {
            Section("Server Watch Directories") {
                HStack {
                    TextField("/path/on/server", text: $newPath)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Button("Add") { Task { await add() } }
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message {
                    AdminStatusBanner(message: message)
                }
            }
            Section("Watched directories") {
                if directories.isEmpty && !isLoading {
                    LookEmptyState(
                        title: "No watched directories",
                        systemImage: "folder.badge.plus",
                        message: "Add a server path to make it available for imports and file watching."
                    )
                    .frame(minHeight: 220)
                }
                ForEach(directories) { dir in
                    Toggle(isOn: Binding(
                        get: { dir.active },
                        set: { newValue in Task { await setActive(dir, newValue) } }
                    )) {
                        WatchDirectoryRow(directory: dir, isBusy: busyPath == dir.path)
                    }
                    .contextMenu {
                        Button { editingDirectory = dir } label: {
                            Label("Edit Path", systemImage: "pencil")
                        }
                        Button { Task { await sync(dir) } } label: {
                            Label("Sync Directory", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { pendingRemoval = dir } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingRemoval = dir } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button { editingDirectory = dir } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button { Task { await sync(dir) } } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.green)
                    }
                }
                .onDelete { idx in
                    if let first = idx.first {
                        pendingRemoval = directories[first]
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .lookScreenBackground()
        .navigationTitle("Watch Directories")
        .overlay {
            if isLoading && directories.isEmpty {
                LookLoadingState(title: "Loading directories", message: "Reading the server watch list.")
                    .background(LookTheme.ColorToken.paper.opacity(0.92))
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingDirectory) { dir in
            EditWatchDirectorySheet(directory: dir) {
                await load()
            }
        }
        .alert(item: $pendingRemoval) { dir in
            Alert(
                title: Text("Remove Watch Directory?"),
                message: Text("Stop watching \(dir.path). Existing photos stay in the library, but new changes in this folder will no longer be picked up."),
                primaryButton: .destructive(Text("Remove")) {
                    Task { await remove(dir.path) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.watchList()
            directories = resp.directories
            message = nil
        } catch {
            message = "Could not load watch directories: \(error.localizedDescription)"
        }
    }
    private func add() async {
        do {
            _ = try await APIClient.shared.addWatchDir(newPath.trimmingCharacters(in: .whitespaces))
            newPath = ""; message = nil
            await load()
        } catch { message = error.localizedDescription }
    }
    private func remove(_ path: String) async {
        do {
            _ = try await APIClient.shared.removeWatchDir(path)
            message = "Removed \(path)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
    private func setActive(_ dir: WatchDirectory, _ active: Bool) async {
        do {
            _ = try await APIClient.shared.setWatchActive(dir.path, active: active)
            message = active ? "Watching \(dir.path)" : "Paused \(dir.path)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
    private func sync(_ dir: WatchDirectory) async {
        busyPath = dir.path
        defer { busyPath = nil }
        do {
            let submit = try await APIClient.shared.importPhotos(path: dir.path)
            message = submit.message ?? "Sync started"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct EditWatchDirectorySheet: View {
    let directory: WatchDirectory
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: String
    @State private var active: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(directory: WatchDirectory, onSaved: @escaping () async -> Void) {
        self.directory = directory
        self.onSaved = onSaved
        _path = State(initialValue: directory.path)
        _active = State(initialValue: directory.active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Directory") {
                    TextField("/path/on/server", text: $path)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Toggle("Active", isOn: $active)
                }
                if let errorMessage {
                    Section {
                        LookStatusBanner(title: "Could not save directory", message: errorMessage, tone: .error)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Edit Watch Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.updateWatchDir(
                directory.path,
                newPath: path.trimmingCharacters(in: .whitespacesAndNewlines),
                active: active
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Migrations

struct MigrationsView: View {
    @State private var info: MigrationStatusResponse?
    @State private var message: String?
    @State private var isLoading = true
    @State private var confirmApply = false

    var body: some View {
        List {
            if let message, info == nil {
                Section {
                    AdminStatusBanner(message: message, title: "Could not load migrations", actionTitle: "Retry") {
                        Task { await load() }
                    }
                }
                .listRowSeparator(.hidden)
            }
            if let info {
                Section("Schema") {
                    HStack { Text("Current version"); Spacer()
                        Text("\(info.currentVersion)")
                            .foregroundStyle(LookTheme.ColorToken.readableSecondary) }
                }
                Section("Pending (\(info.pending.count))") {
                    if info.pending.isEmpty {
                        LookStatusBanner(
                            title: "Schema is up to date",
                            message: "There are no pending server migrations.",
                            tone: .success
                        )
                    }
                    ForEach(info.pending) { m in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("v\(m.version)").font(LookTheme.Typography.captionEmphasis)
                            Text(m.description)
                                .font(LookTheme.Typography.secondary)
                                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        }
                    }
                }
                Section {
                    Button("Apply pending migrations", role: .destructive) {
                        confirmApply = true
                    }
                        .disabled(info.pending.isEmpty)
                    if let message {
                        AdminStatusBanner(message: message)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .lookScreenBackground()
        .navigationTitle("Migrations")
        .overlay {
            if isLoading && info == nil {
                LookLoadingState(title: "Checking migrations", message: "Reading the server schema status.")
                    .background(LookTheme.ColorToken.paper.opacity(0.92))
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Apply Pending Migrations?", isPresented: $confirmApply) {
            Button("Apply", role: .destructive) {
                Task { await apply() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will change the server database schema. Make sure the server is healthy and backed up before continuing.")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            info = try await APIClient.shared.migrationStatus()
            message = nil
        } catch {
            info = nil
            message = error.localizedDescription
        }
    }
    private func apply() async {
        do {
            let resp = try await APIClient.shared.runMigrations()
            message = resp.status == "applied"
                ? "Applied \(resp.appliedCount ?? 0) migration(s)" : "Already up to date"
            await load()
        } catch {
            message = "Migration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tag cleanup / merge

struct TagCleanupView: View {
    @State private var duplicates: [DuplicateTagGroup] = []
    @State private var source = ""
    @State private var target = ""
    @State private var message: String?
    @State private var isLoading = true
    @State private var pendingMerge: TagMergeRequest?

    var body: some View {
        List {
            Section("Merge tags") {
                TextField("Source tag (removed)", text: $source)
                    .autocapitalization(.none).disableAutocorrection(true)
                TextField("Target tag (kept)", text: $target)
                    .autocapitalization(.none).disableAutocorrection(true)
                Button("Merge", role: .destructive) {
                    pendingMerge = TagMergeRequest(
                        source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                        target: target.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty
                              || target.trimmingCharacters(in: .whitespaces).isEmpty)
                if let message {
                    AdminStatusBanner(message: message)
                }
            }
            Section("Possible duplicate tags") {
                if duplicates.isEmpty && !isLoading {
                    LookEmptyState(
                        title: "No duplicate tags found",
                        systemImage: "tag",
                        message: "Suggestions will appear here when the server finds tags that differ only by casing or spacing."
                    )
                    .frame(minHeight: 220)
                }
                ForEach(duplicates) { dup in
                    HStack {
                        Text(dup.normal)
                        Spacer()
                        if let c = dup.c {
                            Text("\(c)")
                                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        }
                    }
                    .font(LookTheme.Typography.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .lookScreenBackground()
        .navigationTitle("Tag Cleanup")
        .overlay {
            if isLoading && duplicates.isEmpty {
                LookLoadingState(title: "Loading tag suggestions", message: "Checking for duplicate tag names.")
                    .background(LookTheme.ColorToken.paper.opacity(0.92))
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(item: $pendingMerge) { request in
            Alert(
                title: Text("Merge Tags?"),
                message: Text("Replace \"\(request.source)\" with \"\(request.target)\" on matching photos. Tag history remains on the server, but this merge cannot be undone from the app."),
                primaryButton: .destructive(Text("Merge Tags")) {
                    Task { await merge(request) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.duplicateTagSuggestions()
            duplicates = resp.suggestions
            message = nil
        } catch {
            duplicates = []
            message = "Could not load tag suggestions: \(error.localizedDescription)"
        }
    }
    private func merge(_ request: TagMergeRequest) async {
        do {
            _ = try await APIClient.shared.mergeTags(
                source: request.source,
                target: request.target)
            message = "Merged '\(request.source)' into '\(request.target)'"
            source = ""; target = ""
            await load()
        } catch { message = error.localizedDescription }
    }
}

private struct TagMergeRequest: Identifiable {
    let source: String
    let target: String
    var id: String { "\(source)-\(target)" }
}

private struct AdminStatusBanner: View {
    let message: String
    var title: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        let resolvedTitle = title ?? Self.title(for: message)
        LookStatusBanner(
            title: resolvedTitle,
            message: resolvedTitle == message ? nil : message,
            tone: Self.tone(for: message),
            actionTitle: actionTitle,
            action: action
        )
    }

    private static func title(for message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("failed")
            || lowercased.contains("could not")
            || lowercased.contains("unable")
            || lowercased.contains("error") {
            return "Action failed"
        }
        if lowercased.contains("disabled")
            || lowercased.contains("cancelled")
            || lowercased.contains("timed out")
            || lowercased.contains("waiting") {
            return "Needs attention"
        }
        return message
    }

    private static func tone(for message: String) -> LookStatusBanner.Tone {
        let lowercased = message.lowercased()
        if lowercased.contains("failed")
            || lowercased.contains("could not")
            || lowercased.contains("unable")
            || lowercased.contains("error") {
            return .error
        }
        if lowercased.contains("disabled")
            || lowercased.contains("cancelled")
            || lowercased.contains("timed out")
            || lowercased.contains("waiting") {
            return .warning
        }
        if lowercased.contains("updated")
            || lowercased.contains("merged")
            || lowercased.contains("removed")
            || lowercased.contains("watching")
            || lowercased.contains("paused")
            || lowercased.contains("applied")
            || lowercased.contains("up to date")
            || lowercased.contains("found") {
            return .success
        }
        return .info
    }
}

private struct WatchDirectoryRow: View {
    let directory: WatchDirectory
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(directory.path)
                .font(LookTheme.Typography.mono)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack(spacing: LookTheme.Spacing.tight) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.72)
                    Text("Working...")
                } else if let added = directory.addedAt {
                    Image(systemName: "calendar")
                    Text("Added \(added.prefix(10))")
                }
            }
            .font(LookTheme.Typography.caption)
            .foregroundStyle(LookTheme.ColorToken.readableSecondary)
        }
    }
}
