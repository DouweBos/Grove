// Views/Reflog/ReflogViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - ReflogActionType

/// Categorised action derived from a ``ReflogEntry`` message prefix.
enum ReflogActionType: String, Sendable {
    case commit, commitAmend, checkout, rebase, merge, pull, push, reset, cherryPick, other

    var displayName: String {
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

    var systemImage: String {
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

    static func from(message: String) -> ReflogActionType {
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
final class ReflogViewModel {

    struct PendingReset: Identifiable {
        let entry: ReflogEntry
        let index: Int
        let mode: ResetMode
        var id: String { "\(entry.id)-\(mode)" }
    }

    // MARK: - State

    private(set) var entries: [ReflogEntry] = []
    private(set) var selectedEntry: ReflogEntry?
    private(set) var selectedCommit: CommitInfo?
    private(set) var isLoading = false
    private(set) var isLoadingDetail = false
    var errorMessage: String?
    var pendingReset: PendingReset?
    /// Entry the Create Branch sheet is open for.
    var branchSource: ReflogEntry?

    /// Maximum number of reflog entries to load.
    let maxCount = 500

    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Loading

    func refresh() async {
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

    func select(_ entry: ReflogEntry) async {
        guard entry.id != selectedEntry?.id else { return }
        selectedEntry = entry
        selectedCommit = nil
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        // A missing commit (e.g. after gc) is expected; the panel shows entry data only.
        let commit = try? await repository.commitDetail(entry.newSHA)
        if selectedEntry?.id == entry.id { selectedCommit = commit }
    }

    // MARK: - Reset

    func requestReset(to entry: ReflogEntry, mode: ResetMode) {
        pendingReset = PendingReset(entry: entry, index: index(of: entry), mode: mode)
    }

    func cancelReset() {
        pendingReset = nil
    }

    /// Takes the dialog item because the dialog clears `pendingReset` before running its action.
    func confirmReset(_ pending: PendingReset) async {
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

    func beginCreateBranch(from entry: ReflogEntry) {
        branchSource = entry
    }

    func cancelCreateBranch() {
        branchSource = nil
    }

    func createBranch(named rawName: String, checkout: Bool) async {
        guard let entry = branchSource else { return }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard Self.isValidBranchName(name) else { return }
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

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Derived

    func index(of entry: ReflogEntry) -> Int {
        entries.firstIndex(where: { $0.id == entry.id }) ?? 0
    }

    func actionType(for entry: ReflogEntry) -> ReflogActionType {
        ReflogActionType.from(message: entry.message)
    }

    /// Mirrors the common `git check-ref-format` rules closely enough for inline validation.
    static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
              !name.hasSuffix("."), !name.hasSuffix(".lock"), !name.contains(".."), !name.contains("@{"),
              !name.contains("//") else { return false }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\").union(.controlCharacters)
        return name.unicodeScalars.allSatisfy { !forbidden.contains($0) }
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
