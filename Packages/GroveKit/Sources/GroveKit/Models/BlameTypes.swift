// Models/BlameTypes.swift
// GroveKit
//
// Blame annotation types.

import Foundation

// MARK: - BlameEntry

/// One contiguous block of lines in a blame annotation sharing the same commit.
struct BlameEntry: Identifiable, Hashable, Sendable {
    let id: String
    let lineStart: Int
    let lineCount: Int
    let commitSHA: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let summary: String
    /// Original file path when the code was introduced (for rename tracking).
    let originalPath: String?
}
