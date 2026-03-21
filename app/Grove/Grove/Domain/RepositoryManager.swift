// Domain/RepositoryManager.swift
// Grove
//
// Concrete implementation of RepositoryManagerProtocol.
// Persists bookmark and group data using SwiftData.
//
// The SwiftData model types (RepositoryBookmark, RepositoryGroup, …) are
// implementation details of this class and are never exposed through the
// protocol surface.  All public API uses the lightweight Codable types
// declared in RepositoryManagerProtocol.swift.

import Foundation
import Observation
import SwiftData
import os

// MARK: - RepositoryManager

/// Concrete repository manager backed by a SwiftData `ModelContext`.
///
/// On first launch after the SwiftData store is created, any data previously
/// stored in UserDefaults is migrated automatically and the old keys are
/// removed.  Subsequent launches skip the migration entirely.
@MainActor
@Observable
final class RepositoryManager: RepositoryManagerProtocol {

    // MARK: Observable State

    /// All bookmark groups, kept in sync with the SwiftData store.
    var bookmarkGroups: [BookmarkGroupData] = []

    /// All repository bookmarks, kept in sync with the SwiftData store.
    var bookmarks: [RepositoryBookmarkData] = []

    // MARK: Private State

    private let context: ModelContext

    // MARK: UserDefaults Migration Keys

    /// The UserDefaults keys written by the previous UserDefaults-backed
    /// implementation.  Once migration completes these are removed.
    private enum LegacyKeys {
        static let groups    = "grove.bookmarkGroups"
        static let bookmarks = "grove.bookmarks"
    }

    // MARK: Init

    /// Creates a ``RepositoryManager`` using the provided SwiftData context.
    ///
    /// During initialisation the manager:
    /// 1. Runs the one-time UserDefaults → SwiftData migration (if needed).
    /// 2. Fetches the current state from the store into the observable arrays.
    ///
    /// - Parameter context: A `ModelContext` configured with the Grove schema.
    init(context: ModelContext) {
        self.context = context
        migrateFromUserDefaultsIfNeeded()
        reloadFromStore()
    }

    // MARK: - Migration

    /// Migrates bookmark and group data from UserDefaults to SwiftData.
    ///
    /// The migration runs only when:
    /// - The SwiftData store contains no `RepositoryBookmark` records **and**
    /// - At least one of the legacy UserDefaults keys is present.
    ///
    /// After a successful migration the legacy keys are deleted so the
    /// migration never runs again.
    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        // Bail out early if neither legacy key is present.
        guard defaults.data(forKey: LegacyKeys.groups) != nil
                || defaults.data(forKey: LegacyKeys.bookmarks) != nil
        else { return }

        // Also bail out if the store already contains bookmarks — this
        // handles the edge-case where the migration ran but keys weren't
        // cleaned up (e.g. a previous crash right after saving).
        let existingCount = (try? context.fetchCount(FetchDescriptor<RepositoryBookmark>())) ?? 0
        guard existingCount == 0 else {
            // Store already populated; remove stale legacy keys and return.
            clearLegacyUserDefaultsKeys(defaults)
            return
        }

        Logger.repositoryManager.info("Migrating bookmark data from UserDefaults to SwiftData")

        // Decode legacy groups.
        var legacyGroups: [BookmarkGroupData] = []
        if let data = defaults.data(forKey: LegacyKeys.groups),
           let decoded = try? JSONDecoder().decode([BookmarkGroupData].self, from: data) {
            legacyGroups = decoded
        }

        // Decode legacy bookmarks.
        var legacyBookmarks: [RepositoryBookmarkData] = []
        if let data = defaults.data(forKey: LegacyKeys.bookmarks),
           let decoded = try? JSONDecoder().decode([RepositoryBookmarkData].self, from: data) {
            legacyBookmarks = decoded
        }

        // Insert groups first so bookmarks can reference them by groupID UUID.
        var groupModelsByID: [UUID: RepositoryGroup] = [:]
        for groupData in legacyGroups {
            let model = RepositoryGroup(
                name: groupData.name,
                sortOrder: groupData.sortOrder,
                isExpanded: groupData.isExpanded
            )
            // Preserve the original UUID so existing groupID references on
            // bookmarks resolve correctly.
            model.groupID = groupData.id
            context.insert(model)
            groupModelsByID[groupData.id] = model
        }

