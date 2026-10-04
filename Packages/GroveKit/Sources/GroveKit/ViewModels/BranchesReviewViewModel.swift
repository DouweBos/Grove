// ViewModels/BranchesReviewViewModel.swift
// GroveKit

import Foundation
import Observation

public enum BranchCategory: String, CaseIterable, Sendable {
    case merged = "Merged"
    case stale = "Stale"
    case active = "Active"
}

public struct ReviewedBranch: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let sha: String
    public let isCurrentBranch: Bool
    let isPrimary: Bool
    public let lastCommitDate: Date?
    public let lastCommitSummary: String
    public let authorName: String
    /// Relative to the primary branch.
    public let ahead: Int
    public let behind: Int
    public let category: BranchCategory
    public let daysSinceLastCommit: Int?
    /// Another worktree has it checked out, so git won't delete it.
    public let worktreePath: String?

    public var isDeletable: Bool { !isCurrentBranch && !isPrimary && worktreePath == nil }
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
public final class BranchesReviewViewModel {

    public struct PendingDelete: Identifiable {
        public let branches: [ReviewedBranch]
        public var id: [String] { branches.map(\.id) }
        /// Unmerged branches need `-D`, which loses their unique commits.
        public var needsForce: Bool { branches.contains { $0.category != .merged } }
    }

    // MARK: - State

    public private(set) var branches: [ReviewedBranch] = []
    public private(set) var primaryBranch = "main"
    public private(set) var selectedIDs: Set<String> = []
    public private(set) var categoryFilter: BranchCategory?
    public private(set) var isLoading = false
    private(set) var isDeleting = false
    public var errorMessage: String?
    /// Set when the merged-branches check failed; deleting stays off so unmerged branches aren't force-deleted as merged.
    // TODO: Check this error state and the grouped-delete undo in the running app; only unit tests cover them.
    public private(set) var mergeStatusError: String?
    public var pendingDelete: PendingDelete?
    private var aheadBehindCache = AheadBehindCache()

    public var onRepositoryChanged: (() async -> Void)?
    /// Reports each action this view model runs, e.g. to the app's telemetry.
    @ObservationIgnored public var onAction: GroveKitActionHandler?
    public var undoManager: GitUndoManager?

    public let repository: any GitRepositoryProtocol

    /// The session's shared refs; without them (previews, tests) branches are read directly.
    private let refs: RepositoryRefs?

    public init(repository: any GitRepositoryProtocol, refs: RepositoryRefs? = nil) {
        self.repository = repository
        self.refs = refs
    }

    public var staleDays: Int { ViewModelPreferences.staleBranchDays }

    // MARK: - Derived

    public var visibleBranches: [ReviewedBranch] {
        guard let categoryFilter else { return branches }
        return branches.filter { $0.category == categoryFilter }
    }

    public func count(of category: BranchCategory) -> Int {
        branches.filter { $0.category == category }.count
    }

    public var canDelete: Bool { mergeStatusError == nil && !isDeleting && !isLoading }

    public var selectedBranches: [ReviewedBranch] {
        branches.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Loading

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let local = try await localBranches()
            let primary = Self.primaryBranchName(from: local)
            let tips = Dictionary(try await repository.branchTips().map { ($0.name, $0) }) { first, _ in first }
            let counts = await aheadBehindCounts(for: local, primary: primary, tips: tips)
            let worktrees = await worktreePaths()
            let reviewed = local.map {
                review($0, primary: primary, tip: tips[$0.name], counts: counts[$0.name],
                       worktreePath: $0.isHEAD ? nil : worktrees[$0.name])
            }
            primaryBranch = primary
            branches = reviewed.sorted(by: Self.displayOrder)
            selectedIDs.formIntersection(branches.filter(\.isDeletable).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localBranches() async throws -> [BranchInfo] {
        guard let refs else { return try await repository.localBranches() }
        await refs.settled()
        return refs.localBranches
    }

    /// Branch name to the worktree that has it checked out.
    private func worktreePaths() async -> [String: String] {
        let worktrees: [WorktreeInfo]
        if let refs { worktrees = refs.worktrees } else { worktrees = (try? await repository.worktrees()) ?? [] }
        return Dictionary(worktrees.compactMap { worktree in worktree.branch.map { ($0, worktree.path) } }) { first, _ in first }
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

    private func review(_ branch: BranchInfo, primary: String, tip: BranchTip?, counts: AheadBehind?,
                        worktreePath: String?) -> ReviewedBranch {
        let date = tip?.committerDate
        let days = date.map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 }
        let isPrimary = branch.name == primary
        // Checked out somewhere, like HEAD, so it's never suggested for cleanup.
        let isInUse = branch.isHEAD || worktreePath != nil
        // No commits missing from the primary is exactly what `branch --merged` reports.
        let isMerged = mergeStatusError == nil && counts?.ahead == 0
        let category: BranchCategory
        if !isPrimary && !isInUse && isMerged {
            category = .merged
        } else if !isPrimary && !isInUse, let days, days >= staleDays {
            category = .stale
        } else {
            category = .active
        }
        return ReviewedBranch(
            id: branch.id, name: branch.name, sha: branch.targetSHA, isCurrentBranch: branch.isHEAD,
            isPrimary: isPrimary, lastCommitDate: date, lastCommitSummary: tip?.summary ?? "",
            authorName: tip?.authorName ?? "", ahead: counts?.ahead ?? 0, behind: counts?.behind ?? 0,
            category: category, daysSinceLastCommit: days, worktreePath: worktreePath
        )
    }

    // MARK: - Selection & Filter

    public func toggleSelection(_ branch: ReviewedBranch) {
        guard branch.isDeletable else { return }
        if selectedIDs.contains(branch.id) { selectedIDs.remove(branch.id) } else { selectedIDs.insert(branch.id) }
    }

    public func selectAllVisible() {
        selectedIDs.formUnion(visibleBranches.filter(\.isDeletable).map(\.id))
    }

    public func clearSelection() {
        selectedIDs.removeAll()
    }

    public func toggleFilter(_ category: BranchCategory) {
        categoryFilter = categoryFilter == category ? nil : category
    }

    // MARK: - Delete

    public func requestDelete(_ branches: [ReviewedBranch]) {
        let deletable = branches.filter(\.isDeletable)
        guard canDelete, !deletable.isEmpty else { return }
        pendingDelete = PendingDelete(branches: deletable)
    }

    public func cancelDelete() {
        pendingDelete = nil
    }

    /// Takes the dialog item because the dialog clears `pendingDelete` before running its action.
    public func confirmDelete(_ pending: PendingDelete) async {
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
        onAction?(.branchDelete, failures.isEmpty)
        await refresh()
        await onRepositoryChanged?()
    }

    public func dismissError() {
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
