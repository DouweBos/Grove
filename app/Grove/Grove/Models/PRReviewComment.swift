// Models/PRReviewComment.swift
// Grove

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

    /// `gh api repos/{owner}/{repo}/pulls/N/comments --paginate --jq '.[]'`: one object per line, oldest first.
    static func parseGitHub(_ output: String) throws -> [PRReviewComment] {
        struct Row: Decodable {
            struct User: Decodable { let login: String }
            let id: Int
            let inReplyToId: Int?
            let user: User?
            let body: String
            let path: String
            let line: Int?
            let originalLine: Int?
            let diffHunk: String?
            let createdAt: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try output.split(whereSeparator: \.isNewline).map { line in
            let row = try decoder.decode(Row.self, from: Data(line.utf8))
            return PRReviewComment(id: row.id, replyTo: row.inReplyToId, authorName: row.user?.login ?? "ghost", body: row.body,
                                   path: row.path, line: row.line ?? row.originalLine, diffHunk: row.diffHunk ?? "",
                                   createdDate: GitDate.parse(row.createdAt) ?? .distantPast)
        }
        .sorted { $0.createdDate < $1.createdDate }
    }
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
