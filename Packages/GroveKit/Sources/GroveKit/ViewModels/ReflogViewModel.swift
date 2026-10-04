// ViewModels/ReflogViewModel.swift
// GroveKit

import Foundation
import Observation

// MARK: - ReflogActionType

/// Categorised action derived from a ``ReflogEntry`` message prefix.
public enum ReflogActionType: String, Sendable {
    case commit, commitAmend, checkout, rebase, merge, pull, push, reset, cherryPick, other

    public var displayName: String {
        switch self {
        case .commit: "Commit"
        case .commitAmend: "Amend"
        case .checkout: "Checkout"
        case .rebase: "Rebase"
        case .merge: "Merge"
        case .pull: "Pull"
        case .push: "Push"
        case .reset: "Reset"
        case .cherryPick: "Cherry-pick"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .commit: "checkmark.circle"
        case .commitAmend: "pencil.circle"
        case .checkout: "arrow.left.arrow.right.circle"
        case .rebase: "arrow.triangle.2.circlepath"
        case .merge: "arrow.triangle.merge"
        case .pull: "arrow.down.circle"
        case .push: "arrow.up.circle"
        case .reset: "arrow.uturn.backward.circle"
        case .cherryPick: "arrow.turn.down.right"
        case .other: "circle"
        }
    }

    public static func from(message: String) -> ReflogActionType {
        let lower = message.lowercased()
        if lower.hasPrefix("commit (amend)") { return .commitAmend }
        if lower.hasPrefix("commit") { return .commit }
        if lower.hasPrefix("checkout") { return .checkout }
        if lower.hasPrefix("rebase") { return .rebase }
        if lower.hasPrefix("merge") { return .merge }
        if lower.hasPrefix("pull") { return .pull }
        if lower.hasPrefix("push") { return .push }
        if lower.hasPrefix("reset") { return .reset }
        if lower.hasPrefix("cherry-pick") { return .cherryPick }
        return .other
    }
}

// MARK: - ReflogViewModel

@MainActor
@Observable
public final class ReflogViewModel {

    public struct PendingReset: Identifiable {
        public let entry: ReflogEntry
        public let index: Int
        public let mode: ResetMode
        public var id: String { "\(entry.id)-\(mode)" }
    }

    // MARK: - State

    public private(set) var entries: [ReflogEntry] = []
    public private(set) var selectedEntry: ReflogEntry?
    public private(set) var selectedCommit: CommitInfo?
    public private(set) var isLoading = false
    public private(set) var isLoadingDetail = false
    public internal(set) var errorMessage: String?
    public var pendingReset: PendingReset?
    /// Entry the Create Branch sheet is open for.
    public internal(set) var branchSource: ReflogEntry?

    /// Maximum number of reflog entries to load.
    let maxCount = 500

    public var onRepositoryChanged: (() async -> Void)?
    public var undoManager: GitUndoManager?

    public let repository: any GitRepositoryProtocol
    // Keyed by SHA: commit details are immutable and verifying signatures makes each lookup slow.
    @ObservationIgnored private var commitCache = LRUCache<String, CommitInfo>(capacity: 100)

    public init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Loading

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await repository.reflog(maxCount: maxCount)
            // Parser ids repeat for identical moves (e.g. two stashes); number from the oldest end so ids survive new entries.
            entries = loaded.enumerated().map { index, entry in
                ReflogEntry(id: "\(loaded.count - 1 - index)-\(entry.newSHA)", oldSHA: entry.oldSHA, newSHA: entry.newSHA,
                            committerName: entry.committerName, committerEmail: entry.committerEmail,
                            date: entry.date, message: entry.message)
            }
            if let selected = selectedEntry, !entries.contains(where: { $0.id == selected.id }) {
                selectedEntry = nil
                selectedCommit = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ entry: ReflogEntry) async {
        guard entry.id != selectedEntry?.id else { return }
        selectedEntry = entry
        if let cached = commitCache.value(for: entry.newSHA) {
            selectedCommit = cached
            isLoadingDetail = false
            return
        }
        selectedCommit = nil
        isLoadingDetail = true
        // A missing commit (e.g. after gc) is expected; the panel shows entry data only.
        let commit = try? await repository.commitDetail(entry.newSHA)
        if let commit { commitCache.insert(commit, for: entry.newSHA) }
        guard selectedEntry?.id == entry.id else { return }
        selectedCommit = commit
        isLoadingDetail = false
    }

    // MARK: - Reset

    public func requestReset(to entry: ReflogEntry, mode: ResetMode) {
        pendingReset = PendingReset(entry: entry, index: index(of: entry), mode: mode)
    }

    public func cancelReset() {
        pendingReset = nil
    }

    /// Takes the dialog item because the dialog clears `pendingReset` before running its action.
    public func confirmReset(_ pending: PendingReset) async {
        pendingReset = nil
        let previousHead = entries.first?.newSHA
        do {
            try await repository.resetToCommit(pending.entry.newSHA, mode: pending.mode)
            if let previousHead, pending.mode != .hard {
                recordResetUndo(from: previousHead, to: pending.entry.newSHA, mode: pending.mode)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
        await onRepositoryChanged?()
    }

    // MARK: - Create Branch

    public func beginCreateBranch(from entry: ReflogEntry) {
        branchSource = entry
    }

    public func cancelCreateBranch() {
        branchSource = nil
    }

    public func createBranch(named rawName: String, checkout: Bool) async {
        guard let entry = branchSource else { return }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard RefName.isValid(name) else { return }
        branchSource = nil
        do {
            try await repository.createBranch(name: name, from: entry.newSHA, checkout: checkout)
            if !checkout {
                undoManager?.record(GitUndoManager.createBranchAction(branchName: name, repository: repository))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await onRepositoryChanged?()
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Derived

    public func index(of entry: ReflogEntry) -> Int {
        entries.firstIndex(where: { $0.id == entry.id }) ?? 0
    }

    public func actionType(for entry: ReflogEntry) -> ReflogActionType {
        ReflogActionType.from(message: entry.message)
    }

    private func recordResetUndo(from oldHead: String, to newHead: String, mode: ResetMode) {
        let repository = repository
        undoManager?.record(GitUndoManager.GitAction(
            description: "Reset to \(newHead.prefix(7))",
            undoCommand: { try await repository.resetToCommit(oldHead, mode: mode) },
            redoCommand: { try await repository.resetToCommit(newHead, mode: mode) }
        ))
    }
}
