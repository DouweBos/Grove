// Views/History/HistoryViewModel.swift
// Grove

import Foundation
import Observation
import SwiftUI

/// ViewModel for the History view.
///
/// Manages commit log loading, search/filter state, commit detail selection,
/// and the commit graph topology used by ``CommitGraphColumn``.
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

    // MARK: - Graph

    /// Keyed by commit SHA. Populated after every page load.
    var graphNodes: [String: GraphNode] = [:]
    /// Number of active columns in the widest row. Drives graph column width.
    var maxGraphColumns: Int = 1

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
        graphNodes = [:]
        maxGraphColumns = 1
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
            buildGraph()
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
        do {
            try await repository.cherryPick(commit: commit.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createBranch(from commit: CommitInfo) async {
        do {
            try await repository.createBranch(name: "new-branch", from: commit.id, checkout: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTag(at commit: CommitInfo) async {
        do {
            try await repository.createTag(name: "new-tag", at: commit.id, message: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Graph

    /// Rebuilds the full graph from the currently loaded commit list.
    ///
    /// Called after every page load. The builder processes all commits in one
    /// pass so topology stays correct across page boundaries.
    private func buildGraph() {
        let builder = CommitGraphBuilder()
        let nodes = builder.buildGraph(from: commits)
        var nodeMap: [String: GraphNode] = [:]
        nodeMap.reserveCapacity(nodes.count)
        for node in nodes {
            nodeMap[node.id] = node
        }
        graphNodes = nodeMap
        maxGraphColumns = (nodes.map(\.column).max().map { $0 + 1 }) ?? 1
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
