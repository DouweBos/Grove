// Runner/LocalGitRunner.swift
// GroveKit
//
// Runs git as a child process on this Mac and reads the worktree through FileManager.

import Foundation

#if os(macOS)
nonisolated struct LocalGitRunner: GitRunner {

    /// Variables added to every launch, read per launch so a changed preference or account applies to the next command.
    /// Gets the working directory and the environment so far.
    typealias EnvironmentProvider = @Sendable (_ workingDirectory: URL, _ base: [String: String]) -> [String: String]

    /// Path to the git executable.
    let gitPath: String
    private let baseEnvironment: [String: String]
    private let environmentProvider: EnvironmentProvider?

    /// - Parameters:
    ///   - gitPath: Overrides the git executable; defaults to the first of the well-known locations.
    ///   - environment: Per-launch variables layered over the inherited environment, e.g. credentials.
    init(gitPath: String? = nil, environment: EnvironmentProvider? = nil) {
        self.gitPath = gitPath ?? Self.resolveGitPath()
        self.environmentProvider = environment
        var env = ProcessInfo.processInfo.environment
        // Ensure consistent output encoding and locale-independent parsing.
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        // Disable pager output so we always get plain text.
        env["GIT_PAGER"] = "cat"
        env["PAGER"] = "cat"
        // Disable interactive prompts (prevents hanging in CI or when no TTY).
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["PATH"] = Self.augmentedPath(env["PATH"])
        self.baseEnvironment = env
    }

    func withGitExecutable(_ path: String) -> (any GitRunner)? {
        LocalGitRunner(gitPath: path, environment: environmentProvider)
    }

    // MARK: Git

    func run(_ invocation: GitInvocation) async throws -> ShellResult {
        let output = try await ProcessRunner.run(buildProcess(invocation), input: invocation.input)
        return ShellResult(stdout: String(data: output.stdout, encoding: .utf8) ?? "",
                           stderr: String(data: output.stderr, encoding: .utf8) ?? "",
                           exitCode: output.status, stdoutData: output.stdout)
    }

    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        let output = try await ProcessRunner.runStreaming(buildProcess(invocation)) { chunk in
            onStderr(String(bytes: chunk, encoding: .utf8) ?? "")
        }
        return ShellResult(stdout: String(data: output.stdout, encoding: .utf8) ?? "",
                           stderr: String(bytes: output.stderr, encoding: .utf8) ?? "",
                           exitCode: output.status, stdoutData: output.stdout)
    }

    private func buildProcess(_ invocation: GitInvocation) -> Process {
        var base = baseEnvironment
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

    var temporaryDirectory: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }

    func itemKind(at url: URL) async -> FileItemKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }

    func readFile(at url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }

    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: url.path)
        }
    }

    func createDirectory(at url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }

    func moveItem(at source: URL, to destination: URL) async throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func contentsOfDirectory(at url: URL) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    // MARK: Git Path Resolution

    /// Apps launched from the Dock get a minimal PATH; Homebrew's git-lfs, gpg and hook tools live here.
    static let toolDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func augmentedPath(_ path: String?) -> String {
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
#endif
