// Models/StatusTypes.swift
// GroveKit
//
// Working tree and index status types.

import Foundation

// MARK: - StatusEntry

/// Working tree / index status for a single file path.
struct StatusEntry: Identifiable, Hashable, Sendable {
    /// File path relative to repository root — used as the stable identifier.
    let id: String
    let path: String
    /// Status in the index (staged area).
    let indexStatus: FileStatus
    /// Status in the working directory (unstaged).
    let workdirStatus: FileStatus
}

// MARK: - FileStatus

/// Single-character status code matching `git status --porcelain` conventions.
enum FileStatus: String, Hashable, Sendable, CaseIterable {
    case unmodified = " "
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case conflicted = "U"
    case typeChange = "T"
}
