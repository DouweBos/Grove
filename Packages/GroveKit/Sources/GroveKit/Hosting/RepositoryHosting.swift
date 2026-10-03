// Hosting/RepositoryHosting.swift
// GroveKit
//
// Pull requests and CI live on a code host, not in git; the app plugs in how a repository's remotes reach one.

import Foundation

/// Finds the host behind a repository's remotes. Read on every call, so a remote added or changed takes effect at once.
@MainActor
public protocol RepositoryHosting {
    /// The pull request API for `remotes`, and the remote it was found through.
    func pullRequestHost(for remotes: [RemoteInfo]) throws -> (host: any PullRequestHost, remote: String)
    /// The CI API for `remotes`.
    func ciHost(for remotes: [RemoteInfo]) throws -> any CIHost
    /// Which service `remotes` point at, if any.
    func service(of remotes: [RemoteInfo]) -> HostingServiceKind?
}

/// No code host: pull requests and CI behave as for a repository without a hosted remote.
public struct NoRepositoryHosting: RepositoryHosting {
    public nonisolated init() {}
    public func pullRequestHost(for remotes: [RemoteInfo]) throws -> (host: any PullRequestHost, remote: String) {
        throw HostingError.noHostedRemote
    }
    public func ciHost(for remotes: [RemoteInfo]) throws -> any CIHost { throw HostingError.noHostedRemote }
    public func service(of remotes: [RemoteInfo]) -> HostingServiceKind? { nil }
}

/// Pull requests of one repository on its hosting service.
public nonisolated protocol PullRequestHost: Sendable {
    var kind: HostingServiceKind { get }
    func pullRequests() async throws -> [PullRequestInfo]
    /// Open and merged pull requests, as small rows for branch lists and stacks.
    func branchPullRequests() async throws -> [BranchPullRequest]
    func pullRequest(number: Int) async throws -> PullRequestInfo
    func comments(number: Int) async throws -> [PRComment]
    func reviewComments(number: Int) async throws -> [PRReviewComment]
    func commits(number: Int) async throws -> [CommitInfo]
    /// Unified diff of the pull request; nil when the service has none, so the branches are diffed locally.
    func diff(number: Int) async throws -> String?
    func merge(number: Int) async throws
    func close(number: Int) async throws
    /// Points the pull request at another base branch, as when the branch below it merged.
    func updateBase(number: Int, base: String) async throws
    func comment(number: Int, body: String) async throws
    /// Opens a pull request and returns its web URL.
    func create(_ draft: PullRequestDraft) async throws -> String
    func webURL(number: Int) async throws -> URL?
    /// A ref the remote keeps for the pull request's head (`refs/pull/N/head`), which also covers forks;
    /// nil where there is none and the source branch is fetched instead.
    func headRef(number: Int) -> String?
}

extension PullRequestHost {
    public func headRef(number: Int) -> String? { nil }
}

/// Why a repository's hosting service can't be reached.
public nonisolated enum HostingError: LocalizedError, Equatable {
    /// No remote points at a service Grove knows.
    case noHostedRemote
    /// The service needs an account in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    /// The stored token was refused.
    case notSignedIn(HostingServiceKind)
    case unsupported(String)
    /// The service is known, but Grove can't read its CI yet.
    case ciUnsupported(HostingServiceKind)
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .noAccount(let kind, let host): "Add a \(kind.displayName) account for \(host) in Settings > Accounts."
        case .notSignedIn(let kind): "\(kind.displayName) refused the sign-in. Sign in again in Settings > Accounts."
        case .unsupported(let message): message
        case .ciUnsupported(let kind): "Grove doesn't show CI runs from \(kind.displayName) yet."
        case .http(let status, let message): message.isEmpty ? "The server answered \(status)." : message
        }
    }
}

/// Workflow runs of one repository on its hosting service.
public nonisolated protocol CIHost: Sendable {
    var kind: HostingServiceKind { get }
    func workflows() async throws -> [CIWorkflow]
    /// The newest runs matching `query`, newest first.
    func runs(_ query: CIRunQuery) async throws -> [CIRun]
    func run(id: Int) async throws -> CIRun
    /// Jobs of the run's latest attempt, with their steps.
    func jobs(runID: Int) async throws -> [CIJob]
    /// Notes the finished job left, such as warnings and test failures.
    func annotations(jobID: Int) async throws -> [CIAnnotation]
    /// The job's whole log as plain text; only there once the job has finished.
    func log(jobID: Int) async throws -> String
    func artifacts(runID: Int) async throws -> [CIArtifact]
    /// How CI went for each branch's newest commit, keyed by branch, for branch rows.
    func branchStatuses() async throws -> [String: BranchCIStatus]
    /// Saves the artifact's zip at `destination`.
    func downloadArtifact(id: Int, to destination: URL) async throws
    /// Starts a new attempt of the run: every job, or only the failed ones and those depending on them.
    func rerun(runID: Int, failedOnly: Bool) async throws
    func cancel(runID: Int) async throws
    /// The workflow's definition as it is on `ref`, to read the inputs it asks for.
    func workflowFile(path: String, ref: String) async throws -> String
    /// Starts a workflow by hand. The host answers without saying which run that became.
    func dispatch(_ dispatch: CIDispatch) async throws
}
