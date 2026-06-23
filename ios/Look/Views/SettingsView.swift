import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage("server_url") private var serverURL = "http://studio.taila3f2b.ts.net:5678"
    @AppStorage("api_key") private var apiKey = ""
    @State private var isTesting = false
    @State private var cacheMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://machine.tailnet.ts.net:5678", text: $serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API key (optional)", text: $apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack {
                        Text("Status")
                        Spacer()
                        if store.serverConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Button {
                        isTesting = true
                        Task {
                            await store.checkConnection()
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            if isTesting { ProgressView().scaleEffect(0.7) }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("Enter your server's Tailscale address (a 100.x.y.z IP or a machine.tailnet.ts.net name) and port. The API key is only needed if the server sets API_KEY.")
                }

                Section("Sync") {
                    Toggle("Auto Sync", isOn: Binding(
                        get: { store.autoSyncEnabled },
                        set: { on in if on { store.startAutoSync() } else { store.stopAutoSync() } }
                    ))
                    Button {
                        Task { await store.syncNow() }
                    } label: {
                        HStack {
                            if store.isSyncing { ProgressView().scaleEffect(0.7) }
                            Text("Sync & Import Now")
                        }
                    }
                    .disabled(store.isSyncing)
                    if let message = store.lastSyncMessage {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(message).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Thumbnail Cache") {
                    LabeledContent("Limit", value: "256 MB disk, 64 MB memory")
                    Button(role: .destructive) {
                        URLCache.shared.removeAllCachedResponses()
                        cacheMessage = "Thumbnail cache cleared"
                    } label: {
                        Label("Clear Thumbnail Cache", systemImage: "trash")
                    }
                    if let cacheMessage {
                        Text(cacheMessage).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Library Info") {
                    LabeledContent("Photos", value: "\(store.totalPhotos)")
                    LabeledContent("Albums", value: "\(store.albums.count)")
                    LabeledContent("Smart Albums", value: "\(store.smartCollections.count)")
                }

                Section("Server Features") {
                    serverToggle("Smart Albums", key: "smart_albums_enabled")
                    serverToggle("Deduplication", key: "dedup_enabled")
                    serverToggle("Tag History", key: "tag_history_enabled")
                    serverToggle("Auto-tag GPS", key: "auto_tag_gps")
                    serverToggle("Auto-tag Camera", key: "auto_tag_camera")
                }

                Section("Tools") {
                    NavigationLink { DedupView() } label: { Label("Duplicates", systemImage: "square.on.square") }
                    NavigationLink { TasksView() } label: { Label("Background Tasks", systemImage: "list.bullet.rectangle") }
                    NavigationLink { WatchListView() } label: { Label("Watch Directories", systemImage: "folder.badge.gearshape") }
                    NavigationLink { TagCleanupView() } label: { Label("Tag Cleanup", systemImage: "tag") }
                    NavigationLink { MigrationsView() } label: { Label("Migrations", systemImage: "cylinder.split.1x2") }
                }

                Section("About") {
                    LabeledContent("App", value: "Look")
                    LabeledContent("Version", value: "1.1.0")
                }
            }
            .navigationTitle("Settings")
            .task {
                await store.checkConnection()
                await store.loadServerSettings()
            }
        }
    }

    private func serverToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { store.boolSetting(key) },
            set: { newValue in Task { await store.toggleServerSetting(key, to: newValue) } }
        ))
    }
}
