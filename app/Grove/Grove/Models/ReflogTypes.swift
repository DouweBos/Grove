// Models/ReflogTypes.swift
// Grove
//
// Reflog entry type.

import Foundation

// MARK: - ReflogEntry

/// One entry from `git reflog`.
struct ReflogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let oldSHA: String
    let newSHA: String
    let committerName: String
    let committerEmail: String
    let date: Date
    let message: String
}
