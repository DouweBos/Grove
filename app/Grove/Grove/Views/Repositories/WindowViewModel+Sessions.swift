// Views/Repositories/WindowViewModel+Sessions.swift
// Grove
//
// Keeps the last few repository sessions so returning to one shows its last state at once.

import Foundation
import os

extension WindowViewModel {

    /// Sessions kept in memory, the open one included; the least recently opened beyond this stops.
    static let cachedSessionLimit = 4

    /// Runs this window in another worktree of the same repository, keeping the current tab.
    /// The old worktree's session pauses so each repository fetches and watches only once.
    func switchWorktree(to path: String) {
        guard let current = openRepo, current.path != path else { return }
        recordNavigation(to: .repository(path: path, item: nil))
        if let loaded = sessions[current.path] {
            setPendingSelection(RepositoryTab(item: loaded.session.selectedItem).item)
        }
        pauseCurrentSession()
        openReference(RepositoryReference(path: path))
    }

    /// Leaving pauses the watcher and auto-fetch; the session stays cached for a quick return.
    func closeRepository() {
        pauseCurrentSession()
        openRepo = nil
    }

    func pauseCurrentSession() {
        guard let path = openRepo?.path else { return }
        sessions[path]?.session.pause()
    }

    // MARK: Loading

    /// Resumes a cached session (refreshing in the background) or opens a new one.
    func loadSessionIfNeeded(for ref: RepositoryReference) {
        let path = ref.path
        if let loaded = sessions[path] {
            setSession(loaded, for: path)
            if let pendingSelection {
                loaded.session.restoreSelection(pendingSelection)
                setPendingSelection(nil)
            }
            Task { await loaded.session.start() }
            return
        }
        guard sessionErrors[path] == nil else { return }
        Logger.ui.info("Opening repository for \(path, privacy: .public)")
        Task {
            let url = URL(fileURLWithPath: path)
            do {
                // Through the manager so the bookmark's "Last Opened" date updates.
                let repo = try await manager.openRepository(at: url)
                let session = RepositorySession(repository: repo)
                session.sidebarVM.onSwitchWorktree = { [weak self] path in self?.switchWorktree(to: path) }
                if let pendingSelection {
                    session.restoreSelection(pendingSelection)
                    setPendingSelection(nil)
                }
                setSession(LoadedSession(repository: repo, session: session), for: path)
                evictSessions()
                // The window may have moved on while this repository was opening.
                guard openRepo?.path == path else { return }
                await session.start()
                Logger.ui.info("Repository ready: \(ref.displayName, privacy: .public)")
            } catch {
                Logger.ui.error("Failed to open repository \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                setSessionError(error.localizedDescription, for: path)
            }
        }
    }

    /// Stops and drops the least recently opened sessions beyond the limit, never the open one.
    private func evictSessions() {
        var excess = sessionOrder.count - Self.cachedSessionLimit
        for path in sessionOrder where excess > 0 && path != openRepo?.path {
            sessions[path]?.session.stop()
            setSession(nil, for: path)
            excess -= 1
        }
    }

    func stopAllSessions() {
        for (_, loaded) in sessions {
            loaded.session.stop()
        }
    }
}
