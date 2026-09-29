// Domain/WorktreeResolver.swift
// Grove
//
// Links git worktrees to their main repository by reading git's own files,
// so the browser can nest them instead of treating each as a separate repo.

import Foundation

/// A linked worktree of a repository, as recorded in `<repo>/.git/worktrees/<name>`.
nonisolated struct LinkedWorktree: Hashable, Sendable {
    let path: String
    let mainRepositoryPath: String
    /// Checked-out branch, or nil when detached.
    let branch: String?
    /// The folder was deleted without `git worktree remove`; `git worktree prune` cleans it up.
    let isMissing: Bool

    var name: String { branch ?? URL(fileURLWithPath: path).lastPathComponent }
}

nonisolated enum WorktreeResolver {

    /// Whether two paths name the same folder; git reports `/private/tmp` where the user opened `/tmp`.
    static func isSameFolder(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The main repository's working directory when `path` is a linked worktree, else nil.
    static func mainRepositoryPath(forWorktreeAt path: String) -> String? {
        let dotGit = URL(fileURLWithPath: path).appendingPathComponent(".git")
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              let gitDir = value(after: "gitdir:", in: contents) else { return nil }
        let adminDir = resolve(gitDir, relativeTo: URL(fileURLWithPath: path))
        guard let commonDir = commonDirectory(ofAdminDirectory: adminDir) else { return nil }
        return workingDirectory(ofCommonDirectory: commonDir)
    }

    /// Worktrees linked to the repository at `repositoryPath`, sorted by name.
    static func linkedWorktrees(ofRepositoryAt repositoryPath: String) -> [LinkedWorktree] {
        let worktreesDir = URL(fileURLWithPath: repositoryPath).appendingPathComponent(".git/worktrees")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: worktreesDir.path) else { return [] }
        return names.compactMap { name -> LinkedWorktree? in
            let adminDir = worktreesDir.appendingPathComponent(name)
            // `gitdir` holds the path of the worktree's own `.git` file.
            guard let pointer = try? String(contentsOf: adminDir.appendingPathComponent("gitdir"), encoding: .utf8)
            else { return nil }
            let dotGit = resolve(pointer.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: adminDir)
            let worktreePath = dotGit.deletingLastPathComponent().standardizedFileURL.path
            let head = try? String(contentsOf: adminDir.appendingPathComponent("HEAD"), encoding: .utf8)
            return LinkedWorktree(
                path: worktreePath,
                mainRepositoryPath: repositoryPath,
                branch: head.flatMap { value(after: "ref: refs/heads/", in: $0) },
                isMissing: !FileManager.default.fileExists(atPath: worktreePath)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private static func commonDirectory(ofAdminDirectory adminDir: URL) -> URL? {
        guard let raw = try? String(contentsOf: adminDir.appendingPathComponent("commondir"), encoding: .utf8) else {
            // Older git omits `commondir`; the admin dir then sits at `<common>/worktrees/<name>`.
            // A submodule's `.git/modules/<path>` has no commondir either, but isn't a worktree.
            let parent = adminDir.deletingLastPathComponent()
            return parent.lastPathComponent == "worktrees" ? parent.deletingLastPathComponent() : nil
        }
        return resolve(raw.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: adminDir)
    }

    /// `<repo>/.git` belongs to `<repo>`; a bare repository is its own directory.
    private static func workingDirectory(ofCommonDirectory commonDir: URL) -> String {
        let standardized = commonDir.standardizedFileURL
        return standardized.lastPathComponent == ".git"
            ? standardized.deletingLastPathComponent().path
            : standardized.path
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path).standardizedFileURL
            : base.appendingPathComponent(path).standardizedFileURL
    }

    private static func value(after prefix: String, in text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
