// Views/Repositories/WindowViewModel.swift
// Grove
//
// ViewModel for the main application window. Owns navigation state
// (which repository is open), the browser (bookmarks, groups),
// and loaded repository sessions.

import Foundation
import Observation
import os

// MARK: - WindowViewModel

/// Drives the main window: navigation between the browser and open
/// repositories, bookmark management, and repository session lifecycle.
@MainActor
@Observable
final class WindowViewModel {

    // MARK: Dependencies

    let manager: any RepositoryManagerProtocol

    // MARK: Navigation

    /// The currently opened repository, or `nil` when showing the browser.
    var openRepo: RepositoryReference?

    /// Whether the browser is showing (no repository open).
    var isBrowsing: Bool { openRepo == nil }

    // MARK: Sessions

    /// Loaded repositories and their sessions, keyed by filesystem path.
    private(set) var sessions: [String: LoadedSession] = [:]

    /// Repo paths that failed to open.
    private(set) var sessionErrors: [String: String] = [:]

    /// The session for the currently open repository.
    var currentSession: LoadedSession? {
        guard let ref = openRepo else { return nil }
        return sessions[ref.path]
    }

    // MARK: Selection

    var selectedGroupID: UUID?
    var selectedBookmarkID: UUID?

    // MARK: Sheet Presentation

    var isShowingCloneDialog = false
    var isShowingAddDialog = false
    var isShowingCreateDialog = false
    /// Non-nil while the new/rename group sheet is up.
    var groupEditor: GroupEditor?

    // MARK: Search

    private(set) var searchText = ""

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

    var sortedGroups: [BookmarkGroupData] {
        manager.bookmarkGroups.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Groups to list: all of them, or while searching only those with matches.
    var visibleGroups: [BookmarkGroupData] {
        isSearching ? sortedGroups.filter { !bookmarks(for: $0.id).isEmpty } : sortedGroups
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    func bookmarks(for groupID: UUID) -> [RepositoryBookmarkData] {
        filtered(manager.bookmarks.filter { $0.groupID == groupID })
    }

    var ungroupedBookmarks: [RepositoryBookmarkData] {
        filtered(manager.bookmarks.filter { $0.groupID == nil })
    }

    private func filtered(_ list: [RepositoryBookmarkData]) -> [RepositoryBookmarkData] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? list : list.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
        }
        return matches.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
    }

    // MARK: Navigation Actions

    func showAddDialog() { isShowingAddDialog = true }
    func showCloneDialog() { isShowingCloneDialog = true }
    func showCreateDialog() { isShowingCreateDialog = true }
    func showNewGroupDialog() { groupEditor = .new }
    func showRenameGroupDialog(_ group: BookmarkGroupData) { groupEditor = .rename(group) }
    func dismissGroupEditor() { groupEditor = nil }

    func setSearchText(_ text: String) { searchText = text }

    func selectBookmark(_ id: UUID?) { selectedBookmarkID = id }

    /// Menu-bar actions that make sense without an open repository.
    /// Returns false when the action belongs to the repository session.
    func handleBrowserAction(_ action: GroveAction) -> Bool {
        switch action {
        case .addRepository: showAddDialog()
        case .cloneRepository: showCloneDialog()
        case .createRepository: showCreateDialog()
        case .newGroup: showNewGroupDialog()
        default: return false
        }
        return true
    }

    func openSelectedBookmark() {
        guard let bookmark = selectedBookmark else { return }
        openBookmark(bookmark)
    }

    func openBookmark(_ bookmark: RepositoryBookmarkData) {
        let reference = RepositoryReference(path: bookmark.path)
        openReference(reference)
    }

    func openReference(_ reference: RepositoryReference) {
        sessionErrors[reference.path] = nil
        openRepo = reference
    }

    /// Closing stops the watcher and auto-fetch; reopening starts a fresh session.
    func closeRepository() {
        if let path = openRepo?.path, let loaded = sessions.removeValue(forKey: path) {
            loaded.session.stop()
        }
        openRepo = nil
    }

    // MARK: Session Loading

    func loadSessionIfNeeded(for ref: RepositoryReference) {
        let path = ref.path
        guard sessions[path] == nil, sessionErrors[path] == nil else { return }
        Logger.ui.info("Opening repository for \(path, privacy: .public)")
        Task {
            let url = URL(fileURLWithPath: path)
            do {
                // Through the manager so the bookmark's "Last Opened" date updates.
                let repo = try await manager.openRepository(at: url)
                let session = RepositorySession(repository: repo)
                sessions[path] = LoadedSession(repository: repo, session: session)
                await session.start()
                Logger.ui.info("Repository ready: \(ref.displayName, privacy: .public)")
            } catch {
                Logger.ui.error("Failed to open repository \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                sessionErrors[path] = error.localizedDescription
            }
        }
    }

    func stopAllSessions() {
        for (_, loaded) in sessions {
            loaded.session.stop()
        }
    }

    // MARK: Bookmark Actions

    func addBookmark(path: String, displayName: String, groupID: UUID? = nil) {
        do {
            try manager.addBookmark(path: path, displayName: displayName, groupID: groupID)
            selectedBookmarkID = manager.bookmarks.first(where: { $0.path == path })?.id
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

    func renameGroup(_ group: BookmarkGroupData, to name: String) {
        do {
            try manager.renameGroup(id: group.id, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the group sheet: creates or renames depending on how it was opened.
    func commitGroupEditor(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let editor = groupEditor else { return }
        switch editor {
        case .new: createGroup(name: trimmed)
        case .rename(let group): renameGroup(group, to: trimmed)
        }
        groupEditor = nil
    }

    func dismissError() { errorMessage = nil }

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

// MARK: - GroupEditor

enum GroupEditor: Identifiable {
    case new
    case rename(BookmarkGroupData)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let group): group.id.uuidString
        }
    }
}

// MARK: - LoadedSession

/// Pairs a loaded repository handle with its session.
struct LoadedSession {
    let repository: any GitRepositoryProtocol
    let session: RepositorySession
}
