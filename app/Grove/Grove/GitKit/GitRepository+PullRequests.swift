// GitKit/GitRepository+PullRequests.swift
// Grove
//
// Pull requests through whichever service the repository's remote points at.

import Foundation
import os

extension GitRepository {

    /// Read each time so a remote added or changed in Settings takes effect at once.
    private func resolvedHost() async throws -> (host: any PullRequestHost, remote: String) {
        try PullRequestHostResolver.resolve(remotes: try await remotes(), directory: path)
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

    func openPullRequests() async throws -> [String: OpenPullRequest] {
        try await host().openPullRequests()
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

    /// Services without a checkout command get a fetch of the source branch and a tracking branch for it.
    func checkoutPullRequest(number: Int) async throws {
        Logger.gitRepository.info("Checking out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let (host, remote) = try await resolvedHost()
        if try await !host.checkout(number: number) {
            let branch = try await host.pullRequest(number: number).sourceBranch
            try await shell.run(["fetch", remote, branch])
            let hasLocal = try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"]).isSuccess
            try await shell.run(hasLocal ? ["checkout", branch] : ["checkout", "-b", branch, "--track", "\(remote)/\(branch)"])
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

    func commentOnPullRequest(number: Int, body: String) async throws {
        Logger.gitRepository.info("Commenting on PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await host().comment(number: number, body: body)
    }
}
