// GitKit/GitRepository+PullRequests.swift
// Grove
//
// Pull requests via the GitHub CLI.

import Foundation
import os

extension GitRepository {

    // MARK: - Pull Requests

    func pullRequests() async throws -> [PullRequestInfo] {
        Logger.gitRepository.info("Fetching pull requests in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "list",
            "--json", "number,title,body,author,state,headRefName,baseRefName,createdAt,updatedAt,isDraft,labels,reviewRequests,statusCheckRollup",
            "--state", "all", "--limit", "100"
        ])
        let prs = try PRParser.parseList(result.stdout)
        Logger.gitRepository.info("Fetched \(prs.count, privacy: .public) pull requests in \(self.displayName, privacy: .public)")
        return prs
    }

    /// Only what branch rows show, so it stays a small response even for busy repositories.
    func openPullRequests() async throws -> [String: OpenPullRequest] {
        let result = try await ghRun([
            "pr", "list", "--state", "open", "--limit", "500", "--json", "number,title,headRefName,isDraft,url"
        ])
        return try OpenPullRequest.index(fromJSON: Data(result.stdout.utf8))
    }

    func pullRequestDetail(number: Int) async throws -> PullRequestInfo {
        Logger.gitRepository.info("Fetching PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "view", "\(number)",
            "--json", "number,title,body,author,state,headRefName,baseRefName,createdAt,updatedAt,isDraft,labels,reviewRequests,statusCheckRollup"
        ])
        return try PRParser.parseSingle(result.stdout)
    }

    func pullRequestComments(number: Int) async throws -> [PRComment] {
        Logger.gitRepository.info("Fetching comments for PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "view", "\(number)",
            "--json", "comments,reviews"
        ])
        return try PRParser.parseComments(result.stdout)
    }

    func checkoutPullRequest(number: Int) async throws {
        Logger.gitRepository.info("Checking out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "checkout", "\(number)"])
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
        Logger.gitRepository.info("Checked out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    func closePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Closing PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "close", "\(number)"])
        Logger.gitRepository.info("Closed PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    func mergePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Merging PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "merge", "\(number)", "--merge"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Merged PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    func createPullRequest(_ draft: PullRequestDraft) async throws -> String {
        Logger.gitRepository.info("Creating PR \(draft.head, privacy: .public) → \(draft.base, privacy: .public)")
        let result = try await ghRun(GitHubCLI.createPullRequestArguments(draft))
        // gh prints progress lines before the URL; the URL is the last line.
        return result.stdout.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    }
}
