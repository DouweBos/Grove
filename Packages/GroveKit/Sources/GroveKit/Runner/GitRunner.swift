// Runner/GitRunner.swift
// GroveKit
//
// The one seam between GroveKit and the machine holding the worktree: git invocations and worktree file access.
// LocalGitRunner runs git on this Mac; a remote runner can implement the same protocol without touching callers.

import Foundation

/// One git invocation: its arguments, where it runs, and what it adds to the environment.
public nonisolated struct GitInvocation: Sendable {
    public var arguments: [String]
    public var workingDirectory: URL
    /// Set by the shell for all its invocations; layered under the runner's own per-launch variables.
    public var shellEnvironment: [String: String] = [:]
    /// Per-call overrides, applied last.
    public var environment: [String: String] = [:]
    /// Written to git's stdin when present.
    public var input: Data?

    public init(arguments: [String], workingDirectory: URL, shellEnvironment: [String: String] = [:],
         environment: [String: String] = [:], input: Data? = nil) {
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.shellEnvironment = shellEnvironment
        self.environment = environment
        self.input = input
    }
}

/// Runs git and reaches the worktree's files. Every git process and worktree file GroveKit touches goes through one.
public nonisolated protocol GitRunner: Sendable {
    /// Runs git and returns its output whatever the exit code.
    func run(_ invocation: GitInvocation) async throws -> ShellResult
    /// Runs a long command (clone), handing stderr to `onStderr` as it arrives; cancelling the task stops git.
    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult

    /// Scratch space for files git reads: rebase todo lists, editor scripts, temporary indexes.
    var temporaryDirectory: URL { get }
    func itemKind(at url: URL) async -> FileItemKind?
    func readFile(at url: URL) async throws -> Data
    /// Atomic write, creating missing parent directories.
    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws
    func removeItem(at url: URL) async throws
    /// Creates the folder and any missing parents; an existing folder is fine.
    func createDirectory(at url: URL) async throws
    func moveItem(at source: URL, to destination: URL) async throws
    func contentsOfDirectory(at url: URL) async throws -> [String]
    /// Moves the item to the Trash where the machine has one.
    func trashItem(at url: URL) async throws

    /// Watches the folders in `paths` until the returned watch stops, calling `onChange` (debounced, on the main queue)
    /// after changes to paths `isRelevant` accepts, written under the folder as given. Nil when the runner can't watch.
    func watch(_ paths: [URL], latency: TimeInterval, isRelevant: @escaping @Sendable (String) -> Bool,
               onChange: @escaping @Sendable () -> Void) -> (any FileWatch)?

    /// The same runner using another git executable (e.g. one with git-svn), or nil when it can't switch.
    func withGitExecutable(_ path: String) -> (any GitRunner)?
}

/// A running watch from ``GitRunner/watch(_:latency:isRelevant:onChange:)``.
public nonisolated protocol FileWatch: AnyObject, Sendable {
    func stop()
}

public nonisolated enum FileItemKind: Sendable {
    case file, directory
}

// Nonisolated so conformers outside GroveKit get these defaults whatever their default isolation.
nonisolated extension GitRunner {
    public func withGitExecutable(_ path: String) -> (any GitRunner)? { nil }

    public func trashItem(at url: URL) async throws { throw CocoaError(.featureUnsupported) }

    public func watch(_ paths: [URL], latency: TimeInterval, isRelevant: @escaping @Sendable (String) -> Bool,
                      onChange: @escaping @Sendable () -> Void) -> (any FileWatch)? { nil }

    public func fileExists(at url: URL) async -> Bool { await itemKind(at: url) != nil }

    /// The file as UTF-8, or nil when it's missing or unreadable.
    public func readString(at url: URL) async -> String? {
        guard let data = try? await readFile(at: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeString(_ string: String, to url: URL, executable: Bool = false) async throws {
        try await writeFile(Data(string.utf8), to: url, executable: executable)
    }

    /// Makes sure the folder `url` goes in exists, e.g. before git moves a file there.
    public func createParentDirectory(of url: URL) async throws {
        try await createDirectory(at: url.deletingLastPathComponent())
    }
}
