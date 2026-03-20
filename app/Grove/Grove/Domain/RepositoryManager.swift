// Domain/RepositoryManager.swift
// Grove
//
// Concrete implementation of RepositoryManagerProtocol.
// Manages repository bookmarks in memory (persisted via UserDefaults for now).
// WS5 will replace the persistence layer with SwiftData.

import Foundation
import Observation
import os

// MARK: - RepositoryManager

/// Concrete repository manager that persists bookmarks to UserDefaults.
///
/// In Phase B this replaces the mock in non-preview contexts. WS5 will
/// swap the persistence layer for SwiftData without changing the protocol surface.
@MainActor
@Observable
final class RepositoryManager: RepositoryManagerProtocol {

    // MARK: Observable State

    var bookmarkGroups: [BookmarkGroupData] = []
    var bookmarks: [RepositoryBookmarkData] = []

    // MARK: Private State

    private let defaults = UserDefaults.standard
    private let groupsKey = "grove.bookmarkGroups"
    private let bookmarksKey = "grove.bookmarks"

    // MARK: Init

    init() {
        loadFromDefaults()
    }

    // MARK: Persistence

    private func loadFromDefaults() {
        if let groupsData = defaults.data(forKey: groupsKey),
           let groups = try? JSONDecoder().decode([BookmarkGroupData].self, from: groupsData) {
            bookmarkGroups = groups
        }
        if let bookmarksData = defaults.data(forKey: bookmarksKey),
           let bmarks = try? JSONDecoder().decode([RepositoryBookmarkData].self, from: bookmarksData) {
            bookmarks = bmarks
        }
    }

    private func saveToDefaults() {
        if let groupsData = try? JSONEncoder().encode(bookmarkGroups) {
            defaults.set(groupsData, forKey: groupsKey)
        }
        if let bookmarksData = try? JSONEncoder().encode(bookmarks) {
            defaults.set(bookmarksData, forKey: bookmarksKey)
        }
    }

    // MARK: Repository Operations

    @discardableResult
    func openRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("Opening repository at \(url.path, privacy: .public)")
        do {
            let repo = try await GitRepository(path: url)
            // Update last-opened timestamp for any matching bookmark.
            if let index = bookmarks.firstIndex(where: { $0.path == url.path }) {
                bookmarks[index].lastOpenedDate = Date()
                saveToDefaults()
            }
            Logger.repositoryManager.info("Repository opened: \(url.lastPathComponent, privacy: .public)")
            return repo
        } catch {
            Logger.repositoryManager.error("Failed to open repository at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    func cloneRepository(
        url: String,
        to destination: URL,
        progress: (@Sendable (CloneProgress) -> Void)?
    ) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("Cloning \(url, privacy: .public) to \(destination.path, privacy: .public)")

        let shell = GitShell(workingDirectory: destination.deletingLastPathComponent())

        progress?(CloneProgress(phase: .fetching, receivedObjects: 0, totalObjects: 100, receivedBytes: 0))

        do {
            try await shell.run(["clone", "--progress", url, destination.path])
        } catch {
            Logger.repositoryManager.error("Clone failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        progress?(CloneProgress(phase: .checkingOut, receivedObjects: 100, totalObjects: 100, receivedBytes: 0))

        let repo = try await GitRepository(path: destination)
        try addBookmark(path: destination.path, displayName: destination.lastPathComponent, groupID: nil)

        Logger.repositoryManager.info("Clone complete: \(destination.lastPathComponent, privacy: .public)")
        return repo
    }

    @discardableResult
    func initRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("Initializing repository at \(url.path, privacy: .public)")

        // Ensure the directory exists.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let shell = GitShell(workingDirectory: url)
        try await shell.run(["init"])

        let repo = try await GitRepository(path: url)
        try addBookmark(path: url.path, displayName: url.lastPathComponent, groupID: nil)

        Logger.repositoryManager.info("Repository initialized: \(url.lastPathComponent, privacy: .public)")
        return repo
    }

    // MARK: Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws {
        guard !bookmarks.contains(where: { $0.path == path }) else {
            Logger.repositoryManager.debug("Bookmark already exists for \(path, privacy: .public)")
            return
        }
        Logger.repositoryManager.info("Adding bookmark: \(displayName, privacy: .public) at \(path, privacy: .public)")
        let bookmark = RepositoryBookmarkData(
            id: UUID(),
            path: path,
            displayName: displayName,
            addedDate: Date(),
            lastOpenedDate: nil,
            sortOrder: bookmarks.count,
            groupID: groupID
        )
        bookmarks.append(bookmark)
        saveToDefaults()
    }

    func removeBookmark(id: UUID) throws {
        if let bookmark = bookmarks.first(where: { $0.id == id }) {
            Logger.repositoryManager.info("Removing bookmark: \(bookmark.displayName, privacy: .public)")
        }
        bookmarks.removeAll(where: { $0.id == id })
        saveToDefaults()
    }

    // MARK: Group Management

    @discardableResult
    func createGroup(name: String) throws -> BookmarkGroupData {
        Logger.repositoryManager.info("Creating group: \(name, privacy: .public)")
        let group = BookmarkGroupData(
            id: UUID(),
            name: name,
            sortOrder: bookmarkGroups.count,
            isExpanded: true
        )
        bookmarkGroups.append(group)
        saveToDefaults()
        return group
    }

    func deleteGroup(id: UUID) throws {
        if let group = bookmarkGroups.first(where: { $0.id == id }) {
            Logger.repositoryManager.info("Deleting group: \(group.name, privacy: .public)")
        }
        bookmarkGroups.removeAll(where: { $0.id == id })
        for index in bookmarks.indices where bookmarks[index].groupID == id {
            bookmarks[index].groupID = nil
        }
        saveToDefaults()
    }

    func moveBookmark(id: UUID, toGroup: UUID?) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].groupID = toGroup
        saveToDefaults()
    }

    func reorderBookmark(id: UUID, newSortOrder: Int) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].sortOrder = newSortOrder
        saveToDefaults()
    }

    // MARK: Bulk Operations

    func clearAllData() {
        Logger.repositoryManager.info("Clearing all bookmark data")
        bookmarkGroups.removeAll()
        bookmarks.removeAll()
        saveToDefaults()
    }

    func importData(groups: [BookmarkGroupData], bookmarks newBookmarks: [RepositoryBookmarkData], clearFirst: Bool) {
        if clearFirst {
            bookmarkGroups.removeAll()
            bookmarks.removeAll()
        }
        // Merge groups, skipping duplicates by name.
        let existingNames = Set(bookmarkGroups.map(\.name))
        let nextGroupOrder = bookmarkGroups.map(\.sortOrder).max().map { $0 + 1 } ?? 0
        for (offset, group) in groups.enumerated() {
            if !existingNames.contains(group.name) {
                var g = group
                g.sortOrder = nextGroupOrder + offset
                bookmarkGroups.append(g)
            }
        }
        // Merge bookmarks, skipping duplicates by path.
        let existingPaths = Set(bookmarks.map(\.path))
        let nextBookmarkOrder = bookmarks.map(\.sortOrder).max().map { $0 + 1 } ?? 0
        for (offset, bookmark) in newBookmarks.enumerated() {
            if !existingPaths.contains(bookmark.path) {
                var b = bookmark
                b.sortOrder = nextBookmarkOrder + offset
                bookmarks.append(b)
            }
        }
        saveToDefaults()
        Logger.repositoryManager.info("Imported \(groups.count) groups, \(newBookmarks.count) bookmarks (clearFirst: \(clearFirst))")
    }
}
