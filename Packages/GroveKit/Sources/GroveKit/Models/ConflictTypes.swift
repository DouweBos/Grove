// Models/ConflictTypes.swift
// GroveKit
//
// Types describing an in-progress merge, rebase, cherry-pick or revert.

import Foundation

/// Which side of a conflict to keep. `ours` is index stage 2, `theirs` stage 3.
enum ConflictSide: Equatable, Sendable {
    case ours
    case theirs
}

/// Human-readable names for both sides of an in-progress operation.
struct OperationContext: Equatable, Sendable {
    /// Label for stage 2 (HEAD): the current branch, or the upstream during a rebase.
    var oursLabel: String
    /// Label for stage 3: the incoming branch or commit being applied.
    var theirsLabel: String
}

/// The two conflicting versions of one file. `nil` when that side deleted the file.
struct ConflictVersions: Equatable, Sendable {
    var ours: String?
    var theirs: String?
}

/// The identity git will record as author for new commits.
struct CommitIdentity: Equatable, Sendable {
    var name: String
    var email: String

    var initial: String { String(name.prefix(1)).uppercased() }
}
