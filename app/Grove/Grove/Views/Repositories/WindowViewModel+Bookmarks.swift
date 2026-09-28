// Views/Repositories/WindowViewModel+Bookmarks.swift
// Grove
//
// Renaming and sorting in the repository browser.

import Foundation

extension WindowViewModel {

    func requestDelete(_ bookmark: RepositoryBookmarkData) { bookmarkPendingDelete = bookmark }

    func cancelDelete() { bookmarkPendingDelete = nil }

    /// Removes the repository from the list, and with `movingToTrash` its folder from disk too.
    func confirmDelete(movingToTrash: Bool) {
        guard let bookmark = bookmarkPendingDelete else { return }
        bookmarkPendingDelete = nil
        if movingToTrash {
            if openRepo?.path == bookmark.path { closeRepository() }
            sessions[bookmark.path]?.session.stop()
            setSession(nil, for: bookmark.path)
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: bookmark.path), resultingItemURL: nil)
            } catch {
                errorMessage = "Couldn't move \(bookmark.displayName) to the Trash: \(error.localizedDescription)"
                return
            }
        }
        removeBookmark(bookmark)
    }

    func showRenameBookmarkDialog(_ bookmark: RepositoryBookmarkData) { groupEditor = .renameRepository(bookmark) }

    func renameBookmark(_ bookmark: RepositoryBookmarkData, to name: String) {
        do {
            try manager.renameBookmark(id: bookmark.id, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sorts the repositories of one group, or the ungrouped ones when `groupID` is nil.
    func sortBookmarksByName(inGroup groupID: UUID?) {
        let members = manager.bookmarks.filter { $0.groupID == groupID }
        do {
            try manager.orderBookmarks(Self.byName(members, \.displayName).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sortGroupsByName() {
        do {
            try manager.orderGroups(Self.byName(manager.bookmarkGroups, \.name).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func byName<T>(_ items: [T], _ name: KeyPath<T, String>) -> [T] {
        items.sorted { $0[keyPath: name].localizedStandardCompare($1[keyPath: name]) == .orderedAscending }
    }
}
