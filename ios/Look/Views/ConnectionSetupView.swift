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
    @State private var connectionVerified = false
    @State private var showAPIKey = false
    @State private var showHelp = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                    header
                    statusBanner
                    connectionCard
                    helpDisclosure
                }
                .padding(LookTheme.Spacing.screen)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .lookScreenBackground()
            .navigationTitle("Welcome to Look")
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
            Image(systemName: "photo.stack")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LookTheme.ColorToken.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LookTheme.Spacing.tight) {
                Text("Your photos, on your server")
                    .font(LookTheme.Typography.display)
                    .foregroundStyle(LookTheme.ColorToken.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Browse your private photo archive without moving it to a cloud service. Enter the address of the computer running Look.")
                    .font(LookTheme.Typography.body)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, LookTheme.Spacing.small)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if isTesting {
            LookStatusBanner(
                title: "Connecting…",
                message: "Checking your Look server securely from this device.",
                tone: .info
            )
        } else if connectionVerified, let statusMessage {
            LookStatusBanner(
                title: "Your library is ready",
                message: statusMessage,
                tone: .success
            )
        } else if let displayErrorMessage {
            LookStatusBanner(
                title: "Could not reach Look",
                message: displayErrorMessage,
                tone: .error,
                actionTitle: "Clear",
                action: clearStatus
            )
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
            cardHeader(title: "Connect to your library",
                       subtitle: "This is usually a Mac, NAS, or home server reachable through Tailscale.")

            VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                fieldLabel("Server URL", detail: "Required")
                TextField("http://studio.taila3f2b.ts.net:5678", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .focused($focusedField, equals: .serverURL)
                    .submitLabel(showAPIKey ? .next : .go)
                    .onSubmit {
                        if showAPIKey { focusedField = .apiKey }
                        else { testConnection() }
                    }
                    .lookTextInput()
            }

            DisclosureGroup(isExpanded: $showAPIKey) {
                VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .focused($focusedField, equals: .apiKey)
                        .submitLabel(.go)
                        .onSubmit { testConnection() }
                        .lookTextInput()
                    Text("Only required when API_KEY is enabled on your Look server. It is stored in Keychain.")
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                }
                .padding(.top, LookTheme.Spacing.small)
            } label: {
                Label("My server uses an API key", systemImage: "key")
                    .font(LookTheme.Typography.secondaryEmphasis)
            }

            Button { connectionVerified ? openLibrary() : testConnection() } label: {
                HStack(spacing: LookTheme.Spacing.small) {
                    if isTesting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isTesting ? "Connecting" : connectionVerified ? "Open Library" : "Connect")
                        .font(LookTheme.Typography.bodyEmphasis)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(LookTheme.ColorToken.accentControl)
            .foregroundStyle(.white)
            .disabled(isTesting || normalizedServerURL.isEmpty)
            .padding(.top, LookTheme.Spacing.tight)
        }
        .lookCard()
        .onChange(of: serverURL) { _, _ in resetVerifiedConnection() }
        .onChange(of: apiKey) { _, _ in resetVerifiedConnection() }
    }

    private var helpDisclosure: some View {
        DisclosureGroup(isExpanded: $showHelp) {
            VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                Text("Make sure Tailscale is connected on this device and on the Look server. Look normally runs on port 5678.")
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
                exampleRow("Tailscale IP", value: "http://100.86.254.112:5678", note: "Works without MagicDNS.")
                exampleRow("MagicDNS", value: "http://studio.tailnet-name.ts.net:5678", note: "Use your server’s tailnet name.")
                Text("Look reads the archive on your server. It does not scan or upload this device’s photo library.")
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.secondaryText)
            }
            .padding(.top, LookTheme.Spacing.medium)
        } label: {
            Label("Need help connecting?", systemImage: "questionmark.circle")
                .font(LookTheme.Typography.secondaryEmphasis)
        }
        .lookCard()
    }

    private func cardHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(LookTheme.Typography.headline)
                .foregroundStyle(LookTheme.ColorToken.primaryText)
            Text(subtitle)
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(LookTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ title: String, detail: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                fieldLabelTitle(title)
                Spacer()
                fieldLabelDetail(detail)
            }
            VStack(alignment: .leading, spacing: 2) {
                fieldLabelTitle(title)
                fieldLabelDetail(detail)
            }
        }
    }

    private func fieldLabelTitle(_ title: String) -> some View {
        Text(title)
            .font(LookTheme.Typography.secondaryEmphasis)
            .foregroundStyle(LookTheme.ColorToken.primaryText)
    }

    private func fieldLabelDetail(_ detail: String) -> some View {
        Text(detail)
            .font(LookTheme.Typography.secondary)
            .foregroundStyle(LookTheme.ColorToken.secondaryText)
    }

    private func exampleRow(_ label: String, value: String, note: String) -> some View {
        Button {
            serverURL = value
            clearStatus()
        } label: {
            HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(LookTheme.Typography.secondaryEmphasis)
                        .foregroundStyle(LookTheme.ColorToken.primaryText)
                    Text(value)
                        .font(LookTheme.Typography.mono)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(note)
                        .font(LookTheme.Typography.secondary)
                        .foregroundStyle(LookTheme.ColorToken.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: LookTheme.Spacing.tight)

                Image(systemName: "arrow.down.left.circle")
                    .font(LookTheme.Typography.headline)
                    .foregroundStyle(LookTheme.ColorToken.accent)
                    .accessibilityHidden(true)
            }
            .padding(LookTheme.Spacing.medium)
            .frame(minHeight: 44)
            .background(LookTheme.ColorToken.elevated,
                        in: RoundedRectangle(cornerRadius: LookTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy address", systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel("\(label). \(value). \(note)")
        .accessibilityHint("Fills the server URL field with this example.")
    }

    private func testConnection() {
        clearStatus()
        connectionVerified = false
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

                connectionVerified = true
                statusMessage = "Connected to your private Look server."
                store.errorMessage = nil
            } catch {
                hasSuccessfulConnection = false
                store.serverConnected = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openLibrary() {
        guard connectionVerified else { return }
        hasSuccessfulConnection = true
        Task { await onConnectionEstablished() }
    }

    private func clearStatus() {
        statusMessage = nil
        errorMessage = nil
        store.errorMessage = nil
    }

    private func resetVerifiedConnection() {
        guard connectionVerified else { return }
        connectionVerified = false
        statusMessage = nil
        hasSuccessfulConnection = false
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
