// Models/OpenPullRequest.swift
// Grove

import Foundation

/// An open pull request, as far as branch rows need to know: which branch it comes from.
nonisolated struct OpenPullRequest: Hashable, Sendable {
    let number: Int
    let title: String
    let headBranch: String
    let isDraft: Bool
    let url: String

    /// `gh pr list --json number,title,headRefName,isDraft,url`, keyed by head branch (newest PR wins).
    static func index(fromJSON data: Data) throws -> [String: OpenPullRequest] {
        struct Row: Decodable {
            let number: Int
            let title: String
            let headRefName: String
            let isDraft: Bool
            let url: String
        }
        var result: [String: OpenPullRequest] = [:]
        for row in try JSONDecoder().decode([Row].self, from: data) where (result[row.headRefName]?.number ?? 0) < row.number {
            result[row.headRefName] = OpenPullRequest(number: row.number, title: row.title, headBranch: row.headRefName,
                                                      isDraft: row.isDraft, url: row.url)
        }
        return result
    }

    /// Shown after the branch name, like `#6549`; draft state lives in the tooltip to keep names readable.
    var label: String { "#\(number)" }

    var tooltip: String { "\(isDraft ? "Draft pull request" : "Pull request") #\(number): \(title)" }
}
