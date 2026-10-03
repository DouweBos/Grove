// LFSTests.swift
// GroveKitTests
//
// Git LFS: pointer parsing, attribute parsing, missing-binary errors, and tracking in a scratch repository.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct LFSTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-lfs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
    }

    // MARK: Parsing

    @Test func parsesPointerLines() {
        let pointer = LFSPointer(lines: ["version https://git-lfs.github.com/spec/v1", "oid sha256:abc123", "size 42"])
        #expect(pointer == LFSPointer(oid: "abc123", size: 42))
        #expect(LFSPointer(lines: ["hello", "world"]) == nil)
    }

    @Test func pointerDiffSidesSplitOldAndNew() {
        let lines = [
            DiffLine(id: "1", type: .context, content: "version https://git-lfs.github.com/spec/v1", oldLineNumber: 1, newLineNumber: 1),
            DiffLine(id: "2", type: .deletion, content: "oid sha256:old", oldLineNumber: 2, newLineNumber: nil),
            DiffLine(id: "3", type: .addition, content: "oid sha256:new", oldLineNumber: nil, newLineNumber: 2),
            DiffLine(id: "4", type: .deletion, content: "size 1", oldLineNumber: 3, newLineNumber: nil),
            DiffLine(id: "5", type: .addition, content: "size 2", oldLineNumber: nil, newLineNumber: 3)
        ]
        let hunk = HunkData(id: "h", header: "@@", oldStart: 1, oldCount: 3, newStart: 1, newCount: 3, lines: lines)
        let diff = DiffResult(filePath: "a.bin", oldPath: nil, isBinary: false, hunks: [hunk], stats: DiffStats(additions: 2, deletions: 2))
        let sides = LFSPointer.sides(of: diff)
        #expect(sides?.old == LFSPointer(oid: "old", size: 1))
        #expect(sides?.new == LFSPointer(oid: "new", size: 2))
    }

    @Test func parsesCheckAttrOutput() {
        let output = "a.psd\0filter\0lfs\0b.txt\0filter\0unspecified\0"
        #expect(GitRepository.parseLFSAttributes(output) == ["a.psd"])
    }

    @Test func missingLFSErrorsAreRecognised() {
        let result = ShellResult(stdout: "", stderr: "git-lfs filter-process: git-lfs: command not found", exitCode: 128)
        guard case .lfsNotInstalled = GitShellError.failure(arguments: ["pull"], result: result) else {
            Issue.record("expected lfsNotInstalled")
            return
        }
    }

    @Test func pathGainsHomebrewDirectories() {
        let path = LocalGitRunner.augmentedPath("/usr/bin:/bin")
        #expect(path.hasPrefix("/usr/bin:/bin"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(LocalGitRunner.augmentedPath("/opt/homebrew/bin:/usr/bin") == "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
    }

    // MARK: Repository

    @Test func trackingAnExtensionMarksMatchingFiles() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        guard await GitRepository.isLFSInstalled(shell: repo.shell) else { return }
        try git(["lfs", "install", "--local"])
        #expect(await repo.lfsStatus().usesLFS == false)

        try Data("binary".utf8).write(to: root.appendingPathComponent("cover.psd"))
        try await repo.trackWithLFS(pattern: "*.psd", literal: false)

        #expect(await repo.lfsStatus() == LFSStatus(usesLFS: true, isInstalled: true))
        #expect(await repo.lfsTrackedPaths(among: ["cover.psd", "notes.txt"]) == ["cover.psd"])
        let attributes = try String(contentsOf: root.appendingPathComponent(".gitattributes"), encoding: .utf8)
        #expect(attributes.contains("*.psd filter=lfs"))

        // Staged through the filter, the index holds a pointer that reads back as the real bytes.
        try await repo.stage(paths: ["cover.psd"])
        let blob = try git(["cat-file", "-p", ":cover.psd"])
        #expect(blob.hasPrefix(LFSPointer.versionPrefix))
        #expect(try await repo.fileData(path: "cover.psd", at: .index) == Data("binary".utf8))
    }

    @Test func trackingAnAlreadyCommittedFileRenormalizesIt() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        guard await GitRepository.isLFSInstalled(shell: repo.shell) else { return }
        try git(["lfs", "install", "--local"])
        try Data("big".utf8).write(to: root.appendingPathComponent("video.mov"))
        try git(["add", "."])
        try git(["commit", "-q", "-m", "add video"])

        try await repo.trackWithLFS(pattern: "video.mov", literal: true)

        #expect(try git(["cat-file", "-p", ":video.mov"]).hasPrefix(LFSPointer.versionPrefix))
    }

    // MARK: Helpers

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = LocalGitRunner.augmentedPath(env["PATH"])
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}
