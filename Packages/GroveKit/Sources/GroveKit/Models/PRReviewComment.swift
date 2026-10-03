// Models/PRReviewComment.swift
// GroveKit

import Foundation

/// A comment left on a line of a pull request's diff.
nonisolated struct PRReviewComment: Identifiable, Hashable, Sendable {
    let id: Int
    /// The thread's first comment when this one is a reply.
    let replyTo: Int?
    let authorName: String
    let body: String
    let path: String
    /// Line in the new file; nil when the code it pointed at has since changed.
    let line: Int?
    /// The diff around the comment, ending at the commented line.
    let diffHunk: String
    let createdDate: Date
}

/// A review comment and its replies, anchored to one line.
nonisolated struct PRReviewThread: Identifiable, Hashable, Sendable {
    let root: PRReviewComment
    let replies: [PRReviewComment]
    var id: Int { root.id }

    /// The last few diff lines leading up to the commented line, without the `@@` header.
    var context: [String] {
        Array(root.diffHunk.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("@@") }.suffix(4).map(String.init))
    }

    /// Groups replies under their root; replies to a missing root start their own thread.
    static func threads(from comments: [PRReviewComment]) -> [PRReviewThread] {
        let ids = Set(comments.map(\.id))
        var roots: [PRReviewComment] = []
        var replies: [Int: [PRReviewComment]] = [:]
        for comment in comments {
            if let parent = comment.replyTo, ids.contains(parent) {
                replies[parent, default: []].append(comment)
            } else {
                roots.append(comment)
            }
        }
        return roots.map { PRReviewThread(root: $0, replies: replies[$0.id] ?? []) }
    }
}
