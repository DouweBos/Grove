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

/// Ahead/behind only change when either tip moves, so counts are cached by both SHAs.
struct AheadBehindCache {
    struct Key: Hashable {
        let branchSHA: String
        let baseSHA: String
    }

    private var entries: [Key: AheadBehind] = [:]

    func missing(_ keyed: [(name: String, key: Key)]) -> [String] {
        keyed.filter { entries[$0.key] == nil }.map(\.name)
    }

    /// Stores `fresh` counts and drops entries for tips that no longer exist.
    mutating func update(_ keyed: [(name: String, key: Key)], fresh: [String: AheadBehind]) {
        for (name, key) in keyed { if let value = fresh[name] { entries[key] = value } }
        let live = Set(keyed.map(\.key))
        entries = entries.filter { live.contains($0.key) }
    }

    func counts(_ keyed: [(name: String, key: Key)]) -> [String: AheadBehind] {
        Dictionary(keyed.compactMap { name, key in entries[key].map { (name, $0) } }) { first, _ in first }
    }
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
    private var aheadBehindCache = AheadBehindCache()

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
            let tips = Dictionary(try await repository.branchTips().map { ($0.name, $0) }) { first, _ in first }
            let counts = await aheadBehindCounts(for: local, primary: primary, tips: tips)
            let reviewed = local.map { review($0, primary: primary, tip: tips[$0.name], counts: counts[$0.name]) }
            primaryBranch = primary
            branches = reviewed.sorted(by: Self.displayOrder)
            selectedIDs.formIntersection(branches.filter(\.isDeletable).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Counts only branches whose tip or the primary's tip moved since the last refresh.
    private func aheadBehindCounts(for local: [BranchInfo], primary: String,
                                   tips: [String: BranchTip]) async -> [String: AheadBehind] {
        let baseSHA = tips[primary]?.sha ?? local.first { $0.name == primary }?.targetSHA ?? ""
        let keyed = local.filter { $0.name != primary }.map { branch in
            (name: branch.name,
             key: AheadBehindCache.Key(branchSHA: tips[branch.name]?.sha ?? branch.targetSHA, baseSHA: baseSHA))
        }
        var fresh: [String: AheadBehind] = [:]
        do {
            fresh = try await repository.aheadBehind(branches: aheadBehindCache.missing(keyed), base: primary)
            mergeStatusError = nil
        } catch {
            mergeStatusError = error.localizedDescription
        }
        aheadBehindCache.update(keyed, fresh: fresh)
        return aheadBehindCache.counts(keyed)
    }

    private func review(_ branch: BranchInfo, primary: String, tip: BranchTip?, counts: AheadBehind?) -> ReviewedBranch {
        let date = tip?.committerDate
        let days = date.map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 }
        let isPrimary = branch.name == primary
        // No commits missing from the primary is exactly what `branch --merged` reports.
        let isMerged = mergeStatusError == nil && counts?.ahead == 0
        let category: BranchCategory
        if !isPrimary && !branch.isHEAD && isMerged {
            category = .merged
        } else if !isPrimary && !branch.isHEAD, let days, days >= staleDays {
            category = .stale
        } else {
            category = .active
        }
        return ReviewedBranch(
            id: branch.id, name: branch.name, sha: branch.targetSHA, isCurrentBranch: branch.isHEAD,
            isPrimary: isPrimary, lastCommitDate: date, lastCommitSummary: tip?.summary ?? "",
            authorName: tip?.authorName ?? "", ahead: counts?.ahead ?? 0, behind: counts?.behind ?? 0,
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
