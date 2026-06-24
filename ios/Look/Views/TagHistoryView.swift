import SwiftUI

/// Audit trail of tag add/remove events for a photo (/api/photos/{id}/tags/history).
struct TagHistoryView: View {
    let photoId: String
    @State private var entries: [TagHistoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Could not load history", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await load() }
                        }
                    }
                } else if entries.isEmpty {
                    ContentUnavailableView("No history", systemImage: "clock.arrow.circlepath",
                                           description: Text("No tag changes recorded for this photo."))
                } else {
                    List(entries) { entry in
                        HStack {
                            Image(systemName: entry.action == "removed" ? "minus.circle" : "plus.circle")
                                .foregroundColor(entry.action == "removed" ? .red : .green)
                            VStack(alignment: .leading) {
                                Text(entry.tag).font(.body)
                                Text("\(entry.action) • \(entry.timestamp)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            if let user = entry.byUser {
                                Spacer()
                                Text(user).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tag History")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.tagHistory(photoId)
            entries = resp.history
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}
