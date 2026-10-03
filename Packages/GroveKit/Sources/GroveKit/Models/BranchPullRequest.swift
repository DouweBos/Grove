// Models/BranchPullRequest.swift
// GroveKit

import Foundation

/// A branch's open or merged pull request, as far as branch rows and stacks need to know.
public nonisolated struct BranchPullRequest: Hashable, Sendable {
    public let number: Int
    let title: String
    let headBranch: String
    public let isDraft: Bool
    public let url: String
    public var baseBranch: String = ""
    public var isMerged = false
    /// Head commit the host knows, at merge time for a merged one; Bitbucket reports it abbreviated.
    public var headSHA: String?
    public var checks: PRChecksStatus = .none

    public init(number: Int, title: String, headBranch: String, isDraft: Bool, url: String, baseBranch: String = "", isMerged: Bool = false, headSHA: String? = nil, checks: PRChecksStatus = .none) {
        self.number = number
        self.title = title
        self.headBranch = headBranch
        self.isDraft = isDraft
        self.url = url
        self.baseBranch = baseBranch
        self.isMerged = isMerged
        self.headSHA = headSHA
        self.checks = checks
    }

    /// Open pull requests keyed by head branch, then merged ones for branches without one; the newest wins.
    public static func index(_ pullRequests: [BranchPullRequest]) -> [String: BranchPullRequest] {
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
    public var label: String { "#\(number)" }

    /// Merged is marked the way the Pull Requests list marks it; open needs no symbol.
    public var detailSymbol: String? { isMerged ? "arrow.triangle.merge" : nil }

    public var tooltip: String {
        let kind = isMerged ? "Merged pull request" : isDraft ? "Draft pull request" : "Pull request"
        return "\(kind) #\(number): \(title)"
    }

    /// Whether `sha` is the commit the host reported, allowing for hosts that report short hashes.
    func headMatches(_ sha: String) -> Bool {
        guard let headSHA, headSHA.count >= 7 else { return false }
        return sha.hasPrefix(headSHA) || headSHA.hasPrefix(sha)
    }
}

extension BranchPullRequest {
    /// From a full pull request, for hosts whose list endpoint already returns everything.
    public init(_ pr: PullRequestInfo, url: String) {
        self.init(number: pr.id, title: pr.title, headBranch: pr.sourceBranch, isDraft: pr.isDraft, url: url,
                  baseBranch: pr.targetBranch, isMerged: pr.state == .merged, headSHA: pr.headSHA, checks: pr.checksStatus)
    }
}
