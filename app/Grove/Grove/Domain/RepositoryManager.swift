// Domain/RepositoryManager.swift
// Grove
//
// Concrete implementation of RepositoryManagerProtocol.
// Persists bookmark and group data as a plist file in Application Support.

import CryptoKit
import Foundation
import Observation
import os

// MARK: - RepositoryManager

/// Concrete repository manager backed by a plist file.
@MainActor
@Observable
final class RepositoryManager: RepositoryManagerProtocol {

    // MARK: Observable State

    /// All bookmark groups, kept in sync with the plist store.
    var bookmarkGroups: [BookmarkGroupData] = []

    /// All repository bookmarks, kept in sync with the plist store.
    var bookmarks: [RepositoryBookmarkData] = []

    // MARK: Private

    private static let filename = "bookmarks.plist"

    // MARK: Init

    /// Creates a ``RepositoryManager`` and loads persisted data from disk.
    init() {
        loadFromDisk()
    }

    // MARK: - Persistence

    /// Loads bookmarks and groups from the plist file.
    private func loadFromDisk() {
        let store = PlistStore.load(BookmarksStore.self, from: Self.filename) ?? .empty
        bookmarkGroups = store.groups.sorted(by: { $0.sortOrder < $1.sortOrder })
        bookmarks = store.bookmarks.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    /// Persists the current in-memory state to the plist file.
    private func saveToDisk() {
        let store = BookmarksStore(groups: bookmarkGroups, bookmarks: bookmarks)
        PlistStore.save(store, to: Self.filename)
    }

    // MARK: - Lookup Helpers

    private func bookmarkIndex(path: String) -> Int? {
        bookmarks.firstIndex(where: { $0.path == path })
    }

    private func bookmarkIndex(id: UUID) -> Int? {
        bookmarks.firstIndex(where: { $0.id == id })
    }

    // MARK: - Repository Operations

    @discardableResult
    func openRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("Opening repository at \(url.path, privacy: .public)")
        do {
            let repo = try await GitRepository(path: url)
            // Update last-opened timestamp for any matching bookmark.
            if let index = bookmarkIndex(path: url.path) {
                bookmarks[index].lastOpenedDate = Date()
                saveToDisk()
            }
            Logger.repositoryManager.info("Repository opened: \(url.lastPathComponent, privacy: .public)")
            return repo
        } catch {
            Logger.repositoryManager.error(
                "Failed to open repository at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func inspectRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        try await GitRepository(path: url)
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
            try await shell.runStreaming(["clone", "--progress", url, destination.path]) { chunk in
                if let parsed = CloneProgressParser.parse(chunk) { progress?(parsed) }
            }
        } catch GitShellError.nonZeroExit(_, _, let stderr) {
            let message = CloneProgressParser.errorMessage(from: stderr)
            Logger.repositoryManager.error("Clone failed: \(message, privacy: .public)")
            throw CloneFailure(message: message)
        }

        progress?(CloneProgress(phase: .checkingOut, receivedObjects: 100, totalObjects: 100, receivedBytes: 0))

        let repo = try await GitRepository(path: destination)
        try addBookmark(path: destination.path, displayName: destination.lastPathComponent, groupID: nil)

        Logger.repositoryManager.info("Clone complete: \(destination.lastPathComponent, privacy: .public)")
        return repo
    }

    @discardableResult
    func cloneSVNRepository(url: String, to destination: URL, standardLayout: Bool) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("git svn clone \(url, privacy: .public) to \(destination.path, privacy: .public)")
        let shell = try await SVNSupport.shell(in: destination.deletingLastPathComponent())
        try await shell.run(["svn", "clone"] + (standardLayout ? ["--stdlayout"] : []) + [url, destination.path])
        let repo = try await GitRepository(path: destination)
        try addBookmark(path: destination.path, displayName: destination.lastPathComponent, groupID: nil)
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

    // MARK: - Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws {
        // Guard against duplicates.
        guard bookmarkIndex(path: path) == nil else {
            Logger.repositoryManager.debug("Bookmark already exists for \(path, privacy: .public)")
            return
        }

        Logger.repositoryManager.info("Adding bookmark: \(displayName, privacy: .public) at \(path, privacy: .public)")

        let bookmark = RepositoryBookmarkData(
            id: UUID(deterministicPath: path),
            path: path,
            displayName: displayName,
            addedDate: Date(),
            lastOpenedDate: nil,
            sortOrder: bookmarks.count,
            groupID: groupID
        )
        bookmarks.append(bookmark)
        saveToDisk()
    }

    func removeBookmark(id: UUID) throws {
        guard let index = bookmarkIndex(id: id) else { return }
        let name = bookmarks[index].displayName
        Logger.repositoryManager.info("Removing bookmark: \(name, privacy: .public)")
        bookmarks.remove(at: index)
        saveToDisk()
    }

