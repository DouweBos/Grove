// Models/BlameTypes.swift
// GroveKit
//
// Blame annotation types.

import Foundation

// MARK: - BlameEntry

/// One contiguous block of lines in a blame annotation sharing the same commit.
public struct BlameEntry: Identifiable, Hashable, Sendable {
    public let id: String
    let lineStart: Int
    let lineCount: Int
    public let commitSHA: String
    public let authorName: String
    let authorEmail: String
    public let authorDate: Date
    public let summary: String
    /// Original file path when the code was introduced (for rename tracking).
    let originalPath: String?
}