        // Insert bookmarks, linking them to their group models.
        for bookmarkData in legacyBookmarks {
            let model = RepositoryBookmark(
                path: bookmarkData.path,
                displayName: bookmarkData.displayName,
                addedDate: bookmarkData.addedDate,
                sortOrder: bookmarkData.sortOrder
            )
            model.lastOpenedDate = bookmarkData.lastOpenedDate
            if let gid = bookmarkData.groupID {
                model.group = groupModelsByID[gid]
            }
            context.insert(model)
        }

        // Persist the migrated data.
        do {
            try context.save()
            Logger.repositoryManager.info(
                "Migration complete: \(legacyGroups.count) groups, \(legacyBookmarks.count) bookmarks"
            )
        } catch {
            Logger.repositoryManager.error("SwiftData migration save failed: \(error.localizedDescription, privacy: .public)")
        }

        // Remove legacy keys regardless of whether the save succeeded —
        // a failed save is better surfaced as empty data than an infinite
        // migration loop.
        clearLegacyUserDefaultsKeys(defaults)
    }

    private func clearLegacyUserDefaultsKeys(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: LegacyKeys.groups)
        defaults.removeObject(forKey: LegacyKeys.bookmarks)
    }

    // MARK: - Store Synchronisation

    /// Re-fetches all groups and bookmarks from the store and rebuilds the
    /// observable arrays.  Called after every mutation.
    private func reloadFromStore() {
        // Groups — sorted by sortOrder ascending.
        let groupDescriptor = FetchDescriptor<RepositoryGroup>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let groupModels = (try? context.fetch(groupDescriptor)) ?? []
        bookmarkGroups = groupModels.map { BookmarkGroupData(from: $0) }

        // Bookmarks — sorted by sortOrder ascending.
        let bookmarkDescriptor = FetchDescriptor<RepositoryBookmark>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let bookmarkModels = (try? context.fetch(bookmarkDescriptor)) ?? []
        bookmarks = bookmarkModels.map { RepositoryBookmarkData(from: $0) }
    }

    /// Saves the context and reloads the observable arrays.
    ///
    /// Any error is logged but not rethrown — callers that mutate state
    /// through the protocol do not expect persistence failures to propagate
    /// as thrown errors unless the protocol method is declared `throws`.
    private func saveAndReload() {
        do {
            try context.save()
        } catch {
            Logger.repositoryManager.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
        reloadFromStore()
    }

    // MARK: - Fetch Helpers

    /// Returns the `RepositoryGroup` model whose `groupID` matches `id`, or `nil`.
    private func groupModel(for id: UUID) -> RepositoryGroup? {
        var descriptor = FetchDescriptor<RepositoryGroup>(
            predicate: #Predicate { $0.groupID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Returns the `RepositoryBookmark` model whose `path` matches, or `nil`.
    private func bookmarkModel(path: String) -> RepositoryBookmark? {
        var descriptor = FetchDescriptor<RepositoryBookmark>(
            predicate: #Predicate { $0.path == path }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Returns the `RepositoryBookmark` model whose `path` is not nil —
    /// this overload finds a bookmark by resolving the `RepositoryBookmarkData` id
    /// through its path (the stable unique key in the store).
    private func bookmarkModel(id: UUID) -> RepositoryBookmark? {
        // The protocol uses UUIDs for bookmark IDs but the SwiftData model
        // uses path as its unique key.  We resolve via the cached array which
        // is always in sync after every reloadFromStore().
        guard let data = bookmarks.first(where: { $0.id == id }) else { return nil }
        return bookmarkModel(path: data.path)
    }

    // MARK: - Repository Operations

    @discardableResult
    func openRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        Logger.repositoryManager.info("Opening repository at \(url.path, privacy: .public)")
        do {
            let repo = try await GitRepository(path: url)
            // Update last-opened timestamp for any matching bookmark.
            if let model = bookmarkModel(path: url.path) {
                model.lastOpenedDate = Date()
                saveAndReload()
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

    // MARK: - Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws {
        // Guard against duplicates.
        guard bookmarkModel(path: path) == nil else {
            Logger.repositoryManager.debug("Bookmark already exists for \(path, privacy: .public)")
            return
        }

        Logger.repositoryManager.info("Adding bookmark: \(displayName, privacy: .public) at \(path, privacy: .public)")

        let model = RepositoryBookmark(
            path: path,
            displayName: displayName,
            addedDate: Date(),
            sortOrder: bookmarks.count
        )

        if let gid = groupID {
            model.group = groupModel(for: gid)
        }

        context.insert(model)
        saveAndReload()
    }

    func removeBookmark(id: UUID) throws {
        guard let model = bookmarkModel(id: id) else { return }
        Logger.repositoryManager.info("Removing bookmark: \(model.displayName, privacy: .public)")
        context.delete(model)
        saveAndReload()
    }

    // MARK: - Group Management

    @discardableResult
    func createGroup(name: String) throws -> BookmarkGroupData {
        Logger.repositoryManager.info("Creating group: \(name, privacy: .public)")
        let model = RepositoryGroup(
            name: name,
            sortOrder: bookmarkGroups.count,
            isExpanded: true
        )
        context.insert(model)
        saveAndReload()
        // Return the freshly persisted group data.
        return bookmarkGroups.first(where: { $0.name == name && $0.sortOrder == model.sortOrder })
            ?? BookmarkGroupData(from: model)
    }

    func deleteGroup(id: UUID) throws {
        guard let model = groupModel(for: id) else { return }
        Logger.repositoryManager.info("Deleting group: \(model.name, privacy: .public)")

        // Ungroup all bookmarks that belong to this group before deleting.
        // The `.nullify` delete rule handles this at the relationship level,
        // but we also reload so the observable arrays reflect the change.
        for bookmark in model.repositories {
            bookmark.group = nil
        }

        context.delete(model)
        saveAndReload()
    }

    func moveBookmark(id: UUID, toGroup: UUID?) throws {
        guard let model = bookmarkModel(id: id) else { return }
        if let gid = toGroup {
            model.group = groupModel(for: gid)
        } else {
            model.group = nil
        }
        saveAndReload()
    }

    func reorderBookmark(id: UUID, newSortOrder: Int) throws {
        guard let model = bookmarkModel(id: id) else { return }
        model.sortOrder = newSortOrder
        saveAndReload()
    }

    // MARK: - Bulk Operations

    func clearAllData() {
        Logger.repositoryManager.info("Clearing all bookmark data")

        let allGroups = (try? context.fetch(FetchDescriptor<RepositoryGroup>())) ?? []
        for group in allGroups { context.delete(group) }

        let allBookmarks = (try? context.fetch(FetchDescriptor<RepositoryBookmark>())) ?? []
        for bookmark in allBookmarks { context.delete(bookmark) }

        saveAndReload()
    }

    func importData(
        groups: [BookmarkGroupData],
        bookmarks newBookmarks: [RepositoryBookmarkData],
        clearFirst: Bool
    ) {
        if clearFirst {
            let allGroups = (try? context.fetch(FetchDescriptor<RepositoryGroup>())) ?? []
            for group in allGroups { context.delete(group) }

            let allBookmarks = (try? context.fetch(FetchDescriptor<RepositoryBookmark>())) ?? []
            for bookmark in allBookmarks { context.delete(bookmark) }
        }

        // Reload so the duplicate-detection sets below reflect any cleared state.
        reloadFromStore()

        // Merge groups — skip any whose name already exists.
        let existingGroupNames = Set(bookmarkGroups.map(\.name))
        let nextGroupOrder = (bookmarkGroups.map(\.sortOrder).max() ?? -1) + 1
        var importedGroupModels: [UUID: RepositoryGroup] = [:]

        for (offset, groupData) in groups.enumerated() {
            guard !existingGroupNames.contains(groupData.name) else { continue }
            let model = RepositoryGroup(
                name: groupData.name,
                sortOrder: nextGroupOrder + offset,
                isExpanded: groupData.isExpanded
            )
            // Preserve the UUID so bookmark groupID references resolve correctly.
            model.groupID = groupData.id
            context.insert(model)
            importedGroupModels[groupData.id] = model
        }

        // Merge bookmarks — skip any whose path already exists.
        let existingPaths = Set(bookmarks.map(\.path))
        let nextBookmarkOrder = (bookmarks.map(\.sortOrder).max() ?? -1) + 1

        for (offset, bookmarkData) in newBookmarks.enumerated() {
            guard !existingPaths.contains(bookmarkData.path) else { continue }
            let model = RepositoryBookmark(
                path: bookmarkData.path,
                displayName: bookmarkData.displayName,
                addedDate: bookmarkData.addedDate,
                sortOrder: nextBookmarkOrder + offset
            )
            model.lastOpenedDate = bookmarkData.lastOpenedDate

            if let gid = bookmarkData.groupID {
                // Prefer a freshly imported group model; fall back to an
                // already-existing group in the store.
                model.group = importedGroupModels[gid] ?? groupModel(for: gid)
            }
            context.insert(model)
        }

        saveAndReload()
        Logger.repositoryManager.info(
            "Imported \(groups.count) groups, \(newBookmarks.count) bookmarks (clearFirst: \(clearFirst))"
        )
    }
}

// MARK: - BookmarkGroupData + SwiftData

private extension BookmarkGroupData {
    /// Converts a `RepositoryGroup` SwiftData model to the protocol's data type.
    init(from model: RepositoryGroup) {
        self.init(
            id: model.groupID,
            name: model.name,
            sortOrder: model.sortOrder,
            isExpanded: model.isExpanded
        )
    }
}

// MARK: - RepositoryBookmarkData + SwiftData

private extension RepositoryBookmarkData {
    /// Converts a `RepositoryBookmark` SwiftData model to the protocol's data type.
    ///
    /// The `id` is synthesised from the path string because the SwiftData model
    /// does not carry a separate UUID primary key.  Hashing the path to a
    /// deterministic UUID ensures that the same repository always produces
    /// the same `RepositoryBookmarkData.id` across reloads, which is required
    /// for stable `List` selection and `Identifiable` diffing.
    init(from model: RepositoryBookmark) {
        self.init(
            id: UUID(deterministicPath: model.path),
            path: model.path,
            displayName: model.displayName,
            addedDate: model.addedDate,
            lastOpenedDate: model.lastOpenedDate,
            sortOrder: model.sortOrder,
            groupID: model.group?.groupID
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
            0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
        ]
        let input = namespaceBytes + Array(path.utf8)

        // SHA-1 digest — implemented inline to avoid importing CryptoKit
        // or CommonCrypto from the Domain layer.
        var digest = sha1(data: input)

        // Set version (5) and variant bits per RFC 4122 §4.3.
        digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80  // variant 1

        self = UUID(uuid: (
            digest[0],  digest[1],  digest[2],  digest[3],
            digest[4],  digest[5],  digest[6],  digest[7],
            digest[8],  digest[9],  digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

// MARK: - Minimal SHA-1

/// Pure-Swift, allocation-light SHA-1 implementation (RFC 3174).
///
/// Used exclusively by ``UUID/init(deterministicPath:)`` to avoid adding
/// CryptoKit or CommonCrypto as a compile-time dependency inside the Domain
/// layer.  Not intended for security-sensitive use.
private func sha1(data: [UInt8]) -> [UInt8] {
    var message = data

    // Pre-processing: padding.
    let originalBitCount = UInt64(message.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 {
        message.append(0x00)
    }
    // Append original length as big-endian 64-bit integer.
    for i in stride(from: 56, through: 0, by: -8) {
        message.append(UInt8((originalBitCount >> i) & 0xFF))
    }

    // Initial hash values (H0–H4).
    var h0: UInt32 = 0x67452301
    var h1: UInt32 = 0xEFCDAB89
    var h2: UInt32 = 0x98BADCFE
    var h3: UInt32 = 0x10325476
    var h4: UInt32 = 0xC3D2E1F0

    // Process each 64-byte chunk.
    for chunkStart in stride(from: 0, to: message.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 80)
        for i in 0..<16 {
            let offset = chunkStart + i * 4
            w[i] = (UInt32(message[offset]) << 24)
                | (UInt32(message[offset + 1]) << 16)
                | (UInt32(message[offset + 2]) << 8)
                |  UInt32(message[offset + 3])
        }
        for i in 16..<80 {
            w[i] = rotateLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], by: 1)
        }

        var (a, b, c, d, e) = (h0, h1, h2, h3, h4)

        for i in 0..<80 {
            let (f, k): (UInt32, UInt32)
            switch i {
            case 0..<20:
                f = (b & c) | (~b & d)
                k = 0x5A827999
            case 20..<40:
                f = b ^ c ^ d
                k = 0x6ED9EBA1
            case 40..<60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            default:
                f = b ^ c ^ d
                k = 0xCA62C1D6
            }
            let temp = rotateLeft(a, by: 5) &+ f &+ e &+ k &+ w[i]
            e = d
            d = c
            c = rotateLeft(b, by: 30)
            b = a
            a = temp
        }

        h0 = h0 &+ a
        h1 = h1 &+ b
        h2 = h2 &+ c
        h3 = h3 &+ d
        h4 = h4 &+ e
    }

    // Produce the 20-byte digest.
    var digest = [UInt8](repeating: 0, count: 20)
    for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
        digest[i * 4]     = UInt8((h >> 24) & 0xFF)
        digest[i * 4 + 1] = UInt8((h >> 16) & 0xFF)
        digest[i * 4 + 2] = UInt8((h >>  8) & 0xFF)
        digest[i * 4 + 3] = UInt8( h        & 0xFF)
    }
    return digest
}

@inline(__always)
private func rotateLeft(_ value: UInt32, by count: UInt32) -> UInt32 {
    (value << count) | (value >> (32 - count))
}
