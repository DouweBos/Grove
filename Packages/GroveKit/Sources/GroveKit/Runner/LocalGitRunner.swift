// Runner/LocalGitRunner.swift
// GroveKit
//
// Runs git as a child process on this Mac and reads the worktree through FileManager.

import Foundation

#if os(macOS)
public nonisolated struct LocalGitRunner: GitRunner {

    /// Variables added to every launch, read per launch so a changed preference or account applies to the next command.
    /// Gets the working directory and the environment so far.
    public typealias EnvironmentProvider = @Sendable (_ workingDirectory: URL, _ base: [String: String]) -> [String: String]

    /// Path to the git executable.
    public let gitPath: String
    private let environmentProvider: EnvironmentProvider?

    /// - Parameters:
    ///   - gitPath: Overrides the git executable; defaults to the first of the well-known locations.
    ///   - environment: Per-launch variables layered over the inherited environment, e.g. credentials.
    public init(gitPath: String? = nil, environment: EnvironmentProvider? = nil) {
        self.gitPath = gitPath ?? Self.resolveGitPath()
        self.environmentProvider = environment
    }

    /// The inherited environment, read per launch so variables set after the runner was made still apply.
    private static func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Ensure consistent output encoding and locale-independent parsing.
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        // Disable pager output so we always get plain text.
        env["GIT_PAGER"] = "cat"
        env["PAGER"] = "cat"
        // Disable interactive prompts (prevents hanging in CI or when no TTY).
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["PATH"] = augmentedPath(env["PATH"])
        return env
    }

    public func withGitExecutable(_ path: String) -> (any GitRunner)? {
        LocalGitRunner(gitPath: path, environment: environmentProvider)
    }

    // MARK: Git

    public func run(_ invocation: GitInvocation) async throws -> ShellResult {
        let output = try await ProcessRunner.run(buildProcess(invocation), input: invocation.input)
        return ShellResult(stdout: String(data: output.stdout, encoding: .utf8) ?? "",
                           stderr: String(data: output.stderr, encoding: .utf8) ?? "",
                           exitCode: output.status, stdoutData: output.stdout)
    }

    public func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        let output = try await ProcessRunner.runStreaming(buildProcess(invocation)) { chunk in
            onStderr(String(bytes: chunk, encoding: .utf8) ?? "")
        }
        return ShellResult(stdout: String(data: output.stdout, encoding: .utf8) ?? "",
                           stderr: String(bytes: output.stderr, encoding: .utf8) ?? "",
                           exitCode: output.status, stdoutData: output.stdout)
    }

    private func buildProcess(_ invocation: GitInvocation) -> Process {
        var base = Self.baseEnvironment()
        base.merge(invocation.shellEnvironment) { $1 }
        var env = base
        if let environmentProvider {
            env.merge(environmentProvider(invocation.workingDirectory, base)) { $1 }
        }
        env.merge(invocation.environment) { $1 }

        let process = Process()
        process.executableURL       = URL(fileURLWithPath: gitPath)
        process.arguments           = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment         = env
        return process
    }

    // MARK: Files

    public var temporaryDirectory: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }

    public func itemKind(at url: URL) async -> FileItemKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }

    public func readFile(at url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeFile(_ data: Data, to url: URL, executable: Bool) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: url.path)
        }
    }

    public func createDirectory(at url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func removeItem(at url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    public func moveItem(at source: URL, to destination: URL) async throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func contentsOfDirectory(at url: URL) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    public func trashItem(at url: URL) async throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public func watch(_ paths: [URL], latency: TimeInterval, isRelevant: @escaping @Sendable (String) -> Bool,
                      onChange: @escaping @Sendable () -> Void) -> (any FileWatch)? {
        let watcher = FileWatcher(paths: paths.map(\.path), latency: latency, isRelevant: isRelevant, handler: onChange)
        watcher.start()
        return watcher
    }

    // MARK: Git Path Resolution

    /// Apps launched from the Dock get a minimal PATH; Homebrew's git-lfs, gpg and hook tools live here.
    public static let toolDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    public static func augmentedPath(_ path: String?) -> String {
        var parts = (path ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        for directory in toolDirectories where !parts.contains(directory) { parts.append(directory) }
        return parts.joined(separator: ":")
    }

    private static func resolveGitPath() -> String {
        let candidates = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }
}

/// Synchronous reads of this Mac's disk, for path checks made before any repository or runner exists.
nonisolated enum LocalFiles {
    static func string(at url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    static func names(in url: URL) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: url.path) }
    static func exists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
#endif
