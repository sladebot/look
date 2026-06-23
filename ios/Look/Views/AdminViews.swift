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

    var body: some View {
        List {
            Section("Settings") {
                Toggle("Deduplication enabled", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        Task { _ = try? await APIClient.shared.updateDedupSettings(enabled: newValue) }
                    }
                Stepper("Tolerance: \(tolerance)", value: $tolerance, in: 0...64)
                    .onChange(of: tolerance) { _, newValue in
                        Task { _ = try? await APIClient.shared.updateDedupSettings(tolerance: newValue) }
                    }
                Text("Lower tolerance = stricter matching (Hamming distance on perceptual hash).")
                    .font(.caption2).foregroundColor(.secondary)
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
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                Section("Group \(index + 1) — \(group.count) photos") {
                    ForEach(group) { photo in
                        HStack {
                            AsyncImage(url: APIClient.shared.thumbnailURL(for: photo.photoId, size: 128)) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.gray.opacity(0.1) }
                            .frame(width: 56, height: 56).clipped().cornerRadius(6)
                            Text(photo.filename ?? photo.photoId).font(.caption).lineLimit(1)
                            Spacer()
                            Button("Keep") {
                                Task { await merge(groupIndex: index, keep: photo.photoId) }
                            }
                            .font(.caption).buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
        .task {
            if !loadedSettings {
                if let s = try? await APIClient.shared.dedupSettings() {
                    enabled = s.dedupEnabled
                    tolerance = s.dedupTolerance
                }
                loadedSettings = true
            }
        }
    }

    private func scan() async {
        isScanning = true
        status = "Submitting scan…"
        defer { isScanning = false }
        guard let submit = try? await APIClient.shared.submitDedupScan() else {
            status = "Failed to start scan"; return
        }
        guard let taskId = submit.taskId else {
            status = submit.status == "disabled" ? "Enable deduplication first" : "No task id returned"
            return
        }
        status = "Scanning…"
        // Poll task until done.
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let task = try? await APIClient.shared.task(taskId) else { continue }
            if ["completed", "failed", "cancelled"].contains(task.status) {
                groups = Self.parseGroups(task.result)
                status = task.status == "completed"
                    ? "Found \(groups.count) duplicate group(s)"
                    : "Scan \(task.status)"
                return
            }
        }
        status = "Scan timed out"
    }

    private func merge(groupIndex: Int, keep: String) async {
        do {
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

// MARK: - Background tasks

struct TasksView: View {
    @State private var tasks: [TaskInfo] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if tasks.isEmpty && !isLoading {
                ContentUnavailableView("No background tasks", systemImage: "list.bullet.rectangle")
            }
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.taskType ?? "task").font(.headline)
                        Spacer()
                        statusBadge(task.status)
                    }
                    if let phase = task.progress?["phase"]?.stringValue {
                        Text("Phase: \(phase)").font(.caption).foregroundColor(.secondary)
                    }
                    if let cur = task.progress?["current"]?.intValue,
                       let total = task.progress?["total_scanned"]?.intValue, total > 0 {
                        ProgressView(value: Double(cur), total: Double(total))
                    }
                    if let created = task.createdAt {
                        Text(created).font(.caption2).foregroundColor(.secondary)
                    }
                    if ["pending", "running"].contains(task.status) {
                        Button("Cancel", role: .destructive) {
                            Task {
                                _ = try? await APIClient.shared.cancelTask(task.taskId)
                                await load()
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Tasks")
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = status == "completed" ? .green
            : status == "failed" ? .red
            : status == "running" ? .blue : .secondary
        return Text(status).font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(8)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let resp = try? await APIClient.shared.tasks() { tasks = resp.tasks }
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

    var body: some View {
        List {
            Section("Add directory") {
                HStack {
                    TextField("/path/on/server", text: $newPath)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Button("Add") { Task { await add() } }
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message { Text(message).font(.caption).foregroundColor(.secondary) }
            }
            Section("Watched directories") {
                if directories.isEmpty && !isLoading {
                    Text("None").font(.caption).foregroundColor(.secondary)
                }
                ForEach(directories) { dir in
                    Toggle(isOn: Binding(
                        get: { dir.active },
                        set: { newValue in Task { await setActive(dir, newValue) } }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dir.path).font(.caption).lineLimit(2)
                            if busyPath == dir.path {
                                Text("Working...").font(.caption2).foregroundColor(.secondary)
                            } else if let added = dir.addedAt {
                                Text("Added \(added.prefix(10))").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button { editingDirectory = dir } label: {
                            Label("Edit Path", systemImage: "pencil")
                        }
                        Button { Task { await sync(dir) } } label: {
                            Label("Sync Directory", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { Task { await remove(dir.path) } } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await remove(dir.path) } } label: {
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
                    let paths = idx.map { directories[$0].path }
                    Task { for p in paths { await remove(p) } }
                }
            }
        }
        .navigationTitle("Watch Directories")
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingDirectory) { dir in
            EditWatchDirectorySheet(directory: dir) {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let resp = try? await APIClient.shared.watchList() { directories = resp.directories }
    }
    private func add() async {
        do {
            _ = try await APIClient.shared.addWatchDir(newPath.trimmingCharacters(in: .whitespaces))
            newPath = ""; message = nil
            await load()
        } catch { message = error.localizedDescription }
    }
    private func remove(_ path: String) async {
        _ = try? await APIClient.shared.removeWatchDir(path)
        await load()
    }
    private func setActive(_ dir: WatchDirectory, _ active: Bool) async {
        _ = try? await APIClient.shared.setWatchActive(dir.path, active: active)
        await load()
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
                        Text(errorMessage).foregroundColor(.red)
                    }
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

    var body: some View {
        List {
            if let info {
                Section("Schema") {
                    HStack { Text("Current version"); Spacer()
                        Text("\(info.currentVersion)").foregroundColor(.secondary) }
                }
                Section("Pending (\(info.pending.count))") {
                    if info.pending.isEmpty {
                        Text("Up to date").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(info.pending) { m in
                        VStack(alignment: .leading) {
                            Text("v\(m.version)").font(.caption.bold())
                            Text(m.description).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Section {
                    Button("Apply pending migrations") { Task { await apply() } }
                        .disabled(info.pending.isEmpty)
                    if let message { Text(message).font(.caption).foregroundColor(.secondary) }
                }
            }
        }
        .navigationTitle("Migrations")
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await APIClient.shared.migrationStatus()
    }
    private func apply() async {
        if let resp = try? await APIClient.shared.runMigrations() {
            message = resp.status == "applied"
                ? "Applied \(resp.appliedCount ?? 0) migration(s)" : "Already up to date"
            await load()
        } else {
            message = "Migration failed (API key required?)"
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

    var body: some View {
        List {
            Section("Merge tags") {
                TextField("Source tag (removed)", text: $source)
                    .autocapitalization(.none).disableAutocorrection(true)
                TextField("Target tag (kept)", text: $target)
                    .autocapitalization(.none).disableAutocorrection(true)
                Button("Merge") { Task { await merge() } }
                    .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty
                              || target.trimmingCharacters(in: .whitespaces).isEmpty)
                if let message { Text(message).font(.caption).foregroundColor(.secondary) }
            }
            Section("Possible duplicate tags") {
                if duplicates.isEmpty && !isLoading {
                    Text("None found").font(.caption).foregroundColor(.secondary)
                }
                ForEach(duplicates) { dup in
                    HStack {
                        Text(dup.normal)
                        Spacer()
                        if let c = dup.c { Text("\(c)").foregroundColor(.secondary) }
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Tag Cleanup")
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let resp = try? await APIClient.shared.duplicateTagSuggestions() {
            duplicates = resp.suggestions
        }
    }
    private func merge() async {
        do {
            _ = try await APIClient.shared.mergeTags(
                source: source.trimmingCharacters(in: .whitespaces),
                target: target.trimmingCharacters(in: .whitespaces))
            message = "Merged '\(source)' → '\(target)'"
            source = ""; target = ""
            await load()
        } catch { message = error.localizedDescription }
    }
}
