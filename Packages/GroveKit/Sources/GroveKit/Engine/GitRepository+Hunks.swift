// Engine/GitRepository+Hunks.swift
// GroveKit
//
// Staging, unstaging and discarding hunks and lines, each checked against the diff as it is when it runs.

import Foundation
import os

nonisolated enum HunkOperation: String, Sendable {
    case stage, unstage, discard

    var readsStaged: Bool { self == .unstage }
    var writesIndex: Bool { self != .discard }
    var undoes: Bool { self != .stage }
}

/// Why a hunk action was refused; nothing has changed when one is thrown.
nonisolated enum HunkActionError: LocalizedError {
    case outdated, hidesWhitespace, typeChange, noLinesSelected, notUTF8

    var errorDescription: String? {
        switch self {
        case .outdated:
            "The file changed since this diff was shown, so nothing was applied. Review the updated diff and try again."
        case .hidesWhitespace:
            "This hunk hides whitespace changes. Show whitespace changes, then stage it again."
        case .typeChange:
            "This change replaces the file with another type of file. Stage, unstage or discard the whole file instead."
        case .noLinesSelected:
            "Select at least one added or removed line."
        case .notUTF8:
            "This file isn't UTF-8 text. Stage, unstage or discard the whole file instead."
        }
    }
}

extension GitRepository {

    /// File names are never globs here: `[id].tsx` mustn't also pick `i.tsx`.
    nonisolated private static let literalPaths = ["GIT_LITERAL_PATHSPECS": "1"]

    // MARK: - Actions

    public func stageHunk(_ hunk: HunkData, in file: String) async throws {
        try await change(.stage, hunk, lines: nil, in: file)
    }

    public func unstageHunk(_ hunk: HunkData, in file: String) async throws {
        try await change(.unstage, hunk, lines: nil, in: file)
    }

    public func discardHunk(_ hunk: HunkData, in file: String) async throws {
        try await change(.discard, hunk, lines: nil, in: file)
    }

    public func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        try await change(.stage, hunk, lines: lines, in: file)
    }

    public func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        try await change(.unstage, hunk, lines: lines, in: file)
    }

    public func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        try await change(.discard, hunk, lines: lines, in: file)
    }

    /// One at a time: two actions checked against the same diff could both apply in repeated content.
    private func change(_ operation: HunkOperation, _ hunk: HunkData, lines: [DiffLine]?, in file: String) async throws {
        let previous = lastHunkChange
        let task = Task {
            await previous?.value
            try await applyChange(operation, hunk, lines: lines, in: file)
        }
        lastHunkChange = Task { _ = await task.result }
        try await task.value
    }

    /// The patch comes from a fresh read; the caller's hunk and lines only say which part of it.
    private func applyChange(_ operation: HunkOperation, _ shown: HunkData, lines: [DiffLine]?, in file: String) async throws {
        let staged = operation.readsStaged
        let untracked = staged ? nil : try await untrackedPath(file)

        func find(ignoringWhitespace: Bool) async throws -> (diff: DiffResult, hunk: HunkData)? {
            let output = try await workingDiff(file, staged: staged, untracked: untracked != nil,
                                               ignoreWhitespace: ignoringWhitespace, options: ["--no-textconv"])
            guard output.stdoutData == Data(output.stdout.utf8) else { throw HunkActionError.notUTF8 }
            let sections = DiffParser.parse(output.stdout)
            guard sections.filter({ $0.filePath == file }).count <= 1 else { throw HunkActionError.typeChange }
            guard let diff = Self.section(for: file, in: sections),
                  let hunk = diff.hunks.first(where: { $0.id == shown.id }) else { return nil }
            return (diff, hunk)
        }

        var match = try await find(ignoringWhitespace: false)
        if match == nil {
            match = try await find(ignoringWhitespace: true)
            // With -w the context is the new side's, which is only what undoing starts from.
            if match != nil, !operation.undoes { throw HunkActionError.hidesWhitespace }
        }
        guard let (diff, hunk) = match else { throw HunkActionError.outdated }

        let selected = try Self.resolve(lines ?? hunk.lines, in: hunk)
        let patch = DiffParser.buildPatch(from: selected, in: hunk, filePath: untracked ?? diff.filePath,
                                          oldPath: diff.oldPath, change: diff.change, undoing: operation.undoes)
        Logger.gitRepository.info("Applying a hunk \(operation.rawValue, privacy: .public) in \(self.displayName, privacy: .public)")
        try await applyPatch(patch, cached: operation.writesIndex)
    }

    /// The changed lines of `hunk` that `lines` name, each still as it was shown.
    private static func resolve(_ lines: [DiffLine], in hunk: HunkData) throws -> [DiffLine] {
        let current = Dictionary(hunk.lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolved = try lines.map { line in
            guard let match = current[line.id], match.type == line.type,
                  match.content.utf8.elementsEqual(line.content.utf8) else { throw HunkActionError.outdated }
            return match
        }
        let changed = resolved.filter { $0.type != .context }
        guard !changed.isEmpty else { throw HunkActionError.noLinesSelected }
        return changed
    }

    // MARK: - Reading

    /// The diff hunks come from, for showing and for acting alike, so their ids agree.
    func workingDiff(_ file: String, staged: Bool, untracked: Bool, ignoreWhitespace: Bool,
                     options: [String] = []) async throws -> ShellResult {
        let side = staged ? ["diff", "--cached"] : ["diff"]
        // The user's prefix, color and external diff settings would leave output the parser can't read.
        var args = side + ["-U3", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/"] + options
        if ignoreWhitespace { args.append("-w") }
        if untracked {
            // Untracked files are invisible to `git diff`; compare against an empty file. Exit 1 means "differs".
            let result = try await shell.runAllowingFailure(args + ["--no-index", "--", "/dev/null", file])
            guard result.exitCode <= 1 else {
                throw GitShellError.nonZeroExit(command: "git diff --no-index", exitCode: result.exitCode, stderr: result.stderr)
            }
            return result
        }
        let result = try await shell.run(args + ["--", file], environment: Self.literalPaths)
        guard case .added? = Self.section(for: file, in: DiffParser.parse(result.stdout))?.change,
              let source = try await renameSource(of: file, in: side) else { return result }
        // git only sees a rename when both of its paths are in the diff.
        return try await shell.run(args + ["--", source, file], environment: Self.literalPaths)
    }

    /// The file's section; a lone one also counts, for a path given relative to a subfolder.
    nonisolated static func section(for file: String, in sections: [DiffResult]) -> DiffResult? {
        sections.first { $0.filePath == file } ?? (sections.count == 1 ? sections.first : nil)
    }

    private func renameSource(of file: String, in side: [String]) async throws -> String? {
        let output = try await shell.run(side + ["--name-status", "-z", "--diff-filter=R"]).stdout
        let fields = output.split(separator: "\0").map(String.init)
        for index in stride(from: 0, to: fields.count - 2, by: 3) where fields[index + 2] == file {
            return fields[index + 1]
        }
        return nil
    }

    /// The root-relative path when `file` is untracked, spelled as git would add it.
    private func untrackedPath(_ file: String) async throws -> String? {
        let output = try await shell.run(["ls-files", "--others", "--exclude-standard", "--full-name", "-z", "--", file],
                                         environment: Self.literalPaths).stdout
        return output.split(separator: "\0").map(String.init).first { $0 == file || $0.hasSuffix("/" + file) }
    }
}
