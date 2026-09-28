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
    func sortBookmarks(inGroup groupID: UUID?, by key: BookmarkSortKey) {
        let members = manager.bookmarks.filter { $0.groupID == groupID }
        do {
            try manager.orderBookmarks(Self.sorted(members, by: key).map(\.id))
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

    /// Dates sort newest first; ties and missing dates fall back to name order.
    private static func sorted(_ bookmarks: [RepositoryBookmarkData], by key: BookmarkSortKey) -> [RepositoryBookmarkData] {
        let named = byName(bookmarks, \.displayName)
        let date: (RepositoryBookmarkData) -> Date?
        switch key {
        case .name: return named
        case .lastOpened: date = { $0.displayLastOpenedDate }
        case .dateAdded: date = { $0.addedDate }
        }
        return named.sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) }
    }

    private static func byName<T>(_ items: [T], _ name: KeyPath<T, String>) -> [T] {
        items.sorted { $0[keyPath: name].localizedStandardCompare($1[keyPath: name]) == .orderedAscending }
    }
}

enum BookmarkSortKey: CaseIterable {
    case name, lastOpened, dateAdded

    var title: String {
        switch self {
        case .name: "Name"
        case .lastOpened: "Last Opened"
        case .dateAdded: "Date Added"
        }
    }
}
