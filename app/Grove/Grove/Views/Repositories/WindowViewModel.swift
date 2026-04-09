// Views/Repositories/WindowViewModel.swift
// Grove
//
// ViewModel for the main application window. Owns navigation state
// (which repository is open), the browser (bookmarks, groups),
// and loaded repository sessions.

import Foundation
import Observation
import os

// MARK: - BrowserSourceMode

/// Which source is active in the repository browser sidebar.
enum BrowserSourceMode {
    /// Local bookmarks (default). Toggled by the disk icon.
    case local
    /// Connected cloud service repositories. Toggled by the cloud icon.
    case cloud
    /// No source selected (sidebar is hidden).
    case none
}

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

    // MARK: Source Mode

    /// Which source the sidebar is showing: local bookmarks or cloud repos.
    private(set) var sourceMode: BrowserSourceMode = .local

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

    // MARK: Navigation Actions

    func setSourceMode(_ mode: BrowserSourceMode) {
        sourceMode = mode
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
        sourceMode = .none
        openRepo = reference
    }

    func closeRepository() {
        openRepo = nil
        sourceMode = .local
    }

    // MARK: Session Loading

    func loadSessionIfNeeded(for ref: RepositoryReference) {
        let path = ref.path
        guard sessions[path] == nil, sessionErrors[path] == nil else { return }
        Logger.ui.info("Opening repository for \(path, privacy: .public)")
        Task {
            let url = URL(fileURLWithPath: path)
            do {
                let repo = try await GitRepository(path: url)
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

// MARK: - LoadedSession

/// Pairs a loaded repository handle with its session.
struct LoadedSession {
    let repository: any GitRepositoryProtocol
    let session: RepositorySession
}
