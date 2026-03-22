// Views/Stashes/StashesViewModel.swift
// Grove

import Foundation
import Observation

/// ViewModel for the Stashes view.
@Observable
final class StashesViewModel {

    // MARK: - State

    var stashes: [StashEntry] = []
    var selectedStash: StashEntry?
    var stashDiffs: [FileDiff] = []
    var selectedFileDiff: FileDiff?
    var isLoading = false
    var isLoadingDiff = false
    var errorMessage: String?

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Actions

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            stashes = try await repository.stashes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectStash(_ stash: StashEntry) async {
        selectedStash = stash
        selectedFileDiff = nil
        stashDiffs = []
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            // Stash is stored as a commit — diff using the stash SHA
            stashDiffs = try await repository.diffForCommit(stash.sha)
        } catch {
            // Fall back to empty — stash diff will show nothing
            errorMessage = error.localizedDescription
        }
    }

    func selectFileDiff(byPath path: String?) {
        selectedFileDiff = path.flatMap { p in
            stashDiffs.first { $0.path == p }
        }
    }

    func apply(stash: StashEntry, drop: Bool = false) async {
        do {
            try await repository.stashApply(index: stash.id, drop: drop)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pop(stash: StashEntry) async {
        await apply(stash: stash, drop: true)
    }

    func drop(stash: StashEntry) async {
        do {
            try await repository.stashDrop(index: stash.id)
            if selectedStash?.id == stash.id {
                selectedStash = nil
                stashDiffs = []
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
