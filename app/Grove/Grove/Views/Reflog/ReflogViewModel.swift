// Views/Reflog/ReflogViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - ReflogActionType

/// Categorised action derived from a ``ReflogEntry`` message prefix.
enum ReflogActionType: String, Sendable {
    case commit       = "commit"
    case commitAmend  = "commit (amend)"
    case checkout     = "checkout"
    case rebase       = "rebase"
    case merge        = "merge"
    case pull         = "pull"
    case push         = "push"
    case reset        = "reset"
    case cherryPick   = "cherry-pick"
    case other        = "other"

    // MARK: Display

    /// Human-readable label shown in the UI.
    var displayName: String {
        switch self {
        case .commit:       return "Commit"
        case .commitAmend:  return "Amend"
        case .checkout:     return "Checkout"
        case .rebase:       return "Rebase"
        case .merge:        return "Merge"
        case .pull:         return "Pull"
        case .push:         return "Push"
        case .reset:        return "Reset"
        case .cherryPick:   return "Cherry-pick"
        case .other:        return "Other"
        }
    }

    /// SF Symbol name representing this action.
    var systemImage: String {
        switch self {
        case .commit:       return "checkmark.circle"
        case .commitAmend:  return "pencil.circle"
        case .checkout:     return "arrow.left.arrow.right.circle"
        case .rebase:       return "arrow.triangle.2.circlepath"
        case .merge:        return "arrow.triangle.merge"
        case .pull:         return "arrow.down.circle"
        case .push:         return "arrow.up.circle"
        case .reset:        return "arrow.uturn.backward.circle"
        case .cherryPick:   return "heart.circle"
        case .other:        return "circle"
        }
    }

    // MARK: Parsing

    /// Infer the action type from a raw reflog message string.
    static func from(message: String) -> ReflogActionType {
        let lower = message.lowercased()
        if lower.hasPrefix("commit (amend)")    { return .commitAmend }
        if lower.hasPrefix("commit")            { return .commit }
        if lower.hasPrefix("checkout")          { return .checkout }
        if lower.hasPrefix("rebase")            { return .rebase }
        if lower.hasPrefix("merge")             { return .merge }
        if lower.hasPrefix("pull")              { return .pull }
        if lower.hasPrefix("push")              { return .push }
        if lower.hasPrefix("reset")             { return .reset }
        if lower.hasPrefix("cherry-pick")       { return .cherryPick }
        return .other
    }
}

// MARK: - ReflogViewModel

/// ViewModel for the Reflog browser view.
///
/// Loads ``ReflogEntry`` items from the repository and manages selection,
/// commit detail loading, and HEAD-reset actions.
@Observable
final class ReflogViewModel {

    // MARK: - State

    var entries: [ReflogEntry] = []
    var selectedEntry: ReflogEntry?
    var selectedCommit: CommitInfo?
    var isLoading = false
    var isLoadingDetail = false
    var errorMessage: String?

    // MARK: - Configuration

    /// Maximum number of reflog entries to load.
    var maxCount: Int = 500

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Reload all reflog entries from the repository.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await repository.reflog(maxCount: maxCount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Select a reflog entry and load the associated commit detail.
    func selectEntry(_ entry: ReflogEntry) async {
        selectedEntry = entry
        selectedCommit = nil
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            selectedCommit = try await repository.commitDetail(entry.newSHA)
        } catch {
            // Non-fatal: the entry may reference a SHA that no longer exists
            // (e.g. after a garbage collection). Show partial info from the entry.
            errorMessage = nil
        }
    }

    /// Reset HEAD to the commit referenced by `entry` using the given mode.
    func resetToEntry(_ entry: ReflogEntry, mode: ResetMode) async {
        do {
            try await repository.resetToCommit(entry.newSHA, mode: mode)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a new branch pointing at the commit referenced by `entry`.
    func createBranch(name: String, from entry: ReflogEntry) async {
        do {
            try await repository.createBranch(name: name, from: entry.newSHA, checkout: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Return the index of `entry` in the entries array (HEAD@{N} label).
    func index(of entry: ReflogEntry) -> Int {
        entries.firstIndex(where: { $0.id == entry.id }) ?? 0
    }

    /// Infer the action type for an entry.
    func actionType(for entry: ReflogEntry) -> ReflogActionType {
        ReflogActionType.from(message: entry.message)
    }
}
