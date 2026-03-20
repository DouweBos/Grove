// Views/QuickActions/QuickActionsViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - QuickActionsViewModel

/// ViewModel for the Quick Actions command palette.
///
/// Manages presentation state, search input, tab selection, the results list,
/// and keyboard navigation.  Results are filtered synchronously from a cached
/// data snapshot that is refreshed each time the palette opens.
@Observable
final class QuickActionsViewModel {

    // MARK: - Presentation

    /// Whether the Quick Actions panel is currently visible.
    var isPresented: Bool = false

    // MARK: - Search State

    /// The text the user has typed into the search field.
    var searchText: String = "" {
        didSet { updateResults() }
    }

    /// Which search tab is active.
    var selectedTab: QuickActionsTab = .items {
        didSet { updateResults() }
    }

    // MARK: - Results

    /// The filtered results for the current search text and tab.
    var results: [QuickActionResult] = []

    /// Index of the currently highlighted result row.
    var selectedIndex: Int = 0

    // MARK: - Raw Data (populated on open)

    private var allNavigationResults: [QuickActionResult] = []
    private var allBranchResults: [QuickActionResult] = []
    private var allTagResults: [QuickActionResult] = []
    private var allFileResults: [QuickActionResult] = []
    private var allCommitResults: [QuickActionResult] = []

    // MARK: - Dependencies

    private let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Presentation

    /// Opens the palette and refreshes the searchable data snapshot.
    func open() {
        selectedIndex = 0
        searchText = ""
        isPresented = true
        Task { await refreshData() }
    }

    /// Closes the palette and clears search state.
    func close() {
        isPresented = false
        searchText = ""
    }

    // MARK: - Keyboard Navigation

    /// Moves the selection down one row, wrapping at the bottom.
    func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    /// Moves the selection up one row, wrapping at the top.
    func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    // MARK: - Activation

    /// Activates the currently highlighted result and returns the
    /// ``SidebarItem`` to navigate to (if any).
    ///
    /// - Returns: The sidebar destination, or `nil` for actions that
    ///   require custom handling by the caller.
    @discardableResult
    func activateSelected() -> SidebarItem? {
        guard results.indices.contains(selectedIndex) else { return nil }
        let result = results[selectedIndex]
        close()
        return result.sidebarItem
    }

    /// Activates a specific result by its index.
    @discardableResult
    func activate(at index: Int) -> SidebarItem? {
        guard results.indices.contains(index) else { return nil }
        selectedIndex = index
        return activateSelected()
    }

    // MARK: - Data Refresh

    private func refreshData() async {
        // Build navigation results (always the same set).
        allNavigationResults = [
            .navigation(item: .workingCopy,   title: "Working Copy"),
            .navigation(item: .history,       title: "History"),
            .navigation(item: .stashes,       title: "Stashes"),
            .navigation(item: .pullRequests,  title: "Pull Requests"),
            .navigation(item: .branchesReview, title: "Branches Review"),
            .navigation(item: .settings,      title: "Settings"),
        ]

        // Fetch live data from the repository.
        do {
            async let localBranchesTask   = repository.localBranches()
            async let remoteBranchesTask  = repository.remoteBranches()
            async let tagsTask            = repository.tags()
            async let commitsTask         = repository.log(maxCount: 50, skip: 0, branch: nil)
            async let statusTask          = repository.status()

            let (local, remote, tagList, commits, statusEntries) = try await (
                localBranchesTask,
                remoteBranchesTask,
                tagsTask,
                commitsTask,
                statusTask
            )

            allBranchResults  = local.map(QuickActionResult.branch) +
                                remote.map(QuickActionResult.branch)
            allTagResults     = tagList.map(QuickActionResult.tag)
            allCommitResults  = commits.map(QuickActionResult.commit)
            allFileResults    = statusEntries.map { QuickActionResult.filePath($0.path) }
        } catch {
            // Non-fatal — the palette still shows navigation items.
        }

        updateResults()
    }

    // MARK: - Filtering

    private func updateResults() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        switch selectedTab {
        case .items:
            let candidates = allNavigationResults
                + allBranchResults
                + allTagResults
                + allCommitResults
            results = filter(candidates, query: query)

        case .filename:
            results = filter(allFileResults, query: query)
        }

        // Clamp selection so it remains valid after the results array shrinks.
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }

    private func filter(
        _ candidates: [QuickActionResult],
        query: String
    ) -> [QuickActionResult] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { result in
            result.title.lowercased().contains(query) ||
            (result.subtitle?.lowercased().contains(query) ?? false)
        }
    }
}
