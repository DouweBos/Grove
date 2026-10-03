// Domain/Hosting/CIHost.swift
// Grove
//
// One service's CI/CD API. GitHub Actions is the only provider so far; the others answer "not supported yet".

import Foundation
import GroveKit

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
