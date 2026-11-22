// HunkPatchScratch.swift
// GroveKitTests
//
// A scratch repository for hunk actions, read back as exact bytes and modes on both index and worktree.

import Foundation
import Testing
@testable import GroveKit

nonisolated enum PatchOperation: String, CaseIterable, Sendable {
    case stage, unstage, discard

    var actsOnStaged: Bool { self == .unstage }
}

nonisolated struct PatchBlob: Equatable, CustomStringConvertible {
    let mode: String
    let bytes: Data

    init(mode: String = "100644", _ text: String) {
        self.init(mode: mode, bytes: Data(text.utf8))
    }

    init(mode: String, bytes: Data) {
        self.mode = mode
        self.bytes = bytes
    }

    var description: String { "\(mode) \(String(reflecting: String(decoding: bytes, as: UTF8.self)))" }
}

nonisolated struct PatchSnapshot: Equatable {
    var index: [String: PatchBlob] = [:]
    var worktree: [String: PatchBlob] = [:]
}

/// Offers git alone, as a remote runner would: no file access, no raw bytes beside the text.
private nonisolated struct GitOnlyRunner: GitRunner {
    let git: LocalGitRunner

    func run(_ invocation: GitInvocation) async throws -> ShellResult {
        let result = try await git.run(invocation)
        return ShellResult(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
    }

    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        try await run(invocation)
    }

    var temporaryDirectory: URL { git.temporaryDirectory }
    func itemKind(at url: URL) async -> FileItemKind? { nil }
    func readFile(at url: URL) async throws -> Data { throw CocoaError(.featureUnsupported) }
    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws { throw CocoaError(.featureUnsupported) }
    func removeItem(at url: URL) async throws { throw CocoaError(.featureUnsupported) }
    func createDirectory(at url: URL) async throws { throw CocoaError(.featureUnsupported) }
    func moveItem(at source: URL, to destination: URL) async throws { throw CocoaError(.featureUnsupported) }
    func contentsOfDirectory(at url: URL) async throws -> [String] { throw CocoaError(.featureUnsupported) }
}

/// ProcessRunner blocks a GCD thread per git, so too many cases at once starve the pool and hang.
@MainActor
private enum ScratchSlots {
    private static var free = 6
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func acquire() async {
        guard free == 0 else {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    static func release() {
        guard !waiting.isEmpty else {
            free += 1
            return
        }
        waiting.removeFirst().resume()
    }
}

@MainActor
final class HunkPatchScratch {

    let root: URL
    let repository: GitRepository
    private let shell: GitShell

    private nonisolated static let isolation = [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "XDG_CONFIG_HOME": "/dev/null",
        "GIT_AUTHOR_NAME": "Tester", "GIT_AUTHOR_EMAIL": "tester@example.com",
        "GIT_COMMITTER_NAME": "Tester", "GIT_COMMITTER_EMAIL": "tester@example.com",
    ]

    init() async throws {
        await ScratchSlots.acquire()
        var isReady = false
        defer { if !isReady { ScratchSlots.release() } }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-hunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        shell = GitShell(workingDirectory: root,
                         runner: LocalGitRunner(gitPath: FixtureGit.gitPath, environment: { _, _ in Self.isolation }))
        try await shell.run(["init", "-q", "-b", "main"])
        try await shell.run(["config", "core.precomposeunicode", "true"])
        let runner = GitOnlyRunner(git: LocalGitRunner(environment: { _, _ in Self.isolation }))
        repository = try await GitRepository(path: root, runner: runner)
        isReady = true
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        ScratchSlots.release()
    }

    // MARK: Setup

    @discardableResult
    func git(_ arguments: String...) async throws -> ShellResult {
        try await shell.run(arguments)
    }

    func write(_ path: String, _ blob: PatchBlob) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try blob.bytes.write(to: url)
        let permissions = blob.mode == "100755" ? 0o755 : 0o644
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    func write(_ path: String, _ text: String) throws {
        try write(path, PatchBlob(text))
    }

    func delete(_ path: String) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
    }

    func commitAll() async throws {
        try await git("add", "-A")
        try await git("commit", "-q", "--allow-empty", "-m", "base")
    }

    // MARK: Reading

    func snapshot() async throws -> PatchSnapshot {
        var snapshot = PatchSnapshot()
        for record in try await git("ls-files", "-s", "-z").stdout.split(separator: "\0") {
            let parts = record.split(separator: "\t", maxSplits: 1)
            let fields = parts[0].split(separator: " ")
            let blob = try await git("cat-file", "blob", String(fields[1])).stdoutData
            snapshot.index[String(parts[1]).precomposedStringWithCanonicalMapping] = PatchBlob(mode: String(fields[0]), bytes: blob)
        }
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) where !path.hasPrefix(".git/") && path != ".git" {
            let url = root.appendingPathComponent(path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            let permissions = (attributes[.posixPermissions] as? Int) ?? 0
            snapshot.worktree[path.precomposedStringWithCanonicalMapping] =
                PatchBlob(mode: permissions & 0o100 == 0 ? "100644" : "100755", bytes: try Data(contentsOf: url))
        }
        return snapshot
    }

    func diff(_ path: String, staged: Bool, ignoreWhitespace: Bool = false) async throws -> DiffResult {
        let entry = try #require(try await repository.status().first { $0.path == path }, "no status entry for \(path)")
        return try await repository.diff(for: entry, staged: staged, ignoreWhitespace: ignoreWhitespace)
    }

    // MARK: Acting

    /// Acts on the whole hunk, or on its lines written as `+text` and `-text`.
    func perform(_ operation: PatchOperation, _ hunk: HunkData, in path: String, lines selection: [String]? = nil) async throws {
        guard let selection else {
            switch operation {
            case .stage: try await repository.stageHunk(hunk, in: path)
            case .unstage: try await repository.unstageHunk(hunk, in: path)
            case .discard: try await repository.discardHunk(hunk, in: path)
            }
            return
        }
        let lines = try selection.map { wanted in
            try #require(hunk.lines.first { $0.type.rawValue + $0.content == wanted }, "no line \(wanted)")
        }
        switch operation {
        case .stage: try await repository.stageLines(lines, in: hunk, file: path)
        case .unstage: try await repository.unstageLines(lines, in: hunk, file: path)
        case .discard: try await repository.discardLines(lines, in: hunk, file: path)
        }
    }
}
