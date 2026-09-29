// Models/BranchPullRequest.swift
// Grove

import Foundation

/// A branch's open or merged pull request, as far as branch rows need to know.
nonisolated struct BranchPullRequest: Hashable, Sendable {
    let number: Int
    let title: String
    let headBranch: String
    let isDraft: Bool
    let url: String
    var isMerged = false
    /// Head commit at merge time; Bitbucket reports it abbreviated.
    var headSHA: String?

    /// Open pull requests keyed by head branch, then merged ones for branches without one; the newest wins.
    static func index(_ pullRequests: [BranchPullRequest]) -> [String: BranchPullRequest] {
        var result: [String: BranchPullRequest] = [:]
        for pr in pullRequests where !pr.isMerged && (result[pr.headBranch]?.number ?? 0) < pr.number { result[pr.headBranch] = pr }
        for pr in pullRequests where pr.isMerged && result[pr.headBranch].map({ $0.isMerged && $0.number < pr.number }) ?? true {
            result[pr.headBranch] = pr
        }
        return result
    }

    /// A merged pull request only describes a branch still at its merged head, not one reused or moved on since.
    func applies(toTip sha: String) -> Bool {
        guard isMerged else { return true }
        guard let headSHA, !headSHA.isEmpty else { return false }
        return sha.hasPrefix(headSHA)
    }

    /// Shown after the branch name, like `#6549`; draft state lives in the tooltip to keep names readable.
    var label: String { "#\(number)" }

    /// Merged is marked the way the Pull Requests list marks it; open needs no symbol.
    var detailSymbol: String? { isMerged ? "arrow.triangle.merge" : nil }

    var tooltip: String {
        let kind = isMerged ? "Merged pull request" : isDraft ? "Draft pull request" : "Pull request"
        return "\(kind) #\(number): \(title)"
    }
}
