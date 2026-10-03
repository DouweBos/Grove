// Views/CI/CIViewModel+Notifications.swift
// Grove

import Foundation
import GroveKit

extension CIViewModel {

    /// Watches are keyed by this, and a clicked notification opens it.
    var repositoryPath: String { repository.path.path }

    func isWatching(_ run: CIRun) -> Bool { watcher.isWatching(run.id, in: repositoryPath) }

    /// Notify when an active run finishes, or stop doing so.
    func toggleNotification(for run: CIRun) {
        if isWatching(run) {
            watcher.stopWatching(run.id, in: repositoryPath)
        } else {
            watcher.watch(run, in: repositoryPath, repository: repository)
        }
    }

    /// Selects `runID`, e.g. from its notification; clears the filters when they hide it.
    func reveal(runID: Int) async {
        if !runs.contains(where: { $0.id == runID }) {
            await clearFilters()
            if !runs.contains(where: { $0.id == runID }), let run = try? await repository.ciRun(id: runID) {
                await insert(run)
            }
        }
        guard let run = runs.first(where: { $0.id == runID }) else { return }
        await select(run)
    }
}
