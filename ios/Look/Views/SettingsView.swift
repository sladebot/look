import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.serverURLKey) private var serverURL = ConnectionSetupStorage.defaultServerURL
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var cacheMessage: String?
    @State private var keychainMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://machine.tailnet.ts.net:5678", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)

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
                        testConnection()
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter your server's Tailscale address (a 100.x.y.z IP or a machine.tailnet.ts.net name) and port. The API key is only needed if the server sets API_KEY.")
                        if let keychainMessage {
                            Text(keychainMessage)
                                .foregroundColor(.red)
                        }
                    }
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
            .onChange(of: apiKey) { _, newValue in
                keychainMessage = APIClient.shared.saveAPIKey(newValue) ? nil : "Could not save the API key to Keychain."
            }
            .task {
                APIClient.shared.migrateLegacyAPIKeyIfNeeded()
                apiKey = APIClient.shared.storedAPIKey
                if hasSuccessfulConnection {
                    await store.checkConnection()
                    if !store.serverConnected {
                        hasSuccessfulConnection = false
                    }
                }
                await store.loadServerSettings()
            }
        }
    }

    private func testConnection() {
        keychainMessage = nil
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            store.serverConnected = false
            hasSuccessfulConnection = false
            store.errorMessage = "Enter a valid server URL, including http:// or https://."
            return
        }
        guard APIClient.shared.saveAPIKey(apiKey) else {
            keychainMessage = "Could not save the API key to Keychain."
            return
        }

        serverURL = trimmedURL
        isTesting = true
        Task {
            await store.checkConnection()
            hasSuccessfulConnection = store.serverConnected
            if store.serverConnected {
                store.errorMessage = nil
                await store.loadServerSettings()
            }
            isTesting = false
        }
    }

    private func serverToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { store.boolSetting(key) },
            set: { newValue in Task { await store.toggleServerSetting(key, to: newValue) } }
        ))
    }
}
