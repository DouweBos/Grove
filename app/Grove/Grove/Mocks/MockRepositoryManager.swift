// Mocks/MockRepositoryManager.swift
// Grove
//
// Realistic in-memory fake that conforms to RepositoryManagerProtocol.
// Used by the repository browser and all views that need a manager
// during Phase B development and in SwiftUI Previews.

import Foundation
import Observation

// MARK: - MockRepositoryManager

/// An in-memory fake repository manager with pre-populated bookmarks and groups.
@MainActor
@Observable
final class MockRepositoryManager: RepositoryManagerProtocol {

    // MARK: Observable State

    var bookmarkGroups: [BookmarkGroupData]
    var bookmarks: [RepositoryBookmarkData]

    // MARK: Init

    init() {
        let workGroup = BookmarkGroupData(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Work",
            sortOrder: 0,
            isExpanded: true
        )
        let personalGroup = BookmarkGroupData(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Personal",
            sortOrder: 1,
            isExpanded: true
        )
        bookmarkGroups = [workGroup, personalGroup]

        let now = Date()
        bookmarks = [
            RepositoryBookmarkData(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                path: "/Users/dev/Projects/my-app",
                displayName: "my-app",
                addedDate: Calendar.current.date(byAdding: .day, value: -30, to: now)!,
                lastOpenedDate: Calendar.current.date(byAdding: .hour, value: -2, to: now),
                sortOrder: 0,
                groupID: workGroup.id
            ),
            RepositoryBookmarkData(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                path: "/Users/dev/Projects/api-server",
                displayName: "api-server",
                addedDate: Calendar.current.date(byAdding: .day, value: -20, to: now)!,
                lastOpenedDate: Calendar.current.date(byAdding: .day, value: -1, to: now),
                sortOrder: 1,
                groupID: workGroup.id
            ),
            RepositoryBookmarkData(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                path: "/Users/dev/Projects/design-system",
                displayName: "design-system",
                addedDate: Calendar.current.date(byAdding: .day, value: -15, to: now)!,
                lastOpenedDate: nil,
                sortOrder: 2,
                groupID: workGroup.id
            ),
            RepositoryBookmarkData(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                path: "/Users/dev/Projects/dotfiles",
                displayName: "dotfiles",
                addedDate: Calendar.current.date(byAdding: .day, value: -90, to: now)!,
                lastOpenedDate: Calendar.current.date(byAdding: .day, value: -7, to: now),
                sortOrder: 0,
                groupID: personalGroup.id
            ),
            RepositoryBookmarkData(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
                path: "/Users/dev/Projects/blog",
                displayName: "blog",
                addedDate: Calendar.current.date(byAdding: .day, value: -60, to: now)!,
                lastOpenedDate: Calendar.current.date(byAdding: .day, value: -3, to: now),
                sortOrder: 1,
                groupID: personalGroup.id
            )
        ]
    }

    // MARK: Repository Operations

    @discardableResult
    func openRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        try? await Task.sleep(nanoseconds: 100_000_000)
        return MockGitRepository(
            path: url,
            displayName: url.lastPathComponent
        )
    }

    func inspectRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        MockGitRepository(path: url, displayName: url.lastPathComponent)
    }

    @discardableResult
    func cloneRepository(
        url: String,
        to destination: URL,
        progress: (@Sendable (CloneProgress) -> Void)?
    ) async throws -> any GitRepositoryProtocol {
        // Simulate a multi-phase clone with progress reporting.
        let steps: [(ClonePhase, Int, Int)] = [
            (.fetching, 0, 100),
            (.fetching, 50, 100),
            (.indexing, 80, 100),
            (.checkingOut, 95, 100),
            (.checkingOut, 100, 100)
        ]
        for (phase, received, total) in steps {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let report = CloneProgress(
                phase: phase,
                receivedObjects: received,
                totalObjects: total,
                receivedBytes: Int64(received) * 1024
            )
            progress?(report)
        }
        return MockGitRepository(path: destination, displayName: destination.lastPathComponent)
    }

    @discardableResult
    func cloneSVNRepository(url: String, to destination: URL, standardLayout: Bool) async throws -> any GitRepositoryProtocol {
        try await cloneRepository(url: url, to: destination, progress: nil)
    }

    @discardableResult
    func initRepository(at url: URL) async throws -> any GitRepositoryProtocol {
        try? await Task.sleep(nanoseconds: 80_000_000)
        return MockGitRepository(path: url, displayName: url.lastPathComponent)
    }

    // MARK: Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws {
        let newBookmark = RepositoryBookmarkData(
            id: UUID(),
            path: path,
            displayName: displayName,
            addedDate: Date(),
            lastOpenedDate: nil,
            sortOrder: bookmarks.count,
            groupID: groupID
        )
        bookmarks.append(newBookmark)
    }

    func removeBookmark(id: UUID) throws {
        bookmarks.removeAll(where: { $0.id == id })
    }

    // MARK: Group Management

    @discardableResult
    func createGroup(name: String) throws -> BookmarkGroupData {
        let group = BookmarkGroupData(
            id: UUID(),
            name: name,
            sortOrder: bookmarkGroups.count,
            isExpanded: true
        )
        bookmarkGroups.append(group)
        return group
    }

    func deleteGroup(id: UUID) throws {
        bookmarkGroups.removeAll(where: { $0.id == id })
        // Ungroup bookmarks that belonged to the deleted group.
        for index in bookmarks.indices where bookmarks[index].groupID == id {
            bookmarks[index].groupID = nil
        }
    }

    func renameBookmark(id: UUID, to name: String) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].displayName = name
    }

    func orderBookmarks(_ ids: [UUID]) throws {
        let slots = ids.compactMap { id in bookmarks.first { $0.id == id }?.sortOrder }.sorted()
        for (id, slot) in zip(ids, slots) {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) { bookmarks[index].sortOrder = slot }
        }
        bookmarks.sort { $0.sortOrder < $1.sortOrder }
    }

    func orderGroups(_ ids: [UUID]) throws {
        for (order, id) in ids.enumerated() {
            if let index = bookmarkGroups.firstIndex(where: { $0.id == id }) { bookmarkGroups[index].sortOrder = order }
        }
        bookmarkGroups.sort { $0.sortOrder < $1.sortOrder }
    }

    func renameGroup(id: UUID, to name: String) throws {
        guard let index = bookmarkGroups.firstIndex(where: { $0.id == id }) else { return }
        bookmarkGroups[index].name = name
    }

    func moveBookmark(id: UUID, toGroup: UUID?) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].groupID = toGroup
    }

    func reorderBookmark(id: UUID, newSortOrder: Int) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].sortOrder = newSortOrder
    }

    // MARK: Bulk Operations

    func clearAllData() {
        bookmarkGroups.removeAll()
        bookmarks.removeAll()
    }

    func importData(groups: [BookmarkGroupData], bookmarks newBookmarks: [RepositoryBookmarkData], clearFirst: Bool) {
        if clearFirst {
            bookmarkGroups.removeAll()
            bookmarks.removeAll()
        }
        bookmarkGroups.append(contentsOf: groups)
        bookmarks.append(contentsOf: newBookmarks)
    }
}
