// Views/Repositories/RepositoryBrowserViewModel.swift
// Grove
//
// ViewModel for the repository browser tab.

import Foundation
import Observation

// MARK: - RepositoryBrowserViewModel

/// Drives the repository browser UI.
///
/// Opening a repository calls the injected `onOpenRepository` closure,
/// which the host view uses to add a tab in the window's tab manager.
@MainActor
@Observable
final class RepositoryBrowserViewModel {

    // MARK: Dependencies

    let manager: any RepositoryManagerProtocol

    // MARK: Selection

    var selectedGroupID: UUID?
    var selectedBookmarkID: UUID?

    // MARK: Sheet Presentation

    var isShowingCloneDialog = false
    var isShowingAddDialog = false
    var isShowingCreateDialog = false

    // MARK: Source Mode

    /// Which source the sidebar is showing: local bookmarks or cloud repos.
    var sourceMode: BrowserSourceMode = .local

    // MARK: Error State

    var errorMessage: String?

    // MARK: Navigation

    /// Called by the host to navigate to a repository.
    var onOpenRepo: ((RepositoryReference) -> Void)?

    // MARK: Computed

    var selectedGroup: BookmarkGroupData? {
        guard let id = selectedGroupID else { return nil }
        return manager.bookmarkGroups.first(where: { $0.id == id })
    }

    var selectedBookmark: RepositoryBookmarkData? {
        guard let id = selectedBookmarkID else { return nil }
        return manager.bookmarks.first(where: { $0.id == id })
    }

    func bookmarks(for groupID: UUID) -> [RepositoryBookmarkData] {
        manager.bookmarks
            .filter { $0.groupID == groupID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var ungroupedBookmarks: [RepositoryBookmarkData] {
        manager.bookmarks
            .filter { $0.groupID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        self.selectedGroupID = manager.bookmarkGroups.first?.id
    }

    // MARK: Actions

    func openSelectedBookmark() {
        guard let bookmark = selectedBookmark else { return }
        openBookmark(bookmark)
    }

    func openBookmark(_ bookmark: RepositoryBookmarkData) {
        let reference = RepositoryReference(path: bookmark.path)
        openReference(reference)
    }

    func openReference(_ reference: RepositoryReference) {
        onOpenRepo?(reference)
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
