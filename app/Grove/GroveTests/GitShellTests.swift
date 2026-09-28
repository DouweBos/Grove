// GitShellTests.swift
// GroveTests
//
// Tests for GitShell — verifies that large outputs don't deadlock
// and that basic command execution works correctly.

import Foundation
import Testing
@testable import Grove

// MARK: - GitShellTests

struct GitShellTests {

    /// A temp directory used as a dummy working directory for shell commands.
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroveTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Basic execution

    @Test func gitShell_runsSimpleCommand() async throws {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }

        let shell = GitShell(workingDirectory: dir, gitPath: "/usr/bin/git")
        let result = try await shell.run(["version"])
        #expect(result.stdout.contains("git version"))
        #expect(result.exitCode == 0)
    }

    // MARK: Large output — pipe deadlock prevention

    @Test func gitShell_handlesLargeStdoutWithoutDeadlock() async throws {
        // Generate output that exceeds the pipe buffer (~64 KB on macOS).
        // We batch-create tags using `git update-ref` via stdin for speed.

        let dir = makeTempDir()
        defer { removeTempDir(dir) }

        let shell = GitShell(workingDirectory: dir, gitPath: "/usr/bin/git")

        // Init a repo and create an initial commit.
        try await shell.run(["init"])
        try await shell.run(["-c", "user.email=test@test.com", "-c", "user.name=Test",
                             "commit", "--allow-empty", "-m", "init"])

        // Get the commit SHA to point tags at.
        let headResult = try await shell.run(["rev-parse", "HEAD"])
        let sha = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Batch-create 1500 tags via update-ref --stdin (much faster than individual calls).
        // Each tag line in the output is ~65 bytes, so 1500 × 65 = ~97 KB (exceeds 64 KB pipe buffer).
        var updateRefInput = ""
        for i in 0..<1500 {
            updateRefInput += "create refs/tags/test-tag-with-a-longer-name-for-size-\(String(format: "%04d", i)) \(sha)\n"
        }
        try await shell.runWithInput(["update-ref", "--stdin"], input: updateRefInput)

        // This is the same format string Grove uses for tags.
        let result = try await shell.run([
            "for-each-ref",
            "--sort=-creatordate",
            "--format=%(refname:short)%00%(objectname:short)%00%(objecttype)%00%(*objectname:short)%00%(contents:subject)%00%(taggername)%00%(taggerdate:iso-strict)",
            "refs/tags/"
        ])

        #expect(result.exitCode == 0)

        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1500, "Expected 1500 tag lines, got \(lines.count)")
        #expect(result.stdout.utf8.count > 64_000, "Output should exceed pipe buffer size")
    }

    @Test func gitShell_handlesLargeOutputWithManyBranches() async throws {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }

        let shell = GitShell(workingDirectory: dir, gitPath: "/usr/bin/git")

        try await shell.run(["init"])
        try await shell.run(["-c", "user.email=test@test.com", "-c", "user.name=Test",
                             "commit", "--allow-empty", "-m", "init"])

        let headResult = try await shell.run(["rev-parse", "HEAD"])
        let sha = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Batch-create 200 branches via update-ref --stdin.
        var updateRefInput = ""
        for i in 0..<200 {
            updateRefInput += "create refs/heads/feature/test-branch-\(String(format: "%04d", i)) \(sha)\n"
        }
        try await shell.runWithInput(["update-ref", "--stdin"], input: updateRefInput)

        let result = try await shell.run([
            "for-each-ref",
            "--format=%(refname)%00%(refname:short)%00%(objectname)%00%(upstream)%00%(upstream:track)%00%(HEAD)",
            "refs/heads/"
        ])

        #expect(result.exitCode == 0)
        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        // 200 created + 1 default (main/master)
        #expect(lines.count >= 200)
    }

    // MARK: Non-zero exit

    @Test func gitShell_throwsOnNonZeroExit() async throws {
        let dir = makeTempDir()
        defer { removeTempDir(dir) }

        let shell = GitShell(workingDirectory: dir, gitPath: "/usr/bin/git")

        // Running git log in a non-repo directory should fail.
        do {
            _ = try await shell.run(["log"])
            #expect(Bool(false), "Expected an error to be thrown")
        } catch {
            #expect(error is GitShellError)
        }
    }
}
