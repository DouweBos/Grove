// Models/StashTypes.swift
// Grove
//
// Stash entry type.

import Foundation

// MARK: - StashEntry

/// A single entry in the stash list.
struct StashEntry: Identifiable, Hashable, Sendable {
    /// Zero-based stash index (stash@{0} = 0).
    let id: Int
    let message: String
    let sha: String
    let date: Date
    /// Branch name from which the stash was created, if available.
    let branchName: String?
}
