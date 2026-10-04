// Models/DiffTypes.swift
// GroveKit
//
// Types representing diff output from Git.

import Foundation

// MARK: - DiffResult

/// Complete diff output for a single file, containing one or more hunks.
public struct DiffResult: Sendable {
    public let filePath: String
    /// Original path before a rename, `nil` otherwise.
    public let oldPath: String?
    public let isBinary: Bool
    public let hunks: [HunkData]
    public let stats: DiffStats

    public nonisolated init(filePath: String, oldPath: String? = nil, isBinary: Bool = false, hunks: [HunkData], stats: DiffStats) {
        self.filePath = filePath
        self.oldPath = oldPath
        self.isBinary = isBinary
        self.hunks = hunks
        self.stats = stats
    }
}

// MARK: - DiffStats

/// Aggregate line-change counts for a diff.
public struct DiffStats: Hashable, Sendable {
    public let additions: Int
    public let deletions: Int

    public init(additions: Int, deletions: Int) {
        self.additions = additions
        self.deletions = deletions
    }
}

// MARK: - HunkData

/// One contiguous changed region inside a diff.
public struct HunkData: Identifiable, Hashable, Sendable {
    /// Derived from the hunk header string; stable within a diff result.
    public let id: String
    /// Raw hunk header, e.g. `@@ -10,6 +10,8 @@ func foo() {`.
    public let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    public let lines: [DiffLine]

    public init(id: String, header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

// MARK: - DiffLine

/// A single line inside a ``HunkData``.
public struct DiffLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let type: DiffLineType
    /// Raw line content, without the leading `+`/`-`/` ` prefix.
    public let content: String
    /// Line number in the old file; `nil` for addition lines.
    public let oldLineNumber: Int?
    /// Line number in the new file; `nil` for deletion lines.
    public let newLineNumber: Int?

    public init(id: String, type: DiffLineType, content: String, oldLineNumber: Int? = nil, newLineNumber: Int? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

// MARK: - DiffLineType

/// Whether a diff line is context, an addition, or a deletion.
public enum DiffLineType: String, Hashable, Sendable {
    case context = " "
    case addition = "+"
    case deletion = "-"
}

// MARK: - FileDiff

/// Pairs a file's status entry with its optional computed diff.
public struct FileDiff: Sendable {
    public let path: String
    public let status: FileStatus
    /// `nil` for binary files or when the diff hasn't been loaded yet.
    public let diff: DiffResult?
    public let stats: DiffStats

    public nonisolated init(path: String, status: FileStatus, diff: DiffResult?, stats: DiffStats) {
        self.path = path
        self.status = status
        self.diff = diff
        self.stats = stats
    }
}

// MARK: - FileRevision

/// Where to read one version of a file from.
public enum FileRevision: Hashable, Sendable {
    case workingTree
    case index
    /// Merge conflict stage: 1 base, 2 ours, 3 theirs.
    case conflictStage(Int)
    /// Any revision `git show <rev>:<path>` accepts, e.g. a SHA, `sha^` or `stash@{0}`.
    case commit(String)
}
