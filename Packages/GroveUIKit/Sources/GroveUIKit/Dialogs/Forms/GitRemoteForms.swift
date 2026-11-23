// Dialogs/Forms/GitRemoteForms.swift
// GroveUIKit
//
// Fetch, pull, push and sync.

#if os(macOS)
import Foundation
import GroveKit

public struct GitFetchForm: GitDialogForm, Equatable {
    public var remote: String
    public var allRemotes: Bool

    public init(remotes: [RemoteInfo]) {
        remote = remotes.first?.name ?? "origin"
        allRemotes = remotes.count > 1
    }

    public var commands: [GitCommand] { [.fetch(remote: allRemotes ? nil : remote)] }
}

public struct GitPullForm: GitDialogForm, Equatable {
    /// `remote/branch`, or `./branch` for a local one.
    public var source: String?
    public let upstream: String?
    /// Nil until git says what a plain pull does.
    public var strategy: PullStrategy?
    /// Stashes uncommitted changes first and restores them afterwards.
    public var autoStash = false
    public var options = PullOptions()
    private let remoteNames: [String]

    public init(branch: BranchInfo?, remoteBranches: [BranchInfo], remotes: [RemoteInfo], strategy: PullStrategy?) {
        upstream = branch?.upstreamShortName
        source = Self.defaultSource(for: branch, in: remoteBranches)
        remoteNames = remotes.map(\.name)
        self.strategy = strategy
    }

    public var commands: [GitCommand] { commands(stashed: false) }

    public func commands(stashed: Bool) -> [GitCommand] {
        guard let source, let strategy else { return [] }
        let pull: GitCommand
        if source == upstream {
            pull = .pull(remote: nil, branch: nil, strategy: strategy, options: options)
        } else if let target = split(source) {
            pull = .pull(remote: target.remote, branch: target.branch, strategy: strategy, options: options)
        } else {
            return []
        }
        return stashed ? [.stash(message: Self.stashMessage, includeUntracked: true, keepIndex: false, paths: nil), pull,
                          .applyStash(index: 0, drop: true)] : [pull]
    }

    public func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(in: context)
        let stashed = autoStash ? try await stashIfDirty(context, message: Self.stashMessage) : false
        // The stash already ran; what's left is the pull and, after it, the pop.
        try await perform(Array(commands(stashed: stashed).dropFirst(stashed ? 1 : 0)), in: context, progress: progress)
    }

    static let stashMessage = "Auto-stash before pull"

    /// `origin/feature/x` → ("origin", "feature/x"), matching against known remote names.
    private func split(_ source: String) -> (remote: String, branch: String)? {
        let remote = remoteNames.sorted { $0.count > $1.count }.first { source.hasPrefix($0 + "/") }
            ?? source.split(separator: "/", maxSplits: 1).first.map(String.init)
        guard let remote, source.count > remote.count + 1 else { return nil }
        return (remote, String(source.dropFirst(remote.count + 1)))
    }

    /// Branch names teams usually integrate from, in the order they're suggested.
    static let mainlineNames = ["main", "master", "develop", "trunk"]

    /// The upstream, else a same-named remote branch, else the first remote's mainline.
    public static func defaultSource(for branch: BranchInfo?, in branches: [BranchInfo]) -> String? {
        if let upstream = branch?.upstreamShortName { return upstream }
        let names = branches.map(\.name).sorted()
        if let branch, let twin = names.first(where: { $0.hasSuffix("/" + branch.name) }) { return twin }
        for mainline in mainlineNames {
            if let match = names.first(where: { $0.hasSuffix("/" + mainline) && $0.split(separator: "/").count == 2 }) {
                return match
            }
        }
        return nil
    }
}

public struct GitPushForm: GitDialogForm, Equatable {
    /// The local branch pushed.
    public let branch: String
    /// Whether it's checked out, which pushes HEAD.
    public let isHead: Bool
    public let upstream: String?
    public var remote: String
    /// The branch's name on the remote.
    public var target: String
    public var setUpstream: Bool
    public var forceWithLease = false
    public var tags = PushTags.none
    public var recurseSubmodules: SubmodulePushMode?
    public var skipHooks = false

    public init(branch: BranchInfo, isHead: Bool, remotes: [RemoteInfo]) {
        self.branch = branch.name
        self.isHead = isHead
        upstream = branch.upstreamShortName
        let names = remotes.map(\.name)
        remote = branch.upstreamRemoteName ?? (names.contains("origin") ? "origin" : names.first) ?? "origin"
        target = Self.defaultTarget(for: branch, on: remote)
        setUpstream = branch.upstream == nil
    }

    /// The upstream's branch name when it lives on `remote`, else the local branch's name.
    static func defaultTarget(for branch: BranchInfo, on remote: String) -> String {
        if let upstream = branch.upstreamShortName, branch.upstreamRemoteName == remote {
            return String(upstream.dropFirst(remote.count + 1))
        }
        return branch.name
    }

    public var options: PushOptions { PushOptions(recurseSubmodules: recurseSubmodules, skipHooks: skipHooks, tags: tags) }
    var destination: String { "\(remote)/\(target.trimmed)" }

    public var commands: [GitCommand] {
        let name = target.trimmed
        guard !name.isEmpty else { return [] }
        return isHead
            ? [.push(remote: remote, branch: name, forceWithLease: forceWithLease, setUpstream: setUpstream, options: options)]
            : [.pushBranch(branch, remote: remote, as: name, forceWithLease: forceWithLease, setUpstream: setUpstream,
                           options: options)]
    }
}

public struct GitSyncForm: GitDialogForm, Equatable {
    public var remote: String
    public var strategy: PullStrategy?

    public init(branch: BranchInfo?, remotes: [RemoteInfo], strategy: PullStrategy?) {
        remote = branch?.upstreamRemoteName ?? remotes.first?.name ?? "origin"
        self.strategy = strategy
    }

    public var commands: [GitCommand] {
        strategy.map { [.sync(remote: remote, strategy: $0)] } ?? []
    }
}
#endif
