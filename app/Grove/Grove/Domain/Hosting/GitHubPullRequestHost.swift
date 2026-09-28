// Domain/Hosting/GitHubPullRequestHost.swift
// Grove

import Foundation

/// GitHub through `gh`, run in the repository so it picks the GitHub remote and host itself.
nonisolated struct GitHubPullRequestHost: PullRequestHost {
    let directory: URL
    var kind: HostingServiceKind { .github }

    private static let fields = "number,title,body,author,state,headRefName,baseRefName,createdAt,updatedAt,isDraft,labels,"
        + "reviewRequests,statusCheckRollup"

    private func gh(_ arguments: [String]) async throws -> String {
        try await GitHubCLI.run(arguments, in: directory)
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        try PRParser.parseList(try await gh(["pr", "list", "--json", Self.fields, "--state", "all", "--limit", "100"]))
    }

    /// Only what branch rows show, so it stays a small response even for busy repositories.
    func openPullRequests() async throws -> [String: OpenPullRequest] {
        let output = try await gh(["pr", "list", "--state", "open", "--limit", "500", "--json", "number,title,headRefName,isDraft,url"])
        return try OpenPullRequest.index(fromJSON: Data(output.utf8))
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        try PRParser.parseSingle(try await gh(["pr", "view", "\(number)", "--json", Self.fields]))
    }

    func comments(number: Int) async throws -> [PRComment] {
        try PRParser.parseComments(try await gh(["pr", "view", "\(number)", "--json", "comments,reviews"]))
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        // gh fills in {owner}/{repo} from the repository's GitHub remote.
        try PRReviewComment.parseGitHub(try await gh(["api", "repos/{owner}/{repo}/pulls/\(number)/comments", "--paginate", "--jq", ".[]"]))
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        GitHubCLI.parseCommits(try await gh(["pr", "view", "\(number)", "--json", "commits"]))
    }

    func diff(number: Int) async throws -> String? {
        try await gh(["pr", "diff", "\(number)"])
    }

    func merge(number: Int) async throws {
        _ = try await gh(["pr", "merge", "\(number)", "--merge"])
    }

    func close(number: Int) async throws {
        _ = try await gh(["pr", "close", "\(number)"])
    }

    func comment(number: Int, body: String) async throws {
        _ = try await gh(["pr", "comment", "\(number)", "--body", body])
    }

    func create(_ draft: PullRequestDraft) async throws -> String {
        // gh prints progress lines before the URL; the URL is the last line.
        let output = try await gh(GitHubCLI.createPullRequestArguments(draft))
        return output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    }

    func webURL(number: Int) async throws -> URL? {
        URL(string: try await gh(["pr", "view", "\(number)", "--json", "url", "--jq", ".url"])
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `gh pr checkout` also handles pull requests from forks.
    func checkout(number: Int) async throws -> Bool {
        _ = try await gh(["pr", "checkout", "\(number)"])
        return true
    }
}
