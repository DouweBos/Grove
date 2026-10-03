// Models/ReflogTypes.swift
// GroveKit
//
// Reflog entry type.

import Foundation

// MARK: - ReflogEntry

/// One entry from `git reflog`.
public struct ReflogEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let oldSHA: String
    public let newSHA: String
    let committerName: String
    let committerEmail: String
    public let date: Date
    public let message: String
}
