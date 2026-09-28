// Views/Repositories/WindowViewModel+Snapshots.swift
// Grove
//
// Info-panel snapshots, kept per repository so reselecting one shows its last state while it refreshes.

import Foundation

extension WindowViewModel {

    func snapshot(for bookmark: RepositoryBookmarkData) -> RepositorySnapshot? {
        repositorySnapshots[bookmark.path]
    }

    func isRefreshingSnapshot(for bookmark: RepositoryBookmarkData) -> Bool {
        refreshingSnapshotPaths.contains(bookmark.path)
    }

    func snapshotError(for bookmark: RepositoryBookmarkData) -> String? {
        snapshotErrors[bookmark.path]
    }

    /// Re-reads branch, status, remotes and recent commits; the previous snapshot stays visible meanwhile.
    func refreshSnapshot(for bookmark: RepositoryBookmarkData) async {
        let path = bookmark.path
        guard FileManager.default.fileExists(atPath: path), !refreshingSnapshotPaths.contains(path) else { return }
        setSnapshotRefreshing(true, for: path)
        defer { setSnapshotRefreshing(false, for: path) }
        do {
            // Inspect, not open: merely selecting a bookmark shouldn't bump "Last Opened".
            let repo = try await manager.inspectRepository(at: URL(fileURLWithPath: path))
            async let entries = repo.status()
            async let remotes = repo.remotes()
            async let commits = repo.log(maxCount: 6, skip: 0, branch: nil)
            let changed = try await entries.filter { $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified }.count
            storeSnapshot(RepositorySnapshot(
                branch: repo.currentBranch,
                changedCount: changed,
                remotes: (try? await remotes) ?? [],
                commits: (try? await commits) ?? []
            ), for: path)
        } catch {
            storeSnapshotError("Grove couldn't read this repository: \(error.localizedDescription)", for: path)
        }
    }
}
