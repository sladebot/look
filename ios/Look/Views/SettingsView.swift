import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: PhotoStore
    @AppStorage("server_url") private var serverURL = "http://10.0.0.151:8765"
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL)
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

                    Button(action: {
                        isTesting = true
                        Task {
                            await store.checkConnection()
                            isTesting = false
                        }
                    }) {
                        HStack {
                            if isTesting {
                                ProgressView().scaleEffect(0.7)
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)
                }

                Section("Library Info") {
                    HStack {
                        Text("Photos")
                        Spacer()
                        Text("\(store.totalPhotos)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Albums")
                        Spacer()
                        Text("\(store.albums.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Auto Sync")
                        Spacer()
                        if store.isSyncing {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(store.autoSyncEnabled ? "On" : "Off")
                            .foregroundColor(store.autoSyncEnabled ? .green : .secondary)
                    }
                    if let message = store.lastSyncMessage {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(message).foregroundColor(.secondary)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("Look").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await store.checkConnection() }
        }
    }
}
