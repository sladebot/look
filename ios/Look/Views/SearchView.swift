import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var results: [Photo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: Photo?
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSearchID = UUID()
    @State private var ignoreNextQueryChange = false
    @AppStorage("recent_searches") private var recentSearchesStorage = ""

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 4)
    ]

    init(initialQuery: String = "", initialResults: [Photo] = []) {
        _query = State(initialValue: initialQuery)
        _submittedQuery = State(initialValue: initialQuery)
        _results = State(initialValue: initialResults)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentSearches: [String] {
        recentSearchesStorage
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                content
            }
            .lookScreenBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LookNavTitle(
                        title: "Search",
                        subtitle: submittedQuery.isEmpty ? "Filename, tag, camera, or path" : "\(results.count) results"
                    )
                }
            }
            .onChange(of: query) { _, newValue in
                if ignoreNextQueryChange {
                    ignoreNextQueryChange = false
                    return
                }
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
                activeSearchID = UUID()
                isLoading = false
            }
            #if DEBUG
            .task {
                // Screenshot tooling hook: LOOK_UI_SEARCH_QUERY runs a real search
                // on launch so the results grid can be captured without typing.
                if query.isEmpty,
                   let seeded = ProcessInfo.processInfo.environment["LOOK_UI_SEARCH_QUERY"],
                   !seeded.isEmpty {
                    submitSearch(seeded, updateField: true)
                }
            }
            #endif
            .fullScreenCover(item: $selectedPhoto) { photo in
                NativePhotoViewer(photos: results, initialPhoto: photo)
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
            HStack(spacing: LookTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .accessibilityHidden(true)

                TextField("Filename, tag, camera, or path", text: $query)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Search photos")
                    .onSubmit {
                        submitSearch(query, updateField: true)
                    }

                if !query.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.medium)
                            .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }

                Button {
                    submitSearch(query, updateField: true)
                } label: {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(trimmedQuery.isEmpty)
                .foregroundStyle(trimmedQuery.isEmpty ? .secondary : LookTheme.ColorToken.cyan)
                .accessibilityLabel("Submit search")
            }
            .lookTextInputSurface()
            .overlay {
                RoundedRectangle(cornerRadius: LookTheme.Radius.panel, style: .continuous)
                    .stroke(isLoading ? LookTheme.ColorToken.cyan.opacity(0.55) : Color.clear, lineWidth: 1)
            }

            Text("Search filenames, tags, camera text, and folder paths.")
                .font(LookTheme.Typography.secondary)
                .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, LookTheme.Spacing.screen)
        .padding(.top, LookTheme.Spacing.small)
        .padding(.bottom, LookTheme.Spacing.medium)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            stateView(
                systemImage: "magnifyingglass",
                title: "Searching...",
                message: submittedQuery.isEmpty ? nil : "Looking for \"\(submittedQuery)\"",
                showProgress: true
            )
        } else if let errorMessage {
            stateView(
                systemImage: "exclamationmark.triangle",
                title: "Search failed",
                message: errorMessage,
                actionTitle: "Retry",
                action: { submitSearch(submittedQuery, updateField: true) }
            )
        } else if submittedQuery.isEmpty {
            emptySearchView
        } else if results.isEmpty {
            stateView(
                systemImage: "magnifyingglass",
                title: "No results for \"\(submittedQuery)\"",
                message: "Try a different filename, tag, or path."
            )
        } else {
            resultsGrid
        }
    }

    private var emptySearchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LookTheme.Spacing.large) {
                LookEmptyState(
                    title: "Search your photo library",
                    systemImage: "photo.stack",
                    message: "Find photos by filename, tag, camera text, or folder path."
                )
                .lookPanel(inset: 0)
                .frame(minHeight: 260)

                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: LookTheme.Spacing.small) {
                        HStack {
                            LookTheme.eyebrow("Recent Searches")
                            Spacer()
                            Button("Clear") {
                                recentSearchesStorage = ""
                            }
                            .font(LookTheme.Typography.secondary)
                            .accessibilityLabel("Clear recent searches")
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: LookTheme.Spacing.tight) {
                                ForEach(recentSearches, id: \.self) { recentQuery in
                                    Button {
                                        submitSearch(recentQuery, updateField: true)
                                    } label: {
                                        LookChip(title: recentQuery, systemImage: "clock.arrow.circlepath", tint: LookTheme.ColorToken.graphite)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Search for \(recentQuery)")
                                }
                            }
                        }
                    }
                    .lookPanel()
                }
            }
            .padding(LookTheme.Spacing.screen)
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LookTheme.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        LookTheme.eyebrow("Results")
                        Text("\(results.count) photos for \"\(submittedQuery)\"")
                            .font(LookTheme.Typography.secondaryEmphasis)
                            .foregroundStyle(LookTheme.ColorToken.graphite)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, LookTheme.Spacing.tight)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(results) { photo in
                        PhotoCard(photo: photo)
                            .onTapGesture { selectedPhoto = photo }
                            .accessibilityLabel("Open \(photo.filename)")
                    }
                }
            }
            .padding(.horizontal, LookTheme.Spacing.small)
            .padding(.bottom, LookTheme.Spacing.large)
        }
        .accessibilityLabel("Search results for \(submittedQuery)")
    }

    private func stateView(
        systemImage: String,
        title: String,
        message: String? = nil,
        showProgress: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: LookTheme.Spacing.medium) {
            if showProgress {
                LookLoadingState(title: title, message: message)
            } else if actionTitle != nil {
                VStack(spacing: LookTheme.Spacing.medium) {
                    LookStatusBanner(
                        title: title,
                        message: message,
                        tone: .error,
                        actionTitle: actionTitle,
                        action: action
                    )
                    Spacer(minLength: 0)
                }
                .padding(LookTheme.Spacing.screen)
            } else {
                LookEmptyState(title: title, systemImage: systemImage, message: message)
            }
        }
    }

    private func stateHeader(
        systemImage: String,
        title: String,
        message: String?,
        showProgress: Bool
    ) -> some View {
        VStack(spacing: 12) {
            if showProgress {
                ProgressView()
                    .accessibilityLabel(title)
            } else {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(LookTheme.ColorToken.readableTertiary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(LookTheme.Typography.headline)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(LookTheme.Typography.secondary)
                    .foregroundStyle(LookTheme.ColorToken.readableSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private func scheduleSearch(for value: String) {
        searchTask?.cancel()

        let searchQuery = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        activeSearchID = requestID

        guard !searchQuery.isEmpty else {
            submittedQuery = ""
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        submittedQuery = searchQuery
        errorMessage = nil
        isLoading = true

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(searchQuery, requestID: requestID)
        }
    }

    private func submitSearch(_ value: String, updateField: Bool = false) {
        searchTask?.cancel()
        let searchQuery = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty else {
            clearSearch()
            return
        }

        if updateField && query != searchQuery {
            ignoreNextQueryChange = true
            query = searchQuery
        }

        let requestID = UUID()
        activeSearchID = requestID

        Task {
            await performSearch(searchQuery, requestID: requestID)
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        activeSearchID = UUID()
        if !query.isEmpty {
            ignoreNextQueryChange = true
            query = ""
        }
        submittedQuery = ""
        results = []
        errorMessage = nil
        isLoading = false
    }

    @MainActor
    private func performSearch(_ searchQuery: String, requestID: UUID) async {
        guard activeSearchID == requestID else { return }
        submittedQuery = searchQuery
        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIClient.shared.search(query: searchQuery)
            guard activeSearchID == requestID else { return }
            results = response.photos
            rememberSearch(searchQuery)
        } catch {
            guard activeSearchID == requestID else { return }
            results = []
            errorMessage = error.localizedDescription
        }

        if activeSearchID == requestID {
            isLoading = false
        }
    }

    private func rememberSearch(_ searchQuery: String) {
        var searches = recentSearches.filter { $0.caseInsensitiveCompare(searchQuery) != .orderedSame }
        searches.insert(searchQuery, at: 0)
        recentSearchesStorage = searches.prefix(6).joined(separator: "\n")
    }
}
