// Views/PullRequests/PullRequestsViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - PRFilterState

/// The active filter tab in the pull request list.
enum PRFilterState: String, CaseIterable, Hashable {
    case open   = "Open"
    case closed = "Closed"
    case all    = "All"
}

// MARK: - PRDetailTab

/// The tab selected inside the PR detail panel.
enum PRDetailTab: String, CaseIterable, Hashable {
    case overview = "Overview"
    case commits  = "Commits"
    case files    = "Files"
}

// MARK: - PullRequestsViewModel

/// ViewModel for the Pull Requests view.
@Observable
final class PullRequestsViewModel {

    // MARK: - State

    /// All pull requests fetched from the repository.
    var pullRequests: [PullRequestInfo] = []
    /// The PR selected in the list panel.
    var selectedPR: PullRequestInfo?
    /// Comments loaded for the selected PR.
    var comments: [PRComment] = []
    /// The active tab in the detail panel.
    var activeDetailTab: PRDetailTab = .overview
    /// Active filter controlling which PRs are visible.
    var filterState: PRFilterState = .open
    var isLoading = false
    var isLoadingComments = false
    var errorMessage: String?
    var actionError: String?

    // MARK: - PR Commits Tab State

    /// Commits on the PR's source branch (for the Commits tab).
    var prCommits: [CommitInfo] = []
    var isLoadingPRCommits = false

    // MARK: - PR Changeset Tab State

    /// All file diffs across the entire PR (for the Files tab).
    var prChangeset: [FileDiff] = []
    /// The file currently expanded in the changeset tab.
    var selectedChangesetFile: FileDiff?
    var isLoadingChangeset = false

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Derived

    /// Pull requests filtered by the active ``filterState``.
    var filteredPullRequests: [PullRequestInfo] {
        switch filterState {
        case .open:
            return pullRequests.filter { $0.state == .open }
        case .closed:
            return pullRequests.filter { $0.state == .closed || $0.state == .merged }
        case .all:
            return pullRequests
        }
    }

    // MARK: - Actions

    /// Reload the full PR list from the repository.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pullRequests = try await repository.pullRequests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Select a PR and load its comments, commits, and changeset.
    func selectPR(_ pr: PullRequestInfo) async {
        selectedPR = pr
        activeDetailTab = .overview
        comments = []
        prCommits = []
        prChangeset = []
        selectedChangesetFile = nil

        // Load comments for the Overview tab.
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            comments = try await repository.pullRequestComments(number: pr.id)
        } catch {
            // Non-fatal — comments section shows empty state.
            errorMessage = error.localizedDescription
        }
    }

    /// Load commits for the PR's source branch (Commits tab).
    ///
    /// Uses `git log <sourceBranch>` with a limit. Called lazily when the
    /// user switches to the Commits tab.
    func loadPRCommits(for pr: PullRequestInfo) async {
        guard prCommits.isEmpty else { return }
        isLoadingPRCommits = true
        defer { isLoadingPRCommits = false }
        do {
            prCommits = try await repository.log(
                maxCount: 100,
                skip: 0,
                branch: pr.sourceBranch
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Load the combined file changeset for the PR (Files tab).
    ///
    /// Fetches the diffs from the most recent commit on the source branch
    /// as a representative snapshot. For a more accurate result a real
    /// `git diff <target>..<source>` would be needed, which can be plumbed
    /// through the protocol in a future iteration.
    func loadChangeset(for pr: PullRequestInfo) async {
        guard prChangeset.isEmpty else { return }
        isLoadingChangeset = true
        defer { isLoadingChangeset = false }
        do {
            // Fetch the first commit on the source branch to get its SHA,
            // then show its diff as a proxy for the PR changeset.
            let commits = try await repository.log(
                maxCount: 1,
                skip: 0,
                branch: pr.sourceBranch
            )
            if let latestCommit = commits.first {
                prChangeset = try await repository.diffForCommit(latestCommit.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle the expanded file in the changeset tab.
    func selectChangesetFile(_ fileDiff: FileDiff?) {
        if selectedChangesetFile?.path == fileDiff?.path {
            selectedChangesetFile = nil
        } else {
            selectedChangesetFile = fileDiff
        }
    }

    /// Check out the branch for the selected pull request.
    func checkout(pr: PullRequestInfo) async {
        actionError = nil
        do {
            try await repository.checkoutPullRequest(number: pr.id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Close the pull request without merging.
    func close(pr: PullRequestInfo) async {
        actionError = nil
        do {
            try await repository.closePullRequest(number: pr.id)
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Merge the pull request.
    func merge(pr: PullRequestInfo) async {
        actionError = nil
        do {
            try await repository.mergePullRequest(number: pr.id)
            await refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
