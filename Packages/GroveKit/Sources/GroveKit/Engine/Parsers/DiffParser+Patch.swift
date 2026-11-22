// Engine/Parsers/DiffParser+Patch.swift
// GroveKit
//
// Patches for part of a file's diff: doing its lines to stage, undoing them to unstage or discard.

import Foundation

extension DiffParser {

    private nonisolated struct PatchLine {
        let type: DiffLineType
        let content: String
        let endsWithoutNewline: Bool

        var undone: PatchLine {
            let opposite: DiffLineType = switch type {
            case .addition: .deletion
            case .deletion: .addition
            case .context: .context
            }
            return PatchLine(type: opposite, content: content, endsWithoutNewline: endsWithoutNewline)
        }
    }

    /// A patch that does only `selectedLines` of `hunk`, or with `undoing` takes them back from the new side.
    /// Either applies forward: `apply --reverse` loses a deleted file's mode on older git, e.g. 2.48.
    nonisolated static func buildPatch(
        from selectedLines: [DiffLine],
        in hunk: HunkData,
        filePath: String,
        oldPath: String? = nil,
        change: FileChange = .content,
        undoing: Bool = false
    ) -> String {
        let lines = patchLines(selecting: Set(selectedLines.map(\.id)), in: hunk, undoing: undoing)
        let body = undoing ? lines.map(\.undone) : lines
        let oldCount = body.filter { $0.type != .addition }.count
        let newCount = body.filter { $0.type != .deletion }.count
        // git searches from the start line, so both are where the hunk sits in the patch's target.
        let start = max(undoing ? hunk.newStart : hunk.oldStart, 1)

        // Taking back a rename's lines edits the file at its new path.
        var patch = fileHeader(change: undoing ? change.undone : change, filePath: filePath, oldPath: undoing ? nil : oldPath,
                               oldCount: oldCount, newCount: newCount)
        patch += "@@ -\(oldCount == 0 ? 0 : start),\(oldCount) +\(newCount == 0 ? 0 : start),\(newCount) @@\n"
        for line in body {
            patch += line.type.rawValue
            patch += line.content
            patch += "\n"
            if line.endsWithoutNewline { patch += "\\ No newline at end of file\n" }
        }
        return patch
    }

    /// The target's side stays byte for byte; its unselected changes become context and the other side's are dropped.
    private nonisolated static func patchLines(selecting selected: Set<String>, in hunk: HunkData, undoing: Bool) -> [PatchLine] {
        let targetType: DiffLineType = undoing ? .addition : .deletion
        let kept = hunk.lines.compactMap { line -> PatchLine? in
            let isUnselected = line.type != .context && !selected.contains(line.id)
            if isUnselected && line.type != targetType { return nil }
            return PatchLine(type: isUnselected ? .context : line.type, content: line.content,
                             endsWithoutNewline: line.endsWithoutNewline)
        }
        let lastOnOtherSide = kept.lastIndex { $0.type != targetType }

        // Only a side's last line can lack a newline; one that others now follow on the built side gains it.
        return kept.enumerated().flatMap { index, line -> [PatchLine] in
            guard line.endsWithoutNewline, line.type != targetType, index != lastOnOtherSide else { return [line] }
            guard line.type == .context else {
                return [PatchLine(type: line.type, content: line.content, endsWithoutNewline: false)]
            }
            return [PatchLine(type: .deletion, content: line.content, endsWithoutNewline: !undoing),
                    PatchLine(type: .addition, content: line.content, endsWithoutNewline: undoing)]
        }
    }

    private nonisolated static func fileHeader(
        change: FileChange, filePath: String, oldPath: String?, oldCount: Int, newCount: Int
    ) -> String {
        let source = oldPath ?? filePath
        let oldName = GitPathQuoting.quote("a/" + source)
        let newName = GitPathQuoting.quote("b/" + filePath)
        var header = "diff --git \(oldName) \(newName)\n"
        var from = oldName
        var to = newName
        switch change {
        // Part of an addition or deletion can leave content on both sides, which is then an edit.
        case .added(let mode) where oldCount == 0:
            header += "new file mode \(mode)\n"
            from = "/dev/null"
        case .deleted(let mode) where newCount == 0:
            header += "deleted file mode \(mode)\n"
            to = "/dev/null"
        case .renamed where source != filePath:
            header += "rename from \(GitPathQuoting.quote(source))\nrename to \(GitPathQuoting.quote(filePath))\n"
        default:
            break
        }
        return header + "--- \(from)\n+++ \(to)\n"
    }
}

private extension FileChange {
    nonisolated var undone: FileChange {
        switch self {
        case .added(let mode): .deleted(mode: mode)
        case .deleted(let mode): .added(mode: mode)
        case .content, .renamed: .content
        }
    }
}
