// PublicRunnerTests.swift
// GroveKitTests
//
// A runner written outside GroveKit, through its public API only.

import Foundation
import GroveKit
import Testing

/// Answers every git call with a canned result, as a runner relaying another host's output would.
private nonisolated struct CannedRunner: GitRunner {
    func run(_ invocation: GitInvocation) async throws -> ShellResult {
        ShellResult(stdout: "abc\n", stderr: "", exitCode: 0)
    }

    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutData: Data([0xFF]))
    }

    var temporaryDirectory: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    func itemKind(at url: URL) async -> FileItemKind? { nil }
    func readFile(at url: URL) async throws -> Data { Data() }
    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws {}
    func removeItem(at url: URL) async throws {}
    func createDirectory(at url: URL) async throws {}
    func moveItem(at source: URL, to destination: URL) async throws {}
    func contentsOfDirectory(at url: URL) async throws -> [String] { [] }
}

struct PublicRunnerTests {

    @Test nonisolated func shellResultBuildsOutsideGroveKit() async throws {
        let runner = CannedRunner()
        let text = try await runner.run(GitInvocation(arguments: ["rev-parse"], workingDirectory: runner.temporaryDirectory))
        #expect(text.isSuccess)
        #expect(text.stdoutData == Data("abc\n".utf8))
        let binary = try await runner.runStreaming(GitInvocation(arguments: [], workingDirectory: runner.temporaryDirectory)) { _ in }
        #expect(binary.stdoutData == Data([0xFF]))
    }

    @Test nonisolated func defaultsAreNonisolated() {
        #expect(CannedRunner().withGitExecutable("/usr/bin/git") == nil)
    }
}
