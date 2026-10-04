// Domain/RepositoryWatcher.swift
// GroveKit
//
// Watches one repository for changes made outside the app, through its runner.

import Foundation

/// Calls `onChange` when the working tree, the worktree's own git state or the refs it shares change.
/// A linked worktree ignores what its sibling worktrees and the main worktree do in the shared git directory.
@MainActor
public final class RepositoryWatcher {

    /// Where one worktree's files and git state live, as git reports them.
    struct Layout: Equatable {
        let worktree: String
        /// This worktree's git directory: `<common>/worktrees/<name>` for a linked worktree.
        let gitDir: String
        /// Refs, objects and config every worktree shares.
        let commonDir: String

        var isLinked: Bool { gitDir != commonDir }

        /// The worktree, plus the git directory when it lives elsewhere (a linked worktree's or a submodule's).
        var watchedPaths: [String] {
            let gitRoot = isLinked ? commonDir : gitDir
            return Self.contains(worktree, gitRoot) ? [worktree] : [worktree, gitRoot]
        }

        func isRelevant(_ path: String) -> Bool {
            if Self.contains(gitDir, path) {
                return !Self.contains(gitDir + "/worktrees", path) && !Self.contains(gitDir + "/logs", path)
            }
            if isLinked, Self.contains(commonDir, path) {
                // Shared refs and config; the main worktree's HEAD and index, and the siblings' folders, aren't ours.
                return Self.contains(commonDir + "/refs", path) || path == commonDir + "/packed-refs"
                    || path == commonDir + "/config"
            }
            return Self.contains(worktree, path)
        }

        private static func contains(_ folder: String, _ path: String) -> Bool {
            path == folder || path.hasPrefix(folder + "/")
        }
    }

    private let path: URL
    private let runner: any GitRunner
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private var watch: (any FileWatch)?
    /// Bumped by `stop()`, so a `start()` still resolving the layout doesn't begin watching afterwards.
    private var generation = 0

    public init(path: URL, runner: any GitRunner, latency: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.runner = runner
        self.latency = latency
        self.onChange = onChange
    }

    /// Starts watching; false when the runner can't watch, so the app refreshes another way.
    @discardableResult
    public func start() async -> Bool {
        guard watch == nil else { return true }
        let started = generation
        let layout = await Self.layout(of: path, runner: runner)
        guard started == generation, watch == nil else { return watch != nil }
        watch = runner.watch(layout.watchedPaths.map { URL(fileURLWithPath: $0) }, latency: latency,
                             isRelevant: { layout.isRelevant($0) }, onChange: onChange)
        return watch != nil
    }

    public func stop() {
        generation += 1
        watch?.stop()
        watch = nil
    }

    /// Asks git, so paths come out the same way every time; a folder git can't read is watched on its own.
    static func layout(of path: URL, runner: any GitRunner) async -> Layout {
        let shell = GitShell(workingDirectory: path, runner: runner)
        let output = try? await shell.run(["rev-parse", "--path-format=absolute", "--show-toplevel", "--git-dir", "--git-common-dir"])
        let lines = output?.stdout.split(separator: "\n").map(String.init) ?? []
        guard lines.count == 3 else {
            let gitDir = path.appendingPathComponent(".git").path
            return Layout(worktree: path.path, gitDir: gitDir, commonDir: gitDir)
        }
        return Layout(worktree: lines[0], gitDir: lines[1], commonDir: lines[2])
    }
}
