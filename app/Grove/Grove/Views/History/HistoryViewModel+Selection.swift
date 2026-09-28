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
        while commit(withID: id) == nil {
            // Another read (a reload after refs arrived) may be running; paging waits for it.
            if isLoading {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            guard hasMore else { break }
            let before = commits.count
            await loadMore()
            if commits.count == before, !isLoading { break }
        }
        guard let commit = commit(withID: id) else { return false }
        setSearchText("")
        select(commit)
        return true
    }

    /// Whether this history holds `sha`, loaded yet or not.
    func contains(_ sha: String) async -> Bool {
        if commit(withID: sha) != nil { return true }
        for revision in logRevisions where await repository.isAncestor(sha, of: revision) {
            return true
        }
        return false
    }

    /// Loads the log if it hasn't been, then selects `sha`, paging it in.
    func reveal(_ sha: String) async {
        await loadIfNeeded()
        if await !selectCommit(id: sha) {
            errorMessage = "Commit \(sha.prefix(7)) isn't in \(filterBranch ?? headBranchName ?? "HEAD")'s history."
        }
    }
}
