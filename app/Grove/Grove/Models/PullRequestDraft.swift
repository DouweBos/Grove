// Models/PullRequestDraft.swift
// Grove

import Foundation

/// Everything a hosting service needs to open a pull request.
nonisolated struct PullRequestDraft: Equatable, Sendable {
    var base: String
    var head: String
    var title: String
    var body: String
    var isDraft = false
    var reviewers: [String] = []

    /// Title and body the way `gh pr create --fill` would pick them: one commit speaks for itself,
    /// several become a list under a title made from the branch name. `commits` is newest first.
    static func prefill(head: String, commits: [CommitInfo]) -> (title: String, body: String) {
        if commits.count == 1, let only = commits.first {
            return (only.summary, only.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        let body = commits.reversed().map { "- \($0.summary)" }.joined(separator: "\n")
        return (title(fromBranch: head), body)
    }

    /// "douwe/fix-login_flow" → "Fix login flow".
    static func title(fromBranch branch: String) -> String {
        let last = branch.split(separator: "/").last.map(String.init) ?? branch
        let words = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Splits "alice, bob  carol" into logins, dropping a leading "@".
    static func reviewers(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : String($0) }
            .filter { !$0.isEmpty }
    }

    /// The branch pull requests target by default: the remote's HEAD, else main, master or develop.
    static func defaultBase(remoteHead: String?, candidates: [String]) -> String? {
        if let remoteHead, candidates.contains(remoteHead) { return remoteHead }
        return ["main", "master", "develop", "trunk"].first(where: candidates.contains) ?? remoteHead ?? candidates.first
    }

    /// The number at the end of a pull or merge request URL, e.g. `.../pull/12` or `.../merge_requests/12`.
    static func number(fromURL url: String) -> Int? {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").last.flatMap { Int($0) }
    }
}

/// Whether the head branch has to be pushed before a hosting service can see it.
nonisolated enum BranchPublishState: Equatable, Sendable {
    case published
    /// No upstream on the remote yet.
    case unpublished
    /// Tracks a remote branch but has commits that aren't there.
    case unpushed(Int)

    init(branch: BranchInfo?) {
        guard let branch, branch.isLocal else { self = .published; return }
        if branch.upstream == nil { self = .unpublished; return }
        self = branch.ahead > 0 ? .unpushed(branch.ahead) : .published
    }

    var needsPush: Bool { self != .published }
}
