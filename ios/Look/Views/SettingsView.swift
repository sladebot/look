import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.serverURLKey) private var serverURL = ConnectionSetupStorage.defaultServerURL
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var cacheMessage: String?
    @State private var keychainMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    connectionPanel
                    syncPanel
                    libraryPanel
                    featuresPanel
                    toolsPanel
                    aboutPanel
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LookNavTitle(
                        title: "Settings",
                        subtitle: store.serverConnected ? "Connected over Tailscale" : "Server connection"
                    )
                }
            }
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

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Server Connection",
                subtitle: "Use the Tailscale address this iPhone can reach.",
                systemImage: "point.3.connected.trianglepath.dotted"
            )

            connectionStatusBanner

            VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                fieldLabel("Server URL", detail: "Tailscale IP or MagicDNS")
                TextField("http://machine.tailnet.ts.net:5678", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .focused($focusedField, equals: .serverURL)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .apiKey }
                    .lookTextInputSurface()
            }

            VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                fieldLabel("API key", detail: "Optional")
                SecureField("Required only when the server sets API_KEY", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .focused($focusedField, equals: .apiKey)
                    .submitLabel(.go)
                    .onSubmit { testConnection() }
                    .lookTextInputSurface()
            }

            Text("Examples: http://100.86.254.112:5678 or http://studio.tailnet-name.ts.net:5678")
                .font(.subheadline)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                testConnection()
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isTesting ? "Testing connection" : "Test connection")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isTesting || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .lookPanel()
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        if let keychainMessage {
            LookStatusBanner(
                title: "API key was not saved",
                message: keychainMessage,
                tone: .error
            )
        } else if isTesting {
            LookStatusBanner(
                title: "Checking Look server",
                message: "Testing the private-network route before saving this connection state.",
                tone: .info
            )
        } else if store.serverConnected {
            LookStatusBanner(
                title: "Connected",
                message: "Library tabs are using \(serverURL.trimmingCharacters(in: .whitespacesAndNewlines)).",
                tone: .success
            )
        } else {
            LookStatusBanner(
                title: "Disconnected",
                message: store.errorMessage ?? "Reconnect to Tailscale or test a different server URL.",
                tone: .warning
            )
        }
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Sync",
                subtitle: "Keep the iOS library view current with the server.",
                systemImage: "arrow.triangle.2.circlepath"
            )

            Toggle("Auto sync", isOn: Binding(
                get: { store.autoSyncEnabled },
                set: { on in if on { store.startAutoSync() } else { store.stopAutoSync() } }
            ))

            Button {
                Task { await store.syncNow() }
            } label: {
                HStack {
                    if store.isSyncing { ProgressView().scaleEffect(0.8) }
                    Text(store.isSyncing ? "Syncing" : "Sync and import now")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isSyncing)

            if let message = store.lastSyncMessage {
                settingsRow("Last sync", value: message, systemImage: "clock")
            }
        }
        .lookPanel()
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Library",
                subtitle: "Local app totals and thumbnail cache controls.",
                systemImage: "photo.stack"
            )

            VStack(spacing: LookTheme.Spacing.small) {
                settingsRow("Photos", value: "\(store.totalPhotos)", systemImage: "photo")
                settingsRow("Albums", value: "\(store.albums.count)", systemImage: "rectangle.stack")
                settingsRow("Smart albums", value: "\(store.smartCollections.count)", systemImage: "sparkles.rectangle.stack")
                settingsRow("Thumbnail cache", value: "512 MB disk, 96 MB memory", systemImage: "externaldrive")
            }

            Button(role: .destructive) {
                Task {
                    await ThumbnailLoader.shared.clear()
                    URLCache.shared.removeAllCachedResponses()
                    await MainActor.run {
                        cacheMessage = "Thumbnail cache cleared"
                    }
                }
            } label: {
                Label("Clear thumbnail cache", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let cacheMessage {
                Text(cacheMessage)
                    .font(.subheadline)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
            }
        }
        .lookPanel()
    }

    private var featuresPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Server features",
                subtitle: "These settings are stored on the Look server.",
                systemImage: "slider.horizontal.3"
            )

            VStack(spacing: LookTheme.Spacing.small) {
                serverToggle("Smart albums", key: "smart_albums_enabled")
                serverToggle("Deduplication", key: "dedup_enabled")
                serverToggle("Tag history", key: "tag_history_enabled")
                serverToggle("Auto-tag GPS", key: "auto_tag_gps")
                serverToggle("Auto-tag camera", key: "auto_tag_camera")
            }
        }
        .lookPanel()
    }

    private var toolsPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Tools",
                subtitle: "Server maintenance and library organization.",
                systemImage: "wrench.and.screwdriver"
            )

            VStack(spacing: LookTheme.Spacing.tight) {
                toolLink("Duplicates", systemImage: "square.on.square") { DedupView() }
                toolLink("Background Tasks", systemImage: "list.bullet.rectangle") { TasksView() }
                toolLink("Watch Directories", systemImage: "folder.badge.gearshape") { WatchListView() }
                toolLink("Tag Cleanup", systemImage: "tag") { TagCleanupView() }
                toolLink("Migrations", systemImage: "cylinder.split.1x2") { MigrationsView() }
            }
        }
        .lookPanel()
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "About",
                subtitle: "App build information.",
                systemImage: "info.circle"
            )

            settingsRow("App", value: "Look", systemImage: "camera.aperture")
            settingsRow("Version", value: "1.1", systemImage: "number")
        }
        .lookPanel()
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

    private func panelHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(LookTheme.ColorToken.cyan)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
        }
    }

    private func settingsRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LookTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: LookTheme.Spacing.small)
            Text(value)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func toolLink<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: LookTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(LookTheme.ColorToken.cyan)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.readableTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
        }
    }

    private enum Field {
        case serverURL
        case apiKey
    }
}
