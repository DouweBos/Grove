// Views/History/HistoryViewModel+Selection.swift
// Grove

import Foundation

extension HistoryViewModel {

    /// Selected commits in list order, newest first.
    var selectedCommits: [CommitInfo] {
        commits.filter { selection.contains($0.id) }
    }

    func isSelected(_ commit: CommitInfo) -> Bool {
        selection.contains(commit.id)
    }

    /// Click, Shift-click range and Cmd-click toggle over the visible (filtered) list.
    func click(_ commit: CommitInfo, extend: Bool, toggle: Bool) {
        var next = selection
        next.click(commit.id, in: filteredCommits.map(\.id), extend: extend, toggle: toggle)
        applySelection(next)
    }

    /// Arrow-key navigation through the visible list; Shift grows the range.
    func selectAdjacent(offset: Int, extend: Bool = false) {
        let visible = filteredCommits
        guard !visible.isEmpty else { return }
        var next = selection
        next.move(by: offset, in: visible.map(\.id), extend: extend)
        applySelection(next)
        guard let index = visible.firstIndex(where: { $0.id == next.focus }) else { return }
        let ahead = index + (offset < 0 ? -1 : 1)
        if visible.indices.contains(ahead) { prefetchDiff(for: visible[ahead]) }
    }

    /// Selects a commit by SHA, e.g. a parent from the detail header, paging it in if needed.
    @discardableResult
    func selectCommit(id: String) async -> Bool {
        while commit(withID: id) == nil, hasMore {
            let before = commits.count
            await loadMore()
            if commits.count == before { break }
        }
        guard let commit = commit(withID: id) else { return false }
        setSearchText("")
        select(commit)
        return true
    }
}
