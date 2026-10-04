// Domain/WorktreeResolver.swift
// GroveKit
//
// Links git worktrees to their main repository by reading git's own files,
// so the browser can nest them instead of treating each as a separate repo.

import Foundation

/// A linked worktree of a repository, as recorded in `<repo>/.git/worktrees/<name>`.
public nonisolated struct LinkedWorktree: Hashable, Sendable {
    public let path: String
    public let mainRepositoryPath: String
    /// Checked-out branch, or nil when detached.
    let branch: String?
    /// The folder was deleted without `git worktree remove`; `git worktree prune` cleans it up.
    public let isMissing: Bool

    public init(path: String, mainRepositoryPath: String, branch: String? = nil, isMissing: Bool) {
        self.path = path
        self.mainRepositoryPath = mainRepositoryPath
        self.branch = branch
        self.isMissing = isMissing
    }

    public var name: String { branch ?? URL(fileURLWithPath: path).lastPathComponent }
}

public nonisolated enum WorktreeResolver {

    /// Whether two paths name the same folder; git reports `/private/tmp` where the user opened `/tmp`.
    public static func isSameFolder(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The main repository's working directory when `path` is a linked worktree, else nil, read through `runner`.
    public static func mainRepositoryPath(forWorktreeAt path: String, runner: any GitRunner) async -> String? {
        let worktree = URL(fileURLWithPath: path)
        guard let gitDir = await runner.readString(at: worktree.appendingPathComponent(".git")).flatMap({ value(after: "gitdir:", in: $0) })
        else { return nil }
        let adminDir = resolve(gitDir, relativeTo: worktree)
        let commondir = await runner.readString(at: adminDir.appendingPathComponent("commondir"))
        return commonDirectory(ofAdminDirectory: adminDir, commondir: commondir).map(workingDirectory(ofCommonDirectory:))
    }

    /// Worktrees linked to the repository at `repositoryPath`, sorted by name, read through `runner`.
    public static func linkedWorktrees(ofRepositoryAt repositoryPath: String, runner: any GitRunner) async -> [LinkedWorktree] {
        let worktreesDir = URL(fileURLWithPath: repositoryPath).appendingPathComponent(".git/worktrees")
        guard let names = try? await runner.contentsOfDirectory(at: worktreesDir) else { return [] }
        var linked: [LinkedWorktree] = []
        for name in names {
            let adminDir = worktreesDir.appendingPathComponent(name)
            guard let pointer = await runner.readString(at: adminDir.appendingPathComponent("gitdir")) else { continue }
            let path = worktreePath(pointer: pointer, adminDir: adminDir)
            let head = await runner.readString(at: adminDir.appendingPathComponent("HEAD"))
            linked.append(LinkedWorktree(path: path, mainRepositoryPath: repositoryPath,
                                         branch: head.flatMap { value(after: "ref: refs/heads/", in: $0) },
                                         isMissing: !(await runner.fileExists(at: URL(fileURLWithPath: path)))))
        }
        return sorted(linked)
    }

    #if os(macOS)
    /// The main repository's working directory when `path`, on this Mac, is a linked worktree, else nil.
    public static func mainRepositoryPath(forWorktreeAt path: String) -> String? {
        let worktree = URL(fileURLWithPath: path)
        guard let gitDir = LocalFiles.string(at: worktree.appendingPathComponent(".git")).flatMap({ value(after: "gitdir:", in: $0) })
        else { return nil }
        let adminDir = resolve(gitDir, relativeTo: worktree)
        let commondir = LocalFiles.string(at: adminDir.appendingPathComponent("commondir"))
        return commonDirectory(ofAdminDirectory: adminDir, commondir: commondir).map(workingDirectory(ofCommonDirectory:))
    }

    /// Worktrees linked to the repository at `repositoryPath` on this Mac, sorted by name.
    public static func linkedWorktrees(ofRepositoryAt repositoryPath: String) -> [LinkedWorktree] {
        let worktreesDir = URL(fileURLWithPath: repositoryPath).appendingPathComponent(".git/worktrees")
        guard let names = LocalFiles.names(in: worktreesDir) else { return [] }
        return sorted(names.compactMap { name -> LinkedWorktree? in
            let adminDir = worktreesDir.appendingPathComponent(name)
            guard let pointer = LocalFiles.string(at: adminDir.appendingPathComponent("gitdir")) else { return nil }
            let path = worktreePath(pointer: pointer, adminDir: adminDir)
            let head = LocalFiles.string(at: adminDir.appendingPathComponent("HEAD"))
            return LinkedWorktree(path: path, mainRepositoryPath: repositoryPath,
                                  branch: head.flatMap { value(after: "ref: refs/heads/", in: $0) },
                                  isMissing: !LocalFiles.exists(at: URL(fileURLWithPath: path)))
        })
    }
    #endif

    // MARK: - Private

    /// `gitdir` holds the path of the worktree's own `.git` file.
    private static func worktreePath(pointer: String, adminDir: URL) -> String {
        let dotGit = resolve(pointer.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: adminDir)
        return dotGit.deletingLastPathComponent().standardizedFileURL.path
    }

    private static func sorted(_ worktrees: [LinkedWorktree]) -> [LinkedWorktree] {
        worktrees.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func commonDirectory(ofAdminDirectory adminDir: URL, commondir: String?) -> URL? {
        guard let raw = commondir else {
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
