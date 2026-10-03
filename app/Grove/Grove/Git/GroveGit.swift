// Git/GroveGit.swift
// Grove
//
// How Grove runs GroveKit: git on this Mac with Grove's environment, and pull requests and CI through Grove's accounts.

import Foundation
import GroveKit

extension LocalGitRunner {
    /// Every git process Grove starts: the user's environment variables and 1Password settings,
    /// then hosting account credentials, both read per launch so changes apply to the next command.
    nonisolated static let grove = LocalGitRunner { workingDirectory, base in
        var env = GitEnvironment.variables(forRepositoryAt: workingDirectory.path, base: base)
        for (key, value) in GitCredentials.environment() {
            env[key] = value
        }
        return env
    }
}

extension GitShell {
    /// A shell running git the way the rest of Grove does.
    nonisolated convenience init(workingDirectory: URL, extraEnvironment: [String: String] = [:]) {
        self.init(workingDirectory: workingDirectory, runner: LocalGitRunner.grove, extraEnvironment: extraEnvironment)
    }
}

extension GitRepository {
    /// Opens a repository with Grove's runner and hosting accounts.
    convenience init(path: URL) async throws {
        try await self.init(path: path, runner: LocalGitRunner.grove, hosting: GroveRepositoryHosting())
    }
}

/// Pull requests and CI through the accounts in Settings.
struct GroveRepositoryHosting: RepositoryHosting {
    func pullRequestHost(for remotes: [RemoteInfo]) throws -> (host: any PullRequestHost, remote: String) {
        try PullRequestHostResolver.resolve(remotes: remotes)
    }

    func ciHost(for remotes: [RemoteInfo]) throws -> any CIHost {
        try CIHostResolver.resolve(remotes: remotes)
    }

    func service(of remotes: [RemoteInfo]) -> HostingServiceKind? {
        PullRequestHostResolver.service(of: remotes)
    }
}
