// Domain/Hosting/CIHost.swift
// Grove
//
// One service's CI/CD API. GitHub Actions is the only provider so far; the others answer "not supported yet".

import Foundation

/// Workflow runs of one repository on its hosting service.
nonisolated protocol CIHost: Sendable {
    var kind: HostingServiceKind { get }
    func workflows() async throws -> [CIWorkflow]
    /// The newest runs matching `query`, newest first.
    func runs(_ query: CIRunQuery) async throws -> [CIRun]
    func run(id: Int) async throws -> CIRun
    /// Jobs of the run's latest attempt, with their steps.
    func jobs(runID: Int) async throws -> [CIJob]
    func artifacts(runID: Int) async throws -> [CIArtifact]
}

@MainActor
enum CIHostResolver {

    /// The CI host behind the remote pull requests use (origin first).
    static func resolve(remotes: [RemoteInfo], accounts: HostingAccountStore? = nil,
                        http: any HTTPClient = URLSessionHTTPClient()) throws -> any CIHost {
        guard let (_, location) = HostedRemoteResolver.location(of: remotes) else { throw HostingError.noHostedRemote }
        // Before credentials: an account wouldn't help on a service Grove can't read CI from.
        guard location.kind == .github else { throw HostingError.ciUnsupported(location.kind) }
        return GitHubCIHost(location: location, client: try HostedRemoteResolver.client(for: location, accounts: accounts ?? .shared, http: http))
    }
}
