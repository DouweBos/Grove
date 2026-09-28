// Views/Repositories/WindowViewModel+Worktrees.swift
// Grove
//
// Nests git worktrees under their main repository in the browser.

import Foundation

extension WindowViewModel {

    /// Rows for the linked worktrees of `bookmark`, reusing a worktree's own bookmark when it has one.
    func worktreeRows(of bookmark: RepositoryBookmarkData) -> [RepositoryBookmarkData] {
        (worktreeIndex.worktreesByRepository[bookmark.path] ?? []).map { worktree in
            if var own = manager.bookmarks.first(where: { $0.path == worktree.path }) {
                own.displayName = worktree.name
                own.groupID = bookmark.groupID
                return own
            }
            return RepositoryBookmarkData(
                id: WorktreeIndex.syntheticID(forPath: worktree.path),
                path: worktree.path,
                displayName: worktree.name,
                addedDate: bookmark.addedDate,
                lastOpenedDate: nil,
                sortOrder: 0,
                groupID: bookmark.groupID
            )
        }
    }

    /// The linked worktree a row stands for, or nil for a regular repository. Reads only the index.
    func linkedWorktree(for bookmark: RepositoryBookmarkData) -> LinkedWorktree? {
        for worktrees in worktreeIndex.worktreesByRepository.values {
            if let match = worktrees.first(where: { $0.path == bookmark.path }) { return match }
        }
        return worktreeIndex.mainRepositoryByWorktree[bookmark.path].map {
            LinkedWorktree(path: bookmark.path, mainRepositoryPath: $0, branch: nil, isMissing: false)
        }
    }

    /// A bookmark or a worktree row by list ID.
    func row(withID id: UUID) -> RepositoryBookmarkData? {
        manager.bookmarks.first { $0.id == id } ?? worktreeRow(withID: id)
    }

    /// True when `bookmark` is only listed because it's a worktree, so bookmark-only actions don't apply.
    func isSyntheticWorktreeRow(_ bookmark: RepositoryBookmarkData) -> Bool {
        !manager.bookmarks.contains { $0.id == bookmark.id }
    }

    func worktreeRow(withID id: UUID) -> RepositoryBookmarkData? {
        manager.bookmarks.lazy.flatMap { self.worktreeRows(of: $0) }.first { $0.id == id }
    }

    /// Adds a repository; a worktree folder adds (or selects) its main repository instead of a separate entry.
    func addRepository(at url: URL, groupID: UUID? = nil) {
        let path = url.standardizedFileURL.path
        guard let main = WorktreeResolver.mainRepositoryPath(forWorktreeAt: path) else {
            addBookmark(path: path, displayName: url.lastPathComponent, groupID: groupID)
            refreshWorktrees()
            return
        }
        if !manager.bookmarks.contains(where: { $0.path == main }) {
            addBookmark(path: main, displayName: URL(fileURLWithPath: main).lastPathComponent, groupID: groupID)
        }
        refreshWorktrees()
        selectBookmark(manager.bookmarks.first { $0.path == path }?.id ?? WorktreeIndex.syntheticID(forPath: path))
    }

    /// Selects the bookmark for `path`, e.g. a worktree's main repository.
    func selectRepository(atPath path: String) {
        guard let bookmark = manager.bookmarks.first(where: { $0.path == path }) else { return }
        selectBookmark(bookmark.id)
    }

    /// `git worktree prune` on the main repository, clearing entries whose folders were deleted.
    func pruneWorktrees(ofRepositoryAt path: String) async {
        do {
            _ = try await GitShell(workingDirectory: URL(fileURLWithPath: path)).run(["worktree", "prune"])
            if let stale = selectedBookmark, isSyntheticWorktreeRow(stale) { selectBookmark(nil) }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshWorktrees()
    }
}
