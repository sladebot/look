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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://machine.tailnet.ts.net:5678", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)

                    SecureField("API key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                } header: {
                    Text("Look Server")
                } footer: {
                    Text("Use the server URL you can reach from this device. The API key is only required when the server sets API_KEY.")
                }

                Section("Tailscale Examples") {
                    exampleRow("Tailscale IP", value: "http://100.86.254.112:5678")
                    exampleRow("MagicDNS", value: "http://studio.tailnet-name.ts.net:5678")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.75)
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(isTesting || normalizedServerURL.isEmpty)

                    if statusMessage != nil || displayErrorMessage != nil {
                        Button("Clear Status") {
                            clearStatus()
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        if let displayErrorMessage {
                            Label(displayErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Connect to Look")
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

    private func exampleRow(_ label: String, value: String) -> some View {
        Button {
            serverURL = value
            clearStatus()
        } label: {
            LabeledContent(label, value: value)
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
