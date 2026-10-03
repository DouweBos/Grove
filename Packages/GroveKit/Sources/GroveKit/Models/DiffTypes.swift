// Models/DiffTypes.swift
// GroveKit
//
// Types representing diff output from Git.

import Foundation

// MARK: - DiffResult

/// Complete diff output for a single file, containing one or more hunks.
struct DiffResult: Sendable {
    let filePath: String
    /// Original path before a rename, `nil` otherwise.
    let oldPath: String?
    let isBinary: Bool
    let hunks: [HunkData]
    let stats: DiffStats
}

// MARK: - DiffStats

/// Aggregate line-change counts for a diff.
struct DiffStats: Hashable, Sendable {
    let additions: Int
    let deletions: Int
}

// MARK: - HunkData

/// One contiguous changed region inside a diff.
struct HunkData: Identifiable, Hashable, Sendable {
    /// Derived from the hunk header string; stable within a diff result.
    let id: String
    /// Raw hunk header, e.g. `@@ -10,6 +10,8 @@ func foo() {`.
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

// MARK: - DiffLine

/// A single line inside a ``HunkData``.
struct DiffLine: Identifiable, Hashable, Sendable {
    let id: String
    let type: DiffLineType
    /// Raw line content, without the leading `+`/`-`/` ` prefix.
    let content: String
    /// Line number in the old file; `nil` for addition lines.
    let oldLineNumber: Int?
    /// Line number in the new file; `nil` for deletion lines.
    let newLineNumber: Int?
}

// MARK: - DiffLineType

/// Whether a diff line is context, an addition, or a deletion.
enum DiffLineType: String, Hashable, Sendable {
    case context = " "
    case addition = "+"
    case deletion = "-"
}

// MARK: - FileDiff

/// Pairs a file's status entry with its optional computed diff.
struct FileDiff: Sendable {
    let path: String
    let status: FileStatus
    /// `nil` for binary files or when the diff hasn't been loaded yet.
    let diff: DiffResult?
    let stats: DiffStats
}

// MARK: - FileRevision

/// Where to read one version of a file from.
enum FileRevision: Hashable, Sendable {
    case workingTree
    case index
    /// Merge conflict stage: 1 base, 2 ours, 3 theirs.
    case conflictStage(Int)
    /// Any revision `git show <rev>:<path>` accepts, e.g. a SHA, `sha^` or `stash@{0}`.
    case commit(String)
}
