// GitKit/GitRepository+PullRequests.swift
// Grove
//
// Pull requests through whichever service the repository's remote points at.

import Foundation
import os

extension GitRepository {

    /// Read each time so a remote added or changed in Settings takes effect at once.
    private func resolvedHost() async throws -> (host: any PullRequestHost, remote: String) {
        try PullRequestHostResolver.resolve(remotes: try await remotes())
    }

    private func host() async throws -> any PullRequestHost {
        try await resolvedHost().host
    }

    func hostingService() async -> HostingServiceKind? {
        PullRequestHostResolver.service(of: (try? await remotes()) ?? [])
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        Logger.gitRepository.info("Fetching pull requests in \(self.displayName, privacy: .public)")
        let prs = try await host().pullRequests()
        Logger.gitRepository.info("Fetched \(prs.count, privacy: .public) pull requests in \(self.displayName, privacy: .public)")
        return prs
    }

    func branchPullRequests() async throws -> [BranchPullRequest] {
        try await host().branchPullRequests()
    }

    func pullRequestDetail(number: Int) async throws -> PullRequestInfo {
        try await host().pullRequest(number: number)
    }

    func pullRequestComments(number: Int) async throws -> [PRComment] {
        try await host().comments(number: number)
    }

    func pullRequestReviewComments(number: Int) async throws -> [PRReviewComment] {
        try await host().reviewComments(number: number)
    }

    func pullRequestCommits(number: Int) async throws -> [CommitInfo] {
        try await host().commits(number: number)
    }

    /// The service's diff, or for services without one the branches' diff after fetching both.
    func pullRequestDiff(number: Int) async throws -> [FileDiff] {
        let (host, remote) = try await resolvedHost()
        if let patch = try await host.diff(number: number) {
            return DiffParser.parse(patch).map { FileDiff(path: $0.filePath, status: Self.inferStatus($0), diff: $0, stats: $0.stats) }
        }
        let pr = try await host.pullRequest(number: number)
        try await shell.run(["fetch", remote, pr.sourceBranch, pr.targetBranch])
        let range = "\(remote)/\(pr.targetBranch)...\(remote)/\(pr.sourceBranch)"
        let patch = try await shell.run(["diff", "--no-color", "-M", range]).stdout
        let names = try await shell.run(["diff", "--name-status", "-M", range]).stdout
        return Self.fileDiffs(patch: patch, nameStatus: names)
    }

    func pullRequestWebURL(number: Int) async throws -> URL? {
        try await host().webURL(number: number)
    }

    /// Fetches the pull request's head with git and checks it out as its source branch. The service's head ref
    /// (`refs/pull/N/head`) also works for forks; without one the source branch is fetched and tracked.
    func checkoutPullRequest(number: Int) async throws {
        Logger.gitRepository.info("Checking out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let (host, remote) = try await resolvedHost()
        let branch = try await host.pullRequest(number: number).sourceBranch
        let hasLocal = try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"]).isSuccess
        let onRemote = try await shell.runAllowingFailure(["ls-remote", "--exit-code", "--heads", remote, branch]).isSuccess
        for step in Self.checkoutSteps(branch: branch, remote: remote, headRef: host.headRef(number: number),
                                       hasLocalBranch: hasLocal, branchOnRemote: onRemote) {
            try await shell.run(step)
        }
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func closePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Closing PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await host().close(number: number)
    }

    func mergePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Merging PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await host().merge(number: number)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    func createPullRequest(_ draft: PullRequestDraft) async throws -> String {
        Logger.gitRepository.info("Creating PR \(draft.head, privacy: .public) → \(draft.base, privacy: .public)")
        return try await host().create(draft)
    }

    func updatePullRequestBase(number: Int, base: String) async throws {
        Logger.gitRepository.info("Retargeting PR #\(number, privacy: .public) onto \(base, privacy: .public)")
        try await host().updateBase(number: number, base: base)
    }

    func commentOnPullRequest(number: Int, body: String) async throws {
        Logger.gitRepository.info("Commenting on PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await host().comment(number: number, body: body)
    }

    /// The git commands that bring a pull request's head into `branch`: a tracking branch when the branch is on the remote,
    /// otherwise the head ref fetched into it; an existing branch is checked out and fast-forwarded.
    nonisolated static func checkoutSteps(branch: String, remote: String, headRef: String?, hasLocalBranch: Bool,
                                          branchOnRemote: Bool) -> [[String]] {
        if branchOnRemote {
            return [["fetch", remote, branch],
                    hasLocalBranch ? ["checkout", branch] : ["checkout", "-b", branch, "--track", "\(remote)/\(branch)"]]
                + (hasLocalBranch ? [["merge", "--ff-only", "\(remote)/\(branch)"]] : [])
        }
        let ref = headRef ?? branch
        if hasLocalBranch {
            return [["checkout", branch], ["fetch", remote, ref], ["merge", "--ff-only", "FETCH_HEAD"]]
        }
        return [["fetch", remote, "\(ref):refs/heads/\(branch)"], ["checkout", branch]]
    }
}
