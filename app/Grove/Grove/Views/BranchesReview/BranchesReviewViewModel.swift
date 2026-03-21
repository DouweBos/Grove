// Views/BranchesReview/BranchesReviewViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - BranchCategory

/// How a branch is classified for review purposes.
enum BranchCategory: String, CaseIterable, Sendable {
    /// Currently checked-out branch and any branch with recent activity.
    case active  = "Active"
    /// No commits in 30 or more days.
    case stale   = "Stale"
    /// Fully merged into the primary branch (main or master).
    case merged  = "Merged"
}

// MARK: - ReviewedBranch

/// A ``BranchInfo`` augmented with review metadata computed by ``BranchesReviewViewModel``.
struct ReviewedBranch: Identifiable, Hashable, Sendable {
    /// Matches ``BranchInfo/id`` for stable identification.
    let id: String
    let name: String
    let isCurrentBranch: Bool
    let lastCommitDate: Date
    let authorName: String
    let authorEmail: String
    /// Commits ahead of the primary branch (main/master).
    let aheadOfMain: Int
    /// Commits behind the primary branch.
    let behindMain: Int
    let category: BranchCategory
}

// MARK: - BranchesReviewViewModel

/// ViewModel for the Branches Review view.
///
/// Loads all local branches, categorises them as active / stale / merged, and
/// supports batch deletion of selected stale or merged branches.
@Observable
final class BranchesReviewViewModel {

    // MARK: - State

    var branches: [ReviewedBranch] = []
    var selectedBranches: Set<String> = []
    var isLoading = false
    var isDeletingBranches = false
    var errorMessage: String?

    // MARK: - Configuration

    /// Number of days without a new commit before a branch is considered stale.
    let staleDaysThreshold: Int = 30

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Load all local branches and classify each one.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let localBranches = try await repository.localBranches()
            let primary = primaryBranchName(from: localBranches)
            var reviewed: [ReviewedBranch] = []

            for branch in localBranches {
                // Load the most recent commit on the branch for date / author metadata
                let commits = (try? await repository.log(maxCount: 1, skip: 0, branch: branch.name)) ?? []
                let latestCommit = commits.first

                let lastDate = latestCommit?.authorDate ?? Date.distantPast
                let authorName = latestCommit?.authorName ?? branch.name
                let authorEmail = latestCommit?.authorEmail ?? ""

                let category = categorise(
                    branch: branch,
                    lastCommitDate: lastDate,
                    primaryBranchName: primary
                )

                reviewed.append(ReviewedBranch(
                    id: branch.id,
                    name: branch.name,
                    isCurrentBranch: branch.isHEAD,
                    lastCommitDate: lastDate,
                    authorName: authorName,
                    authorEmail: authorEmail,
                    aheadOfMain: branch.ahead,
                    behindMain: branch.behind,
                    category: category
                ))
            }

            // Sort: current first, then by last-commit date descending
            branches = reviewed.sorted {
                if $0.isCurrentBranch != $1.isCurrentBranch { return $0.isCurrentBranch }
                return $0.lastCommitDate > $1.lastCommitDate
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all branches that are currently selected.
    ///
    /// The current branch is always excluded even if it appears in the selection.
    func deleteSelected() async {
        let toDelete = selectedBranches
            .compactMap { id in branches.first(where: { $0.id == id }) }
            .filter { !$0.isCurrentBranch }

        guard !toDelete.isEmpty else { return }

        isDeletingBranches = true
        defer { isDeletingBranches = false }

        for branch in toDelete {
            do {
                // Use force: false — the user can retry with force if needed
                try await repository.deleteBranch(name: branch.name, force: false)
                selectedBranches.remove(branch.id)
            } catch {
                errorMessage = "Failed to delete \"\(branch.name)\": \(error.localizedDescription)"
                // Continue attempting to delete the remaining selected branches
            }
        }

        await refresh()
    }

    /// Toggle the selection state of a branch.
    func toggleSelection(for branch: ReviewedBranch) {
        guard !branch.isCurrentBranch else { return }
        if selectedBranches.contains(branch.id) {
            selectedBranches.remove(branch.id)
        } else {
            selectedBranches.insert(branch.id)
        }
    }

    // MARK: - Derived

    /// Branches grouped by category, respecting the canonical display order.
    var groupedBranches: [(category: BranchCategory, branches: [ReviewedBranch])] {
        BranchCategory.allCases.compactMap { cat in
            let items = branches.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            return (category: cat, branches: items)
        }
    }

    /// Number of branches that can be deleted (stale or merged, not current).
    var deletableCount: Int {
        selectedBranches
            .compactMap { id in branches.first(where: { $0.id == id }) }
            .filter { !$0.isCurrentBranch && ($0.category == .stale || $0.category == .merged) }
            .count
    }

    // MARK: - Private Helpers

    /// Determine the name of the primary integration branch.
    private func primaryBranchName(from branches: [BranchInfo]) -> String {
        let candidates = ["main", "master", "trunk", "develop"]
        for name in candidates {
            if branches.contains(where: { $0.name == name }) { return name }
        }
        return branches.first(where: { $0.isHEAD })?.name ?? "main"
    }

    /// Categorise a single branch given its metadata.
    private func categorise(
        branch: BranchInfo,
        lastCommitDate: Date,
        primaryBranchName: String
    ) -> BranchCategory {
        // Current branch is always Active
        if branch.isHEAD { return .active }

        // Branches that are fully merged (zero ahead, have upstream tracking, or name implies it)
        // We use ahead == 0 and the branch has an upstream as a heuristic for "merged".
        // A more accurate check (git branch --merged) is not in the protocol — so we approximate:
        // if behind > 0 and ahead == 0 it is likely merged (or just stale without unique commits).
        let daysSinceLastCommit = Calendar.current.dateComponents([.day], from: lastCommitDate, to: Date()).day ?? 0
        let isStale = daysSinceLastCommit >= staleDaysThreshold

        // Heuristic: behind main + 0 unique commits = merged
        if branch.ahead == 0 && branch.behind > 0 { return .merged }

        if isStale { return .stale }
        return .active
    }
}
