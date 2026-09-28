// GitKit/Parsers/WorktreeParser.swift
// Grove

import Foundation

nonisolated enum WorktreeParser {

    /// Parses `git worktree list --porcelain`: blank-line separated blocks of `worktree`, `HEAD`,
    /// then `branch refs/heads/…` or `detached`, plus optional `locked` / `prunable` lines.
    static func parse(_ output: String) -> [WorktreeInfo] {
        output.components(separatedBy: "\n\n").enumerated().compactMap { index, block in
            var path: String?
            var head: String?
            var branch: String?
            var isPrunable = false
            var isLocked = false
            for line in block.split(whereSeparator: \.isNewline).map(String.init) {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else if line == "prunable" || line.hasPrefix("prunable ") {
                    isPrunable = true
                } else if line == "locked" || line.hasPrefix("locked ") {
                    isLocked = true
                }
            }
            guard let path else { return nil }
            return WorktreeInfo(path: path, branch: branch, headSHA: head ?? "", isMain: index == 0,
                                isPrunable: isPrunable, isLocked: isLocked)
        }
    }
}
