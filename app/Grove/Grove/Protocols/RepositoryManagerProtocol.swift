// Protocols/RepositoryManagerProtocol.swift
// Grove
//
// Contract for the object that manages bookmarked repositories and
// handles open / clone / init operations.
// This file is owned by WS0 and frozen after Phase A.

import Foundation

// MARK: - RepositoryBookmarkData

/// Lightweight, `Codable` representation of a bookmarked repository.
/// Mirrors the SwiftData `RepositoryBookmark` model without the Core Data
/// machinery, enabling use in previews and mocks.
struct RepositoryBookmarkData: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var path: String
    var displayName: String
    var addedDate: Date
    var lastOpenedDate: Date?
    var sortOrder: Int
    /// Identifier of the group this bookmark belongs to, if any.
    var groupID: UUID?
}

// MARK: - BookmarkGroupData

/// Lightweight, `Codable` representation of a bookmark group.
struct BookmarkGroupData: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var isExpanded: Bool
}

// MARK: - RepositoryManagerProtocol

/// Manages the repository list shown in the browser window.
///
/// Responsible for:
/// - Opening, cloning, and initialising repositories.
/// - Persisting bookmark metadata (path, display name, group, order).
/// - Providing observable state for the browser UI.
///
/// The real implementation is owned by WS2; views and ViewModels
/// depend only on this protocol.
@MainActor
protocol RepositoryManagerProtocol: AnyObject, Observable {
    /// All bookmark groups, in display order.
    var bookmarkGroups: [BookmarkGroupData] { get }
    /// All repository bookmarks, in display order.
    var bookmarks: [RepositoryBookmarkData] { get }

    // MARK: Repository Operations

    /// Open an existing repository at the given URL.
    @discardableResult
    func openRepository(at url: URL) async throws -> any GitRepositoryProtocol

    /// Clone a remote repository to a local destination, reporting progress.
    @discardableResult
    func cloneRepository(
        url: String,
        to destination: URL,
        progress: (@Sendable (CloneProgress) -> Void)?
    ) async throws -> any GitRepositoryProtocol

    /// Initialise a new empty repository at the given URL.
    @discardableResult
    func initRepository(at url: URL) async throws -> any GitRepositoryProtocol

    // MARK: Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws
    func removeBookmark(id: UUID) throws

    // MARK: Group Management

    @discardableResult
    func createGroup(name: String) throws -> BookmarkGroupData
    func deleteGroup(id: UUID) throws
    func moveBookmark(id: UUID, toGroup: UUID?) throws
    func reorderBookmark(id: UUID, newSortOrder: Int) throws

    // MARK: Bulk Operations

    /// Remove all bookmarks and groups.
    func clearAllData()

    /// Import groups and bookmarks in bulk, optionally clearing existing data first.
    func importData(groups: [BookmarkGroupData], bookmarks: [RepositoryBookmarkData], clearFirst: Bool)
}
