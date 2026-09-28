// Domain/TowerImporter.swift
// Grove
//
// Reads Tower's bookmarks-v2.plist and converts the repository list
// and group hierarchy into Grove's data model.

import Foundation
import os

// MARK: - TowerImporter

/// Imports repository bookmarks and groups from Tower's data files.
///
/// Tower stores its repository list in a plain XML plist at:
/// `~/Library/Application Support/com.fournova.Tower3/bookmarks-v2.plist`
///
/// The plist has a tree structure:
/// - Root dict (type 3) → children array of group dicts (type 1)
///   - Each group → children array of bookmark dicts (type 2)
///     - Each bookmark has: name, fileURL, repositoryIdentifier, lastOpenedDate, type, valid
enum TowerImporter {

    /// The default location of Tower's bookmarks plist.
    static let defaultBookmarksPath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.fournova.Tower3")
            .appendingPathComponent("bookmarks-v2.plist")
    }()

    /// Whether Tower's bookmarks file exists at the default location.
    static var isTowerInstalled: Bool {
        FileManager.default.fileExists(atPath: defaultBookmarksPath.path)
    }

    // MARK: - Import Result

    /// The result of parsing Tower's bookmarks plist.
    struct ImportResult {
        let groups: [BookmarkGroupData]
        let bookmarks: [RepositoryBookmarkData]
        /// Paths that were in Tower but don't exist on disk.
        let skippedPaths: [String]
    }

    // MARK: - Import

    /// Parse Tower's bookmarks plist and return Grove-compatible data.
    ///
    /// - Parameters:
    ///   - url: Path to the bookmarks-v2.plist. Defaults to Tower's standard location.
    ///   - skipMissingPaths: When true, bookmarks whose paths don't exist on disk are excluded.
    /// - Returns: An `ImportResult` with groups, bookmarks, and any skipped paths.
    static func importBookmarks(
        from url: URL = defaultBookmarksPath,
        skipMissingPaths: Bool = true
    ) throws -> ImportResult {
        let data = try Data(contentsOf: url)

        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw ImportError.invalidFormat("Root is not a dictionary")
        }

        guard let rootChildren = plist["children"] as? [[String: Any]] else {
            throw ImportError.invalidFormat("Root has no children array")
        }

        var groups: [BookmarkGroupData] = []
        var bookmarks: [RepositoryBookmarkData] = []
        var skippedPaths: [String] = []

        for (groupIndex, groupDict) in rootChildren.enumerated() {
            let groupType = groupDict["type"] as? Int ?? 0

            // Type 1 = group, type 2 = bookmark (ungrouped at root level)
            if groupType == 1 {
                let groupID = UUID()
                let groupName = groupDict["name"] as? String ?? "Imported Group"
                let isExpanded = groupDict["expanded"] as? Bool ?? true

                let group = BookmarkGroupData(
                    id: groupID,
                    name: groupName,
                    sortOrder: groupIndex,
                    isExpanded: isExpanded
                )
                groups.append(group)

                // Parse child bookmarks in this group.
                if let children = groupDict["children"] as? [[String: Any]] {
                    for (bookmarkIndex, bookmarkDict) in children.enumerated() {
                        if let result = parseBookmark(bookmarkDict, groupID: groupID, sortOrder: bookmarkIndex, skipMissing: skipMissingPaths) {
                            switch result {
                            case .bookmark(let b):
                                bookmarks.append(b)
                            case .skipped(let path):
                                skippedPaths.append(path)
                            }
                        }
                    }
                }
            } else if groupType == 2 {
                // Ungrouped bookmark at root level.
                if let result = parseBookmark(groupDict, groupID: nil, sortOrder: bookmarks.count, skipMissing: skipMissingPaths) {
                    switch result {
                    case .bookmark(let b):
                        bookmarks.append(b)
                    case .skipped(let path):
                        skippedPaths.append(path)
                    }
                }
            }
        }

        bookmarks = foldingWorktrees(bookmarks)
        Logger.repositoryManager.info("Tower import: \(groups.count) groups, \(bookmarks.count) bookmarks, \(skippedPaths.count) skipped")
        return ImportResult(groups: groups, bookmarks: bookmarks, skippedPaths: skippedPaths)
    }

    // MARK: - Private

    /// Tower lists each git worktree as its own repository. Grove shows worktrees under their
    /// main repository, so keep one bookmark per main repository instead.
    static func foldingWorktrees(_ bookmarks: [RepositoryBookmarkData]) -> [RepositoryBookmarkData] {
        var seen = Set<String>()
        return bookmarks.compactMap { bookmark in
            guard let main = WorktreeResolver.mainRepositoryPath(forWorktreeAt: bookmark.path) else {
                return seen.insert(bookmark.path).inserted ? bookmark : nil
            }
            if bookmarks.contains(where: { $0.path == main }) { return nil }
            guard seen.insert(main).inserted else { return nil }
            var replacement = bookmark
            replacement.path = main
            replacement.displayName = URL(fileURLWithPath: main).lastPathComponent
            return replacement
        }
    }

    private enum ParseResult {
        case bookmark(RepositoryBookmarkData)
        case skipped(String)
    }

    private static func parseBookmark(
        _ dict: [String: Any],
        groupID: UUID?,
        sortOrder: Int,
        skipMissing: Bool
    ) -> ParseResult? {
        guard let fileURLString = dict["fileURL"] as? String,
              let fileURL = URL(string: fileURLString) else {
            return nil
        }

        let path = fileURL.path
        let name = dict["name"] as? String ?? fileURL.lastPathComponent

        // Check if the path exists on disk.
        if skipMissing {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                return .skipped(path)
            }
        }

        // Tower stores Unix timestamps, not CFAbsoluteTime.
        // CFAbsoluteTime is seconds since 2001-01-01 00:00:00 UTC.
        var lastOpened: Date?
        if let towerTimestamp = dict["lastOpenedDate"] as? Double, towerTimestamp > 0 {
            lastOpened = Date(timeIntervalSince1970: towerTimestamp)
        }

        let bookmark = RepositoryBookmarkData(
            id: UUID(),
            path: path,
            displayName: name,
            addedDate: lastOpened ?? Date(),
            lastOpenedDate: lastOpened,
            sortOrder: sortOrder,
            groupID: groupID
        )
        return .bookmark(bookmark)
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let detail):
                return "Invalid Tower bookmarks format: \(detail)"
            }
        }
    }
}
