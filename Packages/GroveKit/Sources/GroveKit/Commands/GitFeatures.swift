// Commands/GitFeatures.swift
// GroveKit

/// One thing a session's git may or may not support.
public nonisolated enum GitFeature: String, CaseIterable, Sendable {
    case createBranch, editBranches, checkout, merge, rebase, push, tag, remotes, submodules, bisect
    case skipHooks, autostash, cancel, verifySignatures, recurseSubmodules
    case reveal, trash, export, applyPatch
}

/// What the host app supports for one repository. The views and the commands both check it.
public nonisolated struct GitFeatures: Sendable, Equatable {
    public private(set) var supported: Set<GitFeature>
    /// Why a missing feature is missing, shown where it would have been.
    public private(set) var reasons: [GitFeature: String]

    public static let all = GitFeatures()

    public init() {
        supported = Set(GitFeature.allCases)
        reasons = [:]
    }

    public mutating func remove(_ features: Set<GitFeature>, reason: String) {
        supported.subtract(features)
        for feature in features { reasons[feature] = reason }
    }

    public func contains(_ feature: GitFeature) -> Bool { supported.contains(feature) }

    public func unavailableReason(_ feature: GitFeature) -> String? {
        contains(feature) ? nil : reasons[feature] ?? "Not available for this repository"
    }
}
