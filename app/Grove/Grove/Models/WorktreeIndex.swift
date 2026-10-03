// Models/WorktreeIndex.swift
// Grove
//
// Which bookmarks are worktrees of which repositories, for nesting them in the browser.

import CryptoKit
import Foundation
import GroveKit

nonisolated struct WorktreeIndex: Sendable {

    /// Linked worktrees per bookmarked repository path.
    private(set) var worktreesByRepository: [String: [LinkedWorktree]] = [:]
    /// Main repository path per bookmarked path that is itself a worktree.
    private(set) var mainRepositoryByWorktree: [String: String] = [:]

    init() {}

    init(bookmarks: [RepositoryBookmarkData]) {
        for bookmark in bookmarks {
            if let main = WorktreeResolver.mainRepositoryPath(forWorktreeAt: bookmark.path) {
                mainRepositoryByWorktree[bookmark.path] = main
            } else {
                let linked = WorktreeResolver.linkedWorktrees(ofRepositoryAt: bookmark.path)
                if !linked.isEmpty { worktreesByRepository[bookmark.path] = linked }
            }
        }
    }

    /// True when the bookmark should be listed under its main repository instead of on its own.
    func isNested(_ bookmark: RepositoryBookmarkData) -> Bool {
        guard let main = mainRepositoryByWorktree[bookmark.path] else { return false }
        return worktreesByRepository[main] != nil
    }

    /// Stable row identity for a worktree that has no bookmark of its own.
    static func syntheticID(forPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(("grove.worktree:" + path).utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
