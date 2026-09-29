// Views/Repositories/WindowViewModel+Switcher.swift
// Grove
//
// Quick repository switcher on the sidebar title, like GitHub's repository dropdown.

import Foundation

extension WindowViewModel {

    func showRepositorySwitcher() {
        guard !isBrowsing else { return }
        refreshWorktrees()
        isShowingRepositorySwitcher = true
    }

    func dismissRepositorySwitcher() { isShowingRepositorySwitcher = false }

    /// Bookmarks matching `query`, without worktrees nested in the browser: the open repository first, then the most recent.
    func repositorySwitcherItems(matching query: String) -> [RepositoryBookmarkData] {
        let current = currentBookmarkPath
        // Sessions cached in this window are fresher than the persisted "Last Opened" date.
        let sessionRank = Dictionary(uniqueKeysWithValues: sessionOrder.enumerated().map { ($1, $0) })
        let sorted = topLevelBookmarks.sorted { lhs, rhs in
            if (lhs.path == current) != (rhs.path == current) { return lhs.path == current }
            let lhsRank = sessionRank[lhs.path] ?? -1, rhsRank = sessionRank[rhs.path] ?? -1
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsDate = lhs.displayLastOpenedDate ?? .distantPast, rhsDate = rhs.displayLastOpenedDate ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sorted }
        let matches = sorted.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
        // Name prefixes beat matches mid-word, keeping recency order within each.
        return matches.filter { $0.displayName.lowercased().hasPrefix(trimmed.lowercased()) }
            + matches.filter { !$0.displayName.lowercased().hasPrefix(trimmed.lowercased()) }
    }

    /// The listed bookmark for the open repository: a linked worktree counts as its main repository when that's bookmarked.
    var currentBookmarkPath: String? {
        guard let path = openRepo?.path else { return nil }
        guard let main = WorktreeResolver.mainRepositoryPath(forWorktreeAt: path),
              manager.bookmarks.contains(where: { $0.path == main }) else { return path }
        return main
    }

    /// Opens another repository in this window on the same tab.
    func switchRepository(to bookmark: RepositoryBookmarkData) {
        dismissRepositorySwitcher()
        guard let current = openRepo, bookmark.path != currentBookmarkPath else { return }
        if let loaded = sessions[current.path] {
            setPendingSelection(RepositoryTab(item: loaded.session.selectedItem).item)
        }
        openBookmark(bookmark)
    }

    /// The switcher's footer: every repository in the local browser.
    func showAllRepositories() {
        dismissRepositorySwitcher()
        showLocalRepositories()
    }
}
