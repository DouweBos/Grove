// Models/HostingService.swift
// GroveKit

import Foundation

/// The code hosts GroveKit talks to for pull requests and hosted repositories.
public nonisolated enum HostingServiceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case github, gitlab, bitbucket, azureDevOps

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .bitbucket: "Bitbucket"
        case .azureDevOps: "Azure DevOps"
        }
    }

    /// GitLab calls them merge requests.
    public var pullRequestNoun: String { self == .gitlab ? "Merge Request" : "Pull Request" }

    public var symbol: String {
        switch self {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .gitlab: "square.stack.3d.up"
        case .bitbucket: "shippingbox"
        case .azureDevOps: "cloud"
        }
    }

    /// Hosts whose name says which service they are; self-hosted GitHub or GitLab usually carry it in the name.
    static func detect(host: String) -> HostingServiceKind? {
        let host = host.lowercased()
        if host == "github.com" || host.hasSuffix(".github.com") || host.contains("github") { return .github }
        if host == "bitbucket.org" { return .bitbucket }
        if host == "dev.azure.com" || host == "ssh.dev.azure.com" || host.hasSuffix(".visualstudio.com") { return .azureDevOps }
        if host.contains("gitlab") { return .gitlab }
        return nil
    }
}

/// Where a remote URL points: which service, and the repository on it.
public nonisolated struct RemoteLocation: Hashable, Sendable {
    public let kind: HostingServiceKind
    public let host: String
    /// GitHub owner, GitLab namespace (may contain slashes), Bitbucket workspace, Azure organization.
    public let owner: String
    public let name: String
    /// Azure DevOps only: the project that holds the repository.
    public var project: String?

    public init(kind: HostingServiceKind, host: String, owner: String, name: String, project: String? = nil) {
        self.kind = kind
        self.host = host
        self.owner = owner
        self.name = name
        self.project = project
    }

    public var fullName: String { "\(owner)/\(name)" }

    /// Parses https, ssh and scp-style remote URLs; nil for local paths and unknown hosts.
    public static func parse(_ url: String) -> RemoteLocation? {
        guard let (host, path) = split(url) else { return nil }
        guard let kind = HostingServiceKind.detect(host: host) else { return nil }
        var parts = path.split(separator: "/").map(String.init)
        if let last = parts.last, last.hasSuffix(".git") { parts[parts.count - 1] = String(last.dropLast(4)) }
        switch kind {
        case .azureDevOps:
            return azure(host: host, parts: parts)
        case .gitlab:
            guard parts.count >= 2 else { return nil }
            return RemoteLocation(kind: kind, host: host, owner: parts.dropLast().joined(separator: "/"), name: parts[parts.count - 1])
        case .github, .bitbucket:
            guard parts.count >= 2 else { return nil }
            return RemoteLocation(kind: kind, host: host, owner: parts[0], name: parts[1])
        }
    }

    /// `dev.azure.com/org/project/_git/repo`, `org.visualstudio.com/project/_git/repo`, `ssh.dev.azure.com:v3/org/project/repo`.
    private static func azure(host: String, parts: [String]) -> RemoteLocation? {
        if host == "ssh.dev.azure.com" || host.hasPrefix("vs-ssh.") {
            guard parts.count >= 4, parts[0] == "v3" else { return nil }
            return RemoteLocation(kind: .azureDevOps, host: "dev.azure.com", owner: parts[1], name: parts[3], project: parts[2])
        }
        guard let git = parts.firstIndex(of: "_git"), git + 1 < parts.count else { return nil }
        if host.hasSuffix(".visualstudio.com") {
            let organization = String(host.dropLast(".visualstudio.com".count))
            guard git >= 1 else { return nil }
            return RemoteLocation(kind: .azureDevOps, host: "dev.azure.com", owner: organization, name: parts[git + 1],
                                  project: parts[git - 1])
        }
        guard git >= 2 else { return nil }
        return RemoteLocation(kind: .azureDevOps, host: host, owner: parts[0], name: parts[git + 1], project: parts[git - 1])
    }

    /// Host and path of a remote URL, with scheme, user and port removed.
    private static func split(_ url: String) -> (String, String)? {
        var rest = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.hasPrefix("/"), !rest.hasPrefix("file:"), !rest.hasPrefix("."), !rest.hasPrefix("~") else { return nil }
        var scpStyle = true
        for scheme in ["https://", "http://", "ssh://", "git://"] where rest.lowercased().hasPrefix(scheme) {
            rest = String(rest.dropFirst(scheme.count))
            scpStyle = false
        }
        if let at = rest.firstIndex(of: "@"), !rest[..<at].contains("/") {
            rest = String(rest[rest.index(after: at)...])
        }
        let separator: Character = scpStyle ? ":" : "/"
        guard let cut = rest.firstIndex(of: separator) else { return nil }
        var host = String(rest[..<cut]).lowercased()
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        let path = String(rest[rest.index(after: cut)...])
        return host.isEmpty ? nil : (host, path)
    }
}
