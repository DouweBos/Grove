// Engine/GitNaming.swift
// GroveKit

import Foundation

/// Names for what GroveKit writes: scratch files, state kept in the git directory, branch config.
/// Apps working on the same repositories should pass the same values to see each other's restacks and branch parents.
public nonisolated struct GitNaming: Sendable, Hashable {
    /// Prefix of scratch files in the runner's temporary directory.
    public var scratchPrefix: String
    /// Folder under the git directory for state that outlives one command, such as a running restack's plan.
    public var stateDirectory: String
    /// Branch config key recording a branch's parent: `branch.<name>.<parentKey>`.
    public var parentKey: String

    public init(scratchPrefix: String, stateDirectory: String, parentKey: String) {
        self.scratchPrefix = scratchPrefix
        self.stateDirectory = stateDirectory
        self.parentKey = parentKey
    }

    /// `<name>-` scratch files, a `<name>` state folder and `<name>-parent` branch config.
    public init(name: String) {
        self.init(scratchPrefix: "\(name)-", stateDirectory: name, parentKey: "\(name)-parent")
    }

    public static let `default` = GitNaming(name: "grovekit")
}
