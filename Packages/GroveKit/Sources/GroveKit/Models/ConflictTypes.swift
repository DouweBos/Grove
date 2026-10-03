// Models/ConflictTypes.swift
// GroveKit
//
// Types describing an in-progress merge, rebase, cherry-pick or revert.

import Foundation

/// Which side of a conflict to keep. `ours` is index stage 2, `theirs` stage 3.
public enum ConflictSide: Equatable, Sendable {
    case ours
    case theirs
}

/// Human-readable names for both sides of an in-progress operation.
public struct OperationContext: Equatable, Sendable {
    /// Label for stage 2 (HEAD): the current branch, or the upstream during a rebase.
    public var oursLabel: String
    /// Label for stage 3: the incoming branch or commit being applied.
    public var theirsLabel: String
}

/// The two conflicting versions of one file. `nil` when that side deleted the file.
public struct ConflictVersions: Equatable, Sendable {
    public var ours: String?
    public var theirs: String?

    public init(ours: String? = nil, theirs: String? = nil) {
        self.ours = ours
        self.theirs = theirs
    }
}

/// The identity git will record as author for new commits.
public struct CommitIdentity: Equatable, Sendable {
    public var name: String
    public var email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    var initial: String { String(name.prefix(1)).uppercased() }
}
