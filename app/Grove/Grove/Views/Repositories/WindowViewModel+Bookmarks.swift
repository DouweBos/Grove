// Views/Repositories/WindowViewModel+Bookmarks.swift
// Grove
//
// Renaming and sorting in the repository browser.

import Foundation

extension WindowViewModel {

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
