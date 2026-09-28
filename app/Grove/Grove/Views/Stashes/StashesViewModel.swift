// Views/Stashes/StashesViewModel.swift
// Grove

import Foundation
import Observation

@MainActor
@Observable
final class StashesViewModel {

    enum Operation: String, Identifiable {
        case apply, pop, drop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .apply: "Apply"
            case .pop: "Pop"
            case .drop: "Drop"
            }
        }
    }

    struct PendingOperation: Identifiable {
        let operation: Operation
        let stash: StashEntry
        var id: String { "\(operation.rawValue)-\(stash.id)" }
    }

    // MARK: - State

    var stashes: [StashEntry] = []
    private(set) var selectedStash: StashEntry?
    private(set) var stashDiffs: [FileDiff] = []
    private(set) var selectedFilePath: String?
    private(set) var isLoading = false
    private(set) var isLoadingDiff = false
    private(set) var isPerforming = false
    var errorMessage: String?
    var pendingOperation: PendingOperation?

    /// Set by the session so a mutation refreshes every view.
    var onRepositoryChanged: (() async -> Void)?
    /// Set by the session to select a commit in History.
    var onRevealInHistory: ((String) -> Void)?

    let repository: any GitRepositoryProtocol
    // A stash commit is immutable, so its diff is cached by SHA; indices shift but SHAs don't.
    @ObservationIgnored private var diffCache = LRUCache<String, [FileDiff]>(capacity: 30)

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stashes = try await repository.stashes()
            // Stash indices shift after pop/drop; re-resolve the selection by SHA.
            if let selected = selectedStash {
                if let match = stashes.first(where: { $0.sha == selected.sha }) {
                    selectedStash = match
                } else {
                    clearSelection()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ stash: StashEntry) async {
        guard stash.sha != selectedStash?.sha else { return }
        selectedStash = stash
        if let cached = diffCache.value(for: stash.sha) {
            stashDiffs = cached
            selectedFilePath = cached.first?.path
            isLoadingDiff = false
            return
        }
        stashDiffs = []
        selectedFilePath = nil
        isLoadingDiff = true
        defer { if selectedStash?.sha == stash.sha { isLoadingDiff = false } }
        do {
            let diffs = try await repository.stashDiff(index: stash.id)
            diffCache.insert(diffs, for: stash.sha)
            guard selectedStash?.sha == stash.sha else { return }
            stashDiffs = diffs
            selectedFilePath = diffs.first?.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectFile(_ file: FileDiff) {
        selectedFilePath = file.path
    }

    // MARK: - Operations

    func request(_ operation: Operation, on stash: StashEntry) {
        pendingOperation = PendingOperation(operation: operation, stash: stash)
    }

    func cancelPendingOperation() {
        pendingOperation = nil
    }

    /// Takes the dialog item because the dialog clears `pendingOperation` before running its action.
    func confirm(_ pending: PendingOperation) async {
        pendingOperation = nil
        isPerforming = true
        defer { isPerforming = false }
        do {
            switch pending.operation {
            case .apply: try await repository.stashApply(index: pending.stash.id, drop: false)
            case .pop: try await repository.stashApply(index: pending.stash.id, drop: true)
            case .drop: try await repository.stashDrop(index: pending.stash.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
        await onRepositoryChanged?()
    }

    /// The stash commit itself isn't on any branch; its first parent is the commit it was made on.
    func revealBaseInHistory(_ stash: StashEntry) async {
        do {
            guard let base = try await repository.commitDetail(stash.sha).parentIDs.first else { return }
            onRevealInHistory?(base)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func clearSelection() {
        selectedStash = nil
        stashDiffs = []
        selectedFilePath = nil
    }
}
