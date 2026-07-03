import SwiftUI

/// Audit trail of tag add/remove events for a photo (/api/photos/{id}/tags/history).
struct TagHistoryView: View {
    let photoId: String
    @State private var entries: [TagHistoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tag History")
                .navigationBarTitleDisplayMode(.inline)
                .task { await load() }
                .refreshable { await load() }
                .lookScreenBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LookLoadingState(title: "Loading tag history", message: "Reading the audit trail for this photo.")
        } else if let errorMessage {
            VStack {
                LookStatusBanner(
                    title: "Could not load history",
                    message: errorMessage,
                    tone: .error,
                    actionTitle: "Retry"
                ) {
                    Task { await load() }
                }
                .padding()
                Spacer()
            }
        } else if entries.isEmpty {
            LookEmptyState(
                title: "No tag history",
                systemImage: "clock.arrow.circlepath",
                message: "No tag changes have been recorded for this photo."
            )
        } else {
            List(entries) { entry in
                TagHistoryRow(entry: entry)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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

private struct TagHistoryRow: View {
    let entry: TagHistoryEntry

    private var isRemoval: Bool {
        entry.action == "removed"
    }

    var body: some View {
        HStack(alignment: .top, spacing: LookTheme.Spacing.small) {
            Image(systemName: isRemoval ? "minus.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(isRemoval ? LookTheme.ColorToken.danger : .green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.tag)
                        .font(LookTheme.Typography.bodyEmphasis)
                        .lineLimit(2)

                    Spacer(minLength: LookTheme.Spacing.small)

                    LookChip(
                        title: isRemoval ? "Removed" : "Added",
                        systemImage: isRemoval ? "minus" : "plus",
                        tint: isRemoval ? LookTheme.ColorToken.danger : .green
                    )
                }

                HStack(spacing: LookTheme.Spacing.tight) {
                    Label(entry.timestamp, systemImage: "clock")
                    if let user = entry.byUser, !user.isEmpty {
                        Label(user, systemImage: "person.crop.circle")
                    }
                }
                .font(LookTheme.Typography.caption)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
            }
        }
        .padding(LookTheme.Spacing.medium)
        .lookInsetSurface()
        .accessibilityElement(children: .combine)
    }
}
