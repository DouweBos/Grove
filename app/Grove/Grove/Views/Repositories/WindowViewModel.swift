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

    /// Which list the browser shows when no repository is open.
    enum BrowserMode { case local, remote }
    private(set) var browserMode: BrowserMode = .local
    let remoteRepositories = RemoteRepositoriesViewModel()
    /// URL the clone sheet opens with, e.g. from the remote browser.
    private(set) var cloneURLPrefill: String?

    /// Tab to reopen on after switching worktrees.
    private var pendingSelection: SidebarItem?

    // MARK: Info Panel Snapshots

    /// Last read state per repository path; see WindowViewModel+Snapshots.
    private(set) var repositorySnapshots: [String: RepositorySnapshot] = [:]
    private(set) var refreshingSnapshotPaths: Set<String> = []
    private(set) var snapshotErrors: [String: String] = [:]

    func storeSnapshot(_ snapshot: RepositorySnapshot, for path: String) {
        repositorySnapshots[path] = snapshot
        snapshotErrors[path] = nil
    }

    func storeSnapshotError(_ message: String, for path: String) { snapshotErrors[path] = message }

    func setSnapshotRefreshing(_ refreshing: Bool, for path: String) {
        if refreshing { refreshingSnapshotPaths.insert(path) } else { refreshingSnapshotPaths.remove(path) }
    }

    // MARK: History

    /// Locations to return to, most recent last; see WindowViewModel+History.
    private(set) var backHistory: [NavigationLocation] = []
    private(set) var forwardHistory: [NavigationLocation] = []
    /// Set while back/forward replays a location, so replaying doesn't record new history.
    private(set) var isApplyingHistory = false

    func pushBack(_ location: NavigationLocation) { backHistory.append(location) }
    func popBack() { backHistory.removeLast() }
    func pushForward(_ location: NavigationLocation) { forwardHistory.append(location) }
    func popForward() { forwardHistory.removeLast() }
    func clearForward() { forwardHistory.removeAll() }

    func withHistoryApplying(_ body: () -> Void) {
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        body()
    }

    /// Opens `path` on `item`, stopping the current repository's session first.
    func reopen(path: String, on item: SidebarItem?) {
        if let current = openRepo, let loaded = sessions.removeValue(forKey: current.path) {
            loaded.session.stop()
        }
        pendingSelection = item
        openReference(RepositoryReference(path: path))
    }

    /// Worktree links read from disk; rebuilt by `refreshWorktrees()`.
    private(set) var worktreeIndex = WorktreeIndex()

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
        return manager.bookmarks.first(where: { $0.id == id }) ?? worktreeRow(withID: id)
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
        filtered(topLevelBookmarks.filter { $0.groupID == groupID })
    }

    var ungroupedBookmarks: [RepositoryBookmarkData] {
        filtered(topLevelBookmarks.filter { $0.groupID == nil })
    }

    /// Worktrees whose main repository is bookmarked are listed under it, not on their own.
    private var topLevelBookmarks: [RepositoryBookmarkData] {
        manager.bookmarks.filter { !worktreeIndex.isNested($0) }
    }

    private func filtered(_ list: [RepositoryBookmarkData]) -> [RepositoryBookmarkData] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? list : list.filter { bookmark in
            matches(bookmark, query) || worktreeRows(of: bookmark).contains { matches($0, query) }
        }
        return matches.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func matches(_ bookmark: RepositoryBookmarkData, _ query: String) -> Bool {
        bookmark.displayName.localizedCaseInsensitiveContains(query) || bookmark.path.localizedCaseInsensitiveContains(query)
    }

    // MARK: Init

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
        refreshWorktrees()
    }

    /// Re-reads worktree links from disk; cheap enough to run on every bookmark change or activation.
    func refreshWorktrees() {
        worktreeIndex = WorktreeIndex(bookmarks: manager.bookmarks)
    }

    // MARK: Navigation Actions

    func showAddDialog() { isShowingAddDialog = true }
    func showCloneDialog(url: String? = nil) {
        cloneURLPrefill = url
        isShowingCloneDialog = true
    }

    /// The disk button: leave any open repository and show local repositories.
    func showLocalRepositories() {
        recordNavigation(to: .browser(.local))
        if !isBrowsing { closeRepository() }
        browserMode = .local
    }

    /// The cloud button: leave any open repository and show the signed-in account's hosted repositories.
    func showRemoteRepositories() {
        recordNavigation(to: .browser(.remote))
        if !isBrowsing { closeRepository() }
        browserMode = .remote
        remoteRepositories.indexLocalClones(bookmarks: manager.bookmarks)
        Task { await remoteRepositories.loadIfNeeded() }
    }

    /// Opens a hosted repository's local clone, bookmarking nothing new.
    func openLocalClone(atPath path: String) {
        // Open first so history records the remote browser as the way back.
        openReference(RepositoryReference(path: path))
        browserMode = .local
    }
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
        case .showLocalRepositories: showLocalRepositories()
        case .showRemoteRepositories: showRemoteRepositories()
        case .navigateBack: goBack()
        case .navigateForward: goForward()
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
        recordNavigation(to: .repository(path: reference.path, item: nil))
        sessionErrors[reference.path] = nil
        openRepo = reference
    }

    /// Runs this window in another worktree of the same repository, keeping the current tab.
    /// The old worktree's session stops so each repository fetches and watches only once.
    func switchWorktree(to path: String) {
        guard let current = openRepo, current.path != path else { return }
        recordNavigation(to: .repository(path: path, item: nil))
        if let loaded = sessions.removeValue(forKey: current.path) {
            pendingSelection = RepositoryTab(item: loaded.session.selectedItem).item
            loaded.session.stop()
        }
        openReference(RepositoryReference(path: path))
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
                session.sidebarVM.onSwitchWorktree = { [weak self] path in self?.switchWorktree(to: path) }
                if let pendingSelection {
                    session.restoreSelection(pendingSelection)
                    self.pendingSelection = nil
                }
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
            addRepository(at: url)
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
