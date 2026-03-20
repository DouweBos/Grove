// Views/History/HistoryViewModel.swift
// Grove

import Foundation
import Observation

/// ViewModel for the History view.
///
/// Manages commit log loading, search/filter state, and commit detail selection.
@Observable
final class HistoryViewModel {

    // MARK: - State

    var commits: [CommitInfo] = []
    var selectedCommit: CommitInfo?
    var commitDiffs: [FileDiff] = []
    var selectedFileDiff: FileDiff?
    var isLoading = false
    var isLoadingDiff = false
    var errorMessage: String?
    var searchText = ""
    var filterBranch: String? // nil = all branches

    // MARK: - Pagination

    private let pageSize = 100
    private var loadedCount = 0
    var hasMore = true

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Actions

    func loadInitial() async {
        loadedCount = 0
        hasMore = true
        commits = []
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repository.log(
                maxCount: pageSize,
                skip: loadedCount,
                branch: filterBranch
            )
            commits.append(contentsOf: page)
            loadedCount += page.count
            hasMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectCommit(_ commit: CommitInfo) async {
        selectedCommit = commit
        selectedFileDiff = nil
        commitDiffs = []
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            commitDiffs = try await repository.diffForCommit(commit.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectFileDiff(_ fileDiff: FileDiff?) {
        selectedFileDiff = fileDiff
    }

    func cherryPick(_ commit: CommitInfo) async {
        // Placeholder — wired in WS5
    }

    func createBranch(from commit: CommitInfo) async {
        // Placeholder — wired in WS5
    }

    func createTag(at commit: CommitInfo) async {
        // Placeholder — wired in WS5
    }

    // MARK: - Derived

    var filteredCommits: [CommitInfo] {
        guard !searchText.isEmpty else { return commits }
        let lower = searchText.lowercased()
        return commits.filter {
            $0.summary.lowercased().contains(lower) ||
            $0.authorName.lowercased().contains(lower) ||
            $0.id.hasPrefix(lower)
        }
    }
}
