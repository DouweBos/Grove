// Models/StashTypes.swift
// GroveKit
//
// Stash entry type.

import Foundation

// MARK: - StashEntry

/// A single entry in the stash list.
public struct StashEntry: Identifiable, Hashable, Sendable {
    /// Zero-based stash index (stash@{0} = 0).
    public let id: Int
    public let message: String
    public let sha: String
    public let date: Date
    /// Branch name from which the stash was created, if available.
    public let branchName: String?
}
