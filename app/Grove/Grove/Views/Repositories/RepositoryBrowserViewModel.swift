// Views/Repositories/RepositoryBrowserViewModel.swift
// Grove
//
// ViewModel for the repository browser window.
// Bridges the RepositoryManagerProtocol to the SwiftUI view layer.

import Foundation
import Observation
import SwiftUI

// MARK: - RepositoryBrowserViewModel

/// Drives the repository browser UI.
///
/// Holds selection state, sheet presentation flags, and delegates
/// all persistence operations to the injected ``RepositoryManagerProtocol``.
@MainActor
@Observable
final class RepositoryBrowserViewModel {

    // MARK: Dependencies

    let manager: any RepositoryManagerProtocol

    // MARK: Selection

    /// Currently selected group in the sidebar.
    var selectedGroupID: UUID?
    /// Currently selected bookmark.
    var selectedBookmarkID: UUID?

    // MARK: Navigation

    /// When set, the browser window navigates in-place to show this repository.
    var openedReference: RepositoryReference?

    // MARK: Sheet Presentation

    var isShowingCloneDialog = false
    var isShowingAddDialog = false
    var isShowingCreateDialog = false

    // MARK: Error State

    var errorMessage: String?

    // MARK: Computed

    var selectedGroup: BookmarkGroupData? {
        guard let id = selectedGroupID else { return nil }
        return manager.bookmarkGroups.first(where: { $0.id == id })
    }

    var selectedBookmark: RepositoryBookmarkData? {
        guard let id = selectedBookmarkID else { return nil }
        return manager.bookmarks.first(where: { $0.id == id })
    }

    /// Bookmarks that belong to a specific group.
    func bookmarks(for groupID: UUID) -> [RepositoryBookmarkData] {
        manager.bookmarks
            .filter { $0.groupID == groupID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Bookmarks that don't belong to any group.
    var ungroupedBookmarks: [RepositoryBookmarkData] {
        manager.bookmarks
            .filter { $0.groupID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        // Select the first group by default.
        self.selectedGroupID = manager.bookmarkGroups.first?.id
    }

    // MARK: Actions

    func openSelectedBookmark() {
        guard let bookmark = selectedBookmark else { return }
        openedReference = RepositoryReference(path: bookmark.path)
    }

    func openBookmark(_ bookmark: RepositoryBookmarkData) {
        openedReference = RepositoryReference(path: bookmark.path)
    }

    func closeRepository() {
        openedReference = nil
    }

    func addBookmark(path: String, displayName: String) {
        do {
            try manager.addBookmark(path: path, displayName: displayName, groupID: selectedGroupID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBookmark(_ bookmark: RepositoryBookmarkData) {
        do {
            try manager.removeBookmark(id: bookmark.id)
            if selectedBookmarkID == bookmark.id {
                selectedBookmarkID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGroup(name: String) {
        do {
            let group = try manager.createGroup(name: name)
            selectedGroupID = group.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGroup(_ group: BookmarkGroupData) {
        do {
            try manager.deleteGroup(id: group.id)
            if selectedGroupID == group.id {
                selectedGroupID = manager.bookmarkGroups.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveBookmark(_ bookmark: RepositoryBookmarkData, toGroup groupID: UUID?) {
        do {
            try manager.moveBookmark(id: bookmark.id, toGroup: groupID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleDroppedURLs(_ urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            addBookmark(path: url.path, displayName: url.lastPathComponent)
        }
    }
}
