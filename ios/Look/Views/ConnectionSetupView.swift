import SwiftUI

enum ConnectionSetupStorage {
    static let serverURLKey = "server_url"
    static let hasSuccessfulConnectionKey = "has_successful_server_connection"
    static let defaultServerURL = "http://studio.taila3f2b.ts.net:5678"
}

struct ConnectionSetupView: View {
    @EnvironmentObject private var store: PhotoStore
    @AppStorage(ConnectionSetupStorage.serverURLKey) private var serverURL = ConnectionSetupStorage.defaultServerURL
    @AppStorage(ConnectionSetupStorage.hasSuccessfulConnectionKey) private var hasSuccessfulConnection = false

    let onConnectionEstablished: () async -> Void

    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    header
                    statusBanner
                    connectionPanel
                    examplesPanel
                    helpPanel
                }
                .padding(LookTheme.Spacing.screen)
            }
            .lookScreenBackground()
            .navigationTitle("Connect to Look")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                APIClient.shared.migrateLegacyAPIKeyIfNeeded()
                apiKey = APIClient.shared.storedAPIKey
            }
        }
    }

    private var normalizedServerURL: String {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayErrorMessage: String? {
        errorMessage ?? store.errorMessage
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(LookTheme.ColorToken.cyan)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LookTheme.Spacing.tight) {
                LookTheme.eyebrow("Private library")
                Text("Connect with Tailscale")
                    .font(LookTheme.Typography.display)
                    .foregroundStyle(LookTheme.ColorToken.graphite)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Look requires a self-hosted Look server. Use the address this iPhone can reach through Tailscale, then test once to unlock the library.")
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: LookTheme.Spacing.tight) {
                LookChip(title: "MagicDNS", systemImage: "network", tint: LookTheme.ColorToken.cyan)
                LookChip(title: "100.x IP", systemImage: "lock.shield", tint: LookTheme.ColorToken.graphite)
                LookChip(title: "API key optional", systemImage: "key", tint: LookTheme.ColorToken.amber)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LookTheme.Spacing.small)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if isTesting {
            LookStatusBanner(
                title: "Checking the private route",
                message: "Testing \(normalizedServerURL) from this device.",
                tone: .info
            )
        } else if let statusMessage {
            LookStatusBanner(
                title: "Ready to browse",
                message: statusMessage,
                tone: .success,
                actionTitle: "Clear",
                action: clearStatus
            )
        } else if let displayErrorMessage {
            LookStatusBanner(
                title: "Could not reach Look",
                message: displayErrorMessage,
                tone: .error,
                actionTitle: "Clear",
                action: clearStatus
            )
        } else {
            LookStatusBanner(
                title: "Use a private-network address",
                message: "Use the private Tailscale HTTP or HTTPS address for your self-hosted Look server, including the port.",
                tone: .info
            )
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Server",
                subtitle: "This is usually the Mac, NAS, or mini PC running Look.",
                systemImage: "server.rack"
            )

            VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                fieldLabel("Server URL", detail: "Required")
                TextField("http://studio.taila3f2b.ts.net:5678", text: $serverURL)
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
                fieldLabel("API key", detail: "Only if API_KEY is set on the server")
                SecureField("Leave blank for a private Tailscale server without API_KEY", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .focused($focusedField, equals: .apiKey)
                    .submitLabel(.go)
                    .onSubmit { testConnection() }
                    .lookTextInputSurface()
            }

            Button {
                testConnection()
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isTesting ? "Testing connection" : "Test and continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTesting || normalizedServerURL.isEmpty)
            .controlSize(.large)
            .padding(.top, LookTheme.Spacing.tight)
        }
        .lookPanel()
    }

    private var examplesPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            panelHeader(
                title: "Common Tailscale Addresses",
                subtitle: "Tap an example to fill the server URL, then replace it with your machine's address.",
                systemImage: "network"
            )

            VStack(spacing: LookTheme.Spacing.small) {
                exampleRow("Tailscale IP", value: "http://100.86.254.112:5678", note: "Works even if MagicDNS is disabled.")
                exampleRow("MagicDNS", value: "http://studio.tailnet-name.ts.net:5678", note: "Friendlier when Tailscale DNS is enabled.")
            }
        }
        .lookPanel()
    }

    private var helpPanel: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            Label("Before testing", systemImage: "checklist")
                .font(LookTheme.Typography.headline)
            Text("Make sure Tailscale is connected on this iPhone and on the Look server. The server should be running on port 5678 and reachable from the same Tailscale network. Look does not scan this iPhone's photo library.")
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lookPanel()
    }

    private func panelHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(LookTheme.ColorToken.cyan)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LookTheme.Typography.headline)
                Text(subtitle)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LookTheme.Typography.secondaryEmphasis)
                .foregroundStyle(LookTheme.ColorToken.graphite)
            Spacer()
            Text(detail)
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
        }
    }

    private func exampleRow(_ label: String, value: String, note: String) -> some View {
        Button {
            serverURL = value
            clearStatus()
        } label: {
            HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
                Image(systemName: "arrow.down.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LookTheme.ColorToken.cyan)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(LookTheme.Typography.secondaryEmphasis)
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(LookTheme.Typography.mono)
                        .foregroundStyle(LookTheme.ColorToken.graphite)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(note)
                        .font(LookTheme.Typography.caption)
                        .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: LookTheme.Spacing.tight)
            }
            .padding(LookTheme.Spacing.small)
            .background(LookTheme.ColorToken.mist.opacity(0.45), in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func testConnection() {
        clearStatus()
        let trimmedURL = normalizedServerURL
        guard !trimmedURL.isEmpty else {
            errorMessage = "Enter a server URL."
            return
        }
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            errorMessage = "Enter a valid URL, including http:// or https://."
            return
        }
        guard APIClient.shared.saveAPIKey(apiKey) else {
            errorMessage = "Could not save the API key to Keychain."
            return
        }

        serverURL = trimmedURL
        isTesting = true

        Task {
            defer { isTesting = false }
            do {
                await store.checkConnection()
                guard store.serverConnected else {
                    throw ConnectionSetupError.connectionFailed(
                        store.errorMessage ?? "The server responded, but health status was not ok."
                    )
                }

                hasSuccessfulConnection = true
                statusMessage = "Connected to \(trimmedURL)"
                store.errorMessage = nil
                await onConnectionEstablished()
            } catch {
                hasSuccessfulConnection = false
                store.serverConnected = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearStatus() {
        statusMessage = nil
        errorMessage = nil
        store.errorMessage = nil
    }

    private enum Field {
        case serverURL
        case apiKey
    }
}

private enum ConnectionSetupError: LocalizedError {
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        }
    }
}
