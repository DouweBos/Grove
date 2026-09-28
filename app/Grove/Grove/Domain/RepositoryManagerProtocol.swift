// Domain/RepositoryManagerProtocol.swift
// Grove
//
// Contract for the object that manages bookmarked repositories and
// handles open / clone / init operations.

import Foundation

// MARK: - RepositoryManagerProtocol

/// Manages the repository list shown in the browser window.
///
/// Responsible for:
/// - Opening, cloning, and initialising repositories.
/// - Persisting bookmark metadata (path, display name, group, order).
/// - Providing observable state for the browser UI.
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

    /// Open a repository to read its state without counting it as opened by the user.
    func inspectRepository(at url: URL) async throws -> any GitRepositoryProtocol

    /// Clone a remote repository to a local destination, reporting progress.
    @discardableResult
    func cloneRepository(
        url: String,
        to destination: URL,
        progress: (@Sendable (CloneProgress) -> Void)?
    ) async throws -> any GitRepositoryProtocol

    /// `git svn clone` of a Subversion repository; `standardLayout` maps trunk, branches and tags.
    @discardableResult
    func cloneSVNRepository(url: String, to destination: URL, standardLayout: Bool) async throws -> any GitRepositoryProtocol

    /// Initialise a new empty repository at the given URL.
    @discardableResult
    func initRepository(at url: URL) async throws -> any GitRepositoryProtocol

    // MARK: Bookmark Management

    func addBookmark(path: String, displayName: String, groupID: UUID?) throws
    func removeBookmark(id: UUID) throws
    func renameBookmark(id: UUID, to name: String) throws
    /// Lists `ids` in this order, reusing the positions they already hold so other bookmarks stay put.
    func orderBookmarks(_ ids: [UUID]) throws

    // MARK: Group Management

    @discardableResult
    func createGroup(name: String) throws -> BookmarkGroupData
    func deleteGroup(id: UUID) throws
    func renameGroup(id: UUID, to name: String) throws
    func moveBookmark(id: UUID, toGroup: UUID?) throws
    func reorderBookmark(id: UUID, newSortOrder: Int) throws
    func orderGroups(_ ids: [UUID]) throws

    // MARK: Bulk Operations

    /// Remove all bookmarks and groups.
    func clearAllData()

    /// Import groups and bookmarks in bulk, optionally clearing existing data first.
    func importData(groups: [BookmarkGroupData], bookmarks: [RepositoryBookmarkData], clearFirst: Bool)
}
