// Models/PRReviewComment.swift
// GroveKit

import Foundation

/// A comment left on a line of a pull request's diff.
public nonisolated struct PRReviewComment: Identifiable, Hashable, Sendable {
    public let id: Int
    /// The thread's first comment when this one is a reply.
    public let replyTo: Int?
    public let authorName: String
    public let body: String
    public let path: String
    /// Line in the new file; nil when the code it pointed at has since changed.
    public let line: Int?
    /// The diff around the comment, ending at the commented line.
    let diffHunk: String
    public let createdDate: Date

    public init(id: Int, replyTo: Int? = nil, authorName: String, body: String, path: String, line: Int? = nil, diffHunk: String, createdDate: Date) {
        self.id = id
        self.replyTo = replyTo
        self.authorName = authorName
        self.body = body
        self.path = path
        self.line = line
        self.diffHunk = diffHunk
        self.createdDate = createdDate
    }
}

/// A review comment and its replies, anchored to one line.
public nonisolated struct PRReviewThread: Identifiable, Hashable, Sendable {
    public let root: PRReviewComment
    public let replies: [PRReviewComment]
    public var id: Int { root.id }

    /// The last few diff lines leading up to the commented line, without the `@@` header.
    public var context: [String] {
        Array(root.diffHunk.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("@@") }.suffix(4).map(String.init))
    }

    /// Groups replies under their root; replies to a missing root start their own thread.
    public static func threads(from comments: [PRReviewComment]) -> [PRReviewThread] {
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
