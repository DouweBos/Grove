// Engine/GitRepositoryProtocol+Defaults.swift
// GroveKit
//
// What GitRepositoryProtocol's conformers get without implementing it.

import Foundation

// MARK: - GitRepositoryProtocol Default Arguments

/// Convenience overloads that supply `sign: false` so existing call sites
/// that were written before signing support was added continue to compile
/// without modification.
extension GitRepositoryProtocol {

    // Defaults so lightweight test doubles only implement what they exercise.
    // TODO: A method GitRepository forgets to implement silently falls back to one of these.
    public func log(maxCount: Int, skip: Int, revisions: [String]) async throws -> [CommitInfo] {
        try await log(maxCount: maxCount, skip: skip, branch: revisions.first)
    }

    public func commits(in revision: String, notIn base: String) async throws -> Set<String> { [] }
    public func isAncestor(_ commit: String, of descendant: String) async -> Bool { false }
    public func formatPatch(commits: [String]) async throws -> String { "" }
    public func filePaths(inHistoryOf path: String, maxCount: Int) async throws -> [String: String] { [:] }
    public func archive(revision: String, to url: URL) async throws {}

    @discardableResult
    public func commit(message: String, body: String?, amend: Bool, sign: Bool, signOff: Bool) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: sign)
    }

    public func commitIdentity() async -> CommitIdentity? { nil }
    public func operationContext() async -> OperationContext? { nil }
    public func continueOperation() async throws {}
    public func conflictVersions(path: String) async throws -> ConflictVersions { ConflictVersions() }
    public func resolveConflict(path: String, side: ConflictSide) async throws {}

    @discardableResult
    public func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: false)
    }

    @discardableResult
    public func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo {
        try await createTag(name: name, at: sha, message: message, sign: false)
    }

    public func filesInCommit(_ sha: String) async throws -> [String] { [] }

    public func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff] {
        try await diffForCommit(sha).filter { $0.path == path || $0.diff?.oldPath == path }
    }

    public func stashDiff(index: Int) async throws -> [FileDiff] { [] }
    public func submodules() async throws -> [SubmoduleInfo] { [] }
    public func initSubmodule(path: String) async throws {}
    public func updateSubmodule(path: String, toRemote: Bool) async throws {}
    public func fetchSubmodule(path: String) async throws {}
    public func addSubmodule(url: String, path: String, branch: String?) async throws {}
    public func removeSubmodule(path: String) async throws {}
    public func worktrees() async throws -> [WorktreeInfo] { [] }
    @discardableResult
    public func createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?) async throws -> BranchInfo {
        try await createBranch(name: name, from: from, checkout: checkout)
    }
    public func branchParents() async throws -> [String: String] { [:] }
    public func branchPullRequests() async throws -> [BranchPullRequest] { [] }
    public func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        try await pull(remote: remote, strategy: strategy, progress: progress)
    }
    public func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        try await push(remote: remote, forceWithLease: forceWithLease, setUpstream: setUpstream, progress: progress)
    }
    public func pruneWorktrees() async throws {}
    public func fileContents(path: String, revision: String?) async throws -> String { "" }
    public func fileData(path: String, at revision: FileRevision) async throws -> Data { Data() }
    public func mergedBranches(into base: String) async throws -> Set<String> { [] }
    public func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int) { (0, 0) }
    public func branchTips() async throws -> [BranchTip] { [] }
    public func aheadBehind(branches: [String], base: String) async throws -> [String: AheadBehind] { [:] }
    public func compareBranches(base: String, compare: String) async throws -> BranchComparison { BranchComparison() }
    public func defaultPullStrategy() async -> PullStrategy { .merge }
    public func localConfigValue(_ key: String) async throws -> String? { nil }
    public func setLocalConfigValue(_ key: String, to value: String?) async throws {}
    public func setRemoteURL(_ url: String, forRemote name: String) async throws {}
    public func addRemote(name: String, url: String) async throws {}
    public func setUpstream(of branch: String, to remoteBranch: String?) async throws {}
    public func removeRemote(name: String) async throws {}
    public func pullRequestDiff(number: Int) async throws -> [FileDiff] { [] }
    public func pullRequestCommits(number: Int) async throws -> [CommitInfo] { [] }
    public func lfsStatus() async -> LFSStatus { LFSStatus() }
    public func lfsTrackedPaths(among paths: [String]) async -> Set<String> { [] }
    public func trackWithLFS(pattern: String, literal: Bool) async throws {}
    public func gitFlowConfig() async -> GitFlowConfig? { nil }
    public func initializeGitFlow(_ config: GitFlowConfig) async throws {}
    public func startFlowBranch(_ kind: GitFlowKind, name: String, base: String?, config: GitFlowConfig) async throws {}
    public func finishFlowBranch(_ kind: GitFlowKind, name: String, config: GitFlowConfig, options: GitFlowFinishOptions) async throws {}
    public func svnStatus() async -> SVNStatus { SVNStatus() }
    public func svnFetch(rebase: Bool) async throws {}
    public func svnDcommit() async throws {}
    public func fastForward(branch: String, fromRemote remote: String, branch remoteBranch: String) async throws {}
    public func push(branch: String, to remote: String, as remoteBranch: String, setUpstream: Bool) async throws {}
    public func createPullRequest(_ draft: PullRequestDraft) async throws -> String { "" }
    public func commentOnPullRequest(number: Int, body: String) async throws {}
    public func hostingService() async -> HostingServiceKind? { .github }
    public func pullRequestWebURL(number: Int) async throws -> URL? { nil }
    public func pullRequestReviewComments(number: Int) async throws -> [PRReviewComment] { [] }
    public func publishBranch(_ name: String, to remote: String, as target: String) async throws {}
    public func defaultBranch(of remote: String) async -> String? { nil }
}
