// Views/BranchesReview/BranchesReviewViewModel.swift
// Grove

import Foundation
import Observation

enum BranchCategory: String, CaseIterable, Sendable {
    case merged = "Merged"
    case stale = "Stale"
    case active = "Active"
}

struct ReviewedBranch: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sha: String
    let isCurrentBranch: Bool
    let isPrimary: Bool
    let lastCommitDate: Date?
    let lastCommitSummary: String
    let authorName: String
    /// Relative to the primary branch.
    let ahead: Int
    let behind: Int
    let category: BranchCategory
    let daysSinceLastCommit: Int?

    var isDeletable: Bool { !isCurrentBranch && !isPrimary }
}

@MainActor
@Observable
final class BranchesReviewViewModel {

    struct PendingDelete: Identifiable {
        let branches: [ReviewedBranch]
        var id: [String] { branches.map(\.id) }
        /// Unmerged branches need `-D`, which loses their unique commits.
        var needsForce: Bool { branches.contains { $0.category != .merged } }
    }

    // MARK: - State

    private(set) var branches: [ReviewedBranch] = []
    private(set) var primaryBranch = "main"
    private(set) var selectedIDs: Set<String> = []
    private(set) var categoryFilter: BranchCategory?
    private(set) var isLoading = false
    private(set) var isDeleting = false
    var errorMessage: String?
    /// Set when the merged-branches check failed; deleting stays off so unmerged branches aren't force-deleted as merged.
    private(set) var mergeStatusError: String?
    var pendingDelete: PendingDelete?

    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    var staleDays: Int { GrovePreferences.staleBranchDays }

    // MARK: - Derived

    var visibleBranches: [ReviewedBranch] {
        guard let categoryFilter else { return branches }
        return branches.filter { $0.category == categoryFilter }
    }

    func count(of category: BranchCategory) -> Int {
        branches.filter { $0.category == category }.count
    }

    var canDelete: Bool { mergeStatusError == nil && !isDeleting && !isLoading }

    var selectedBranches: [ReviewedBranch] {
        branches.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let local = try await repository.localBranches()
            let primary = Self.primaryBranchName(from: local)
            let merged: Set<String>
            do {
                merged = try await repository.mergedBranches(into: primary)
                mergeStatusError = nil
            } catch {
                merged = []
                mergeStatusError = error.localizedDescription
            }
            var reviewed: [ReviewedBranch] = []
            for branch in local {
                reviewed.append(await review(branch, primary: primary, merged: merged))
            }
            primaryBranch = primary
            branches = reviewed.sorted(by: Self.displayOrder)
            selectedIDs.formIntersection(branches.filter(\.isDeletable).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func review(_ branch: BranchInfo, primary: String, merged: Set<String>) async -> ReviewedBranch {
        let latest = (try? await repository.log(maxCount: 1, skip: 0, branch: branch.name))?.first
        var counts: (ahead: Int, behind: Int) = (0, 0)
        if branch.name != primary, let result = try? await repository.aheadBehind(branch: branch.name, base: primary) {
            counts = result
        }
        let days = latest.map { Calendar.current.dateComponents([.day], from: $0.authorDate, to: .now).day ?? 0 }
        let isPrimary = branch.name == primary
        let category: BranchCategory
        if !isPrimary && !branch.isHEAD && merged.contains(branch.name) {
            category = .merged
        } else if !isPrimary && !branch.isHEAD, let days, days >= staleDays {
            category = .stale
        } else {
            category = .active
        }
        return ReviewedBranch(
            id: branch.id, name: branch.name, sha: branch.targetSHA, isCurrentBranch: branch.isHEAD,
            isPrimary: isPrimary, lastCommitDate: latest?.authorDate, lastCommitSummary: latest?.summary ?? "",
            authorName: latest?.authorName ?? "", ahead: counts.ahead, behind: counts.behind,
            category: category, daysSinceLastCommit: days
        )
    }

    // MARK: - Selection & Filter

    func toggleSelection(_ branch: ReviewedBranch) {
        guard branch.isDeletable else { return }
        if selectedIDs.contains(branch.id) { selectedIDs.remove(branch.id) } else { selectedIDs.insert(branch.id) }
    }

    func selectAllVisible() {
        selectedIDs.formUnion(visibleBranches.filter(\.isDeletable).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func toggleFilter(_ category: BranchCategory) {
        categoryFilter = categoryFilter == category ? nil : category
    }

    // MARK: - Delete

    func requestDelete(_ branches: [ReviewedBranch]) {
        let deletable = branches.filter(\.isDeletable)
        guard canDelete, !deletable.isEmpty else { return }
        pendingDelete = PendingDelete(branches: deletable)
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// Takes the dialog item because the dialog clears `pendingDelete` before running its action.
    func confirmDelete(_ pending: PendingDelete) async {
        pendingDelete = nil
        guard mergeStatusError == nil else { return }
        isDeleting = true
        defer { isDeleting = false }
        var failures: [String] = []
        var deleted: [GitUndoManager.GitAction] = []
        for branch in pending.branches {
            do {
                try await repository.deleteBranch(name: branch.name, force: branch.category != .merged)
                selectedIDs.remove(branch.id)
                deleted.append(GitUndoManager.deleteBranchAction(branchName: branch.name, sha: branch.sha,
                                                                 repository: repository))
            } catch {
                failures.append("\(branch.name): \(error.localizedDescription)")
            }
        }
        // One entry so a single Edit › Undo restores the whole batch.
        if deleted.count == 1 {
            undoManager?.record(deleted[0])
        } else if !deleted.isEmpty {
            undoManager?.record(GitUndoManager.groupedAction(description: "Delete \(deleted.count) Branches",
                                                             actions: deleted))
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        await refresh()
        await onRepositoryChanged?()
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    static func primaryBranchName(from branches: [BranchInfo]) -> String {
        for name in ["main", "master", "trunk", "develop"] where branches.contains(where: { $0.name == name }) {
            return name
        }
        return branches.first(where: \.isHEAD)?.name ?? "main"
    }

    private static func displayOrder(_ lhs: ReviewedBranch, _ rhs: ReviewedBranch) -> Bool {
        let rank: [BranchCategory: Int] = [.merged: 0, .stale: 1, .active: 2]
        if lhs.category != rhs.category { return rank[lhs.category]! < rank[rhs.category]! }
        let (l, r) = (lhs.lastCommitDate ?? .distantPast, rhs.lastCommitDate ?? .distantPast)
        // Cleanup candidates oldest first; active work newest first.
        return lhs.category == .active ? l > r : l < r
    }
}
