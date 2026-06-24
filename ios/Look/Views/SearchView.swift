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
        GridItem(.adaptive(minimum: 110), spacing: 2)
    ]

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
            VStack {
                searchField

                content
            }
            .navigationTitle("Search")
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
            .fullScreenCover(item: $selectedPhoto) { photo in
                NativePhotoViewer(photos: results, initialPhoto: photo)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("Search photos...", text: $query)
                .textFieldStyle(.roundedBorder)
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
                        .imageScale(.large)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button {
                submitSearch(query, updateField: true)
            } label: {
                Image(systemName: "magnifyingglass")
                    .imageScale(.large)
            }
            .buttonStyle(.bordered)
            .disabled(trimmedQuery.isEmpty)
            .accessibilityLabel("Submit search")
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
            VStack(spacing: 22) {
                stateHeader(
                    systemImage: "magnifyingglass",
                    title: "Search your photo library",
                    message: "Search by filename, tags, or filepath",
                    showProgress: false
                )

                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Recent")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                recentSearchesStorage = ""
                            }
                            .font(.subheadline)
                            .accessibilityLabel("Clear recent searches")
                        }

                        ForEach(recentSearches, id: \.self) { recentQuery in
                            Button {
                                submitSearch(recentQuery, updateField: true)
                            } label: {
                                Label(recentQuery, systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Search for \(recentQuery)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(results) { photo in
                    PhotoCard(photo: photo)
                        .onTapGesture { selectedPhoto = photo }
                        .accessibilityLabel("Open \(photo.filename)")
                }
            }
            .padding(2)
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
        VStack {
            Spacer()
            stateHeader(systemImage: systemImage, title: title, message: message, showProgress: showProgress)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                    .accessibilityLabel(actionTitle)
            }
            Spacer()
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
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