    func renameBookmark(id: UUID, to name: String) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].displayName = name
        saveToDisk()
    }

    func orderBookmarks(_ ids: [UUID]) throws {
        let slots = ids.compactMap { id in bookmarks.first { $0.id == id }?.sortOrder }.sorted()
        for (id, slot) in zip(ids, slots) {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) { bookmarks[index].sortOrder = slot }
        }
        bookmarks.sort { $0.sortOrder < $1.sortOrder }
        saveToDisk()
    }

    func orderGroups(_ ids: [UUID]) throws {
        for (order, id) in ids.enumerated() {
            if let index = bookmarkGroups.firstIndex(where: { $0.id == id }) { bookmarkGroups[index].sortOrder = order }
        }
        bookmarkGroups.sort { $0.sortOrder < $1.sortOrder }
        saveToDisk()
    }

    // MARK: - Group Management

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
        saveToDisk()
        return group
    }

    func deleteGroup(id: UUID) throws {
        guard let groupIndex = bookmarkGroups.firstIndex(where: { $0.id == id }) else { return }
        let groupName = bookmarkGroups[groupIndex].name
        Logger.repositoryManager.info("Deleting group: \(groupName, privacy: .public)")

        // Ungroup all bookmarks that belonged to this group.
        for index in bookmarks.indices where bookmarks[index].groupID == id {
            bookmarks[index].groupID = nil
        }

        bookmarkGroups.remove(at: groupIndex)
        saveToDisk()
    }

    func renameGroup(id: UUID, to name: String) throws {
        guard let index = bookmarkGroups.firstIndex(where: { $0.id == id }) else { return }
        bookmarkGroups[index].name = name
        saveToDisk()
    }

    func moveBookmark(id: UUID, toGroup: UUID?) throws {
        guard let index = bookmarkIndex(id: id) else { return }
        bookmarks[index].groupID = toGroup
        saveToDisk()
    }

    func reorderBookmark(id: UUID, newSortOrder: Int) throws {
        guard let index = bookmarkIndex(id: id) else { return }
        bookmarks[index].sortOrder = newSortOrder
        saveToDisk()
    }

    // MARK: - Bulk Operations

    func clearAllData() {
        Logger.repositoryManager.info("Clearing all bookmark data")
        bookmarkGroups.removeAll()
        bookmarks.removeAll()
        saveToDisk()
    }

    func importData(
        groups: [BookmarkGroupData],
        bookmarks newBookmarks: [RepositoryBookmarkData],
        clearFirst: Bool
    ) {
        if clearFirst {
            bookmarkGroups.removeAll()
            bookmarks.removeAll()
        }

        // Merge groups — skip any whose name already exists.
        let existingGroupNames = Set(bookmarkGroups.map(\.name))
        let nextGroupOrder = (bookmarkGroups.map(\.sortOrder).max() ?? -1) + 1

        for (offset, groupData) in groups.enumerated() {
            guard !existingGroupNames.contains(groupData.name) else { continue }
            var group = groupData
            group.sortOrder = nextGroupOrder + offset
            bookmarkGroups.append(group)
        }

        // Merge bookmarks — skip any whose path already exists.
        let existingPaths = Set(bookmarks.map(\.path))
        let nextBookmarkOrder = (bookmarks.map(\.sortOrder).max() ?? -1) + 1

        for (offset, bookmarkData) in newBookmarks.enumerated() {
            guard !existingPaths.contains(bookmarkData.path) else { continue }
            var bookmark = bookmarkData
            bookmark.sortOrder = nextBookmarkOrder + offset
            bookmarks.append(bookmark)
        }

        saveToDisk()
        Logger.repositoryManager.info(
            "Imported \(groups.count) groups, \(newBookmarks.count) bookmarks (clearFirst: \(clearFirst))"
        )
    }
}

// MARK: - UUID + Deterministic Path

private extension UUID {
    /// Creates a version-5 (SHA-1 name-based) UUID from an arbitrary string,
    /// using the DNS namespace OID as the base namespace.
    ///
    /// The same input string always produces the same UUID, giving bookmarks
    /// a stable identity that survives app restarts without a stored UUID column.
    init(deterministicPath path: String) {
        // Namespace: DNS OID  6ba7b810-9dad-11d1-80b4-00c04fd430c8
        let namespaceBytes: [UInt8] = [
            0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
            0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8
        ]

        var digest = Array(Insecure.SHA1.hash(data: Data(namespaceBytes) + Data(path.utf8)))

        // Set version (5) and variant bits per RFC 4122 §4.3.
        digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80  // variant 1

        self = UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
