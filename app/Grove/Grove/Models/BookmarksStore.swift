// Models/BookmarksStore.swift
// Grove
//
// Bookmark and group data types, plus the top-level Codable container
// serialized to bookmarks.plist.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - RepositoryBookmarkData

/// Lightweight, `Codable` representation of a bookmarked repository.
nonisolated struct RepositoryBookmarkData: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var path: String
    var displayName: String
    var addedDate: Date
    var lastOpenedDate: Date?
    var sortOrder: Int
    /// Identifier of the group this bookmark belongs to, if any.
    var groupID: UUID?
}

// MARK: - UTType

extension UTType {
    static let groveBookmark = UTType(exportedAs: "com.grove.bookmark")
}

// MARK: - Transferable

extension RepositoryBookmarkData: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .groveBookmark)
    }
}

// MARK: - BookmarkGroupData

/// Lightweight, `Codable` representation of a bookmark group.
struct BookmarkGroupData: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var isExpanded: Bool
}

// MARK: - BookmarksStore

/// The root structure persisted in `bookmarks.plist`.
struct BookmarksStore: Codable {
    var groups: [BookmarkGroupData]
    var bookmarks: [RepositoryBookmarkData]

    /// An empty store used as the default on first launch.
    static let empty = BookmarksStore(groups: [], bookmarks: [])
}
