// StalledRemoteTests.swift
// GroveKitTests
//
// A remote that accepts the connection and never answers must fail the command instead of hanging it.

import Darwin
import Foundation
import Testing
@testable import GroveKit

/// A listening socket nobody accepts on: the kernel completes the handshake and the request goes unanswered.
private final class SilentServer {
    let fd: Int32
    let port: UInt16

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                bind(fd, pointer, length) == 0 && listen(fd, 4) == 0 && getsockname(fd, pointer, &length) == 0
            }
        }
        guard bound else { close(fd); throw POSIXError(.EADDRNOTAVAIL) }
        self.fd = fd
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(fd) }
}

struct StalledRemoteTests {

    @Test nonisolated func stalledHTTPRemoteTimesOut() async throws {
        let server = try SilentServer()
        let runner = LocalGitRunner()
        // Shortens the default 30 s window; the 1 B/s limit still comes from the runner.
        let invocation = GitInvocation(arguments: ["ls-remote", "http://127.0.0.1:\(server.port)/repo.git"],
                                       workingDirectory: runner.temporaryDirectory,
                                       environment: ["GIT_HTTP_LOW_SPEED_TIME": "1"])
        let start = Date()
        let result = try await runner.run(invocation)
        #expect(!result.isSuccess)
        #expect(Date().timeIntervalSince(start) < 20)
        #expect(GitErrorMessage.message(command: "ls-remote", stderr: result.stderr)
                == "The remote stopped responding. Check your internet connection and try again.")
    }

    @Test nonisolated func cancellingAPullStopsGit() async throws {
        let server = try SilentServer()
        let runner = LocalGitRunner()
        let directory = runner.temporaryDirectory.appendingPathComponent("grove-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let shell = GitShell(workingDirectory: runner.temporaryDirectory, runner: runner)
        try await shell.run(["init", "-q", "-b", "main", directory.path])
        try await shell.at(directory).run(["remote", "add", "origin", "http://127.0.0.1:\(server.port)/repo.git"])

        let repo = try await GitRepository(path: directory, runner: runner)
        let pull = Task { try await repo.pull(remote: "origin", branch: "main", strategy: .merge, options: PullOptions(), progress: nil) }
        try await Task.sleep(for: .milliseconds(500))
        let start = Date()
        pull.cancel()
        await #expect(throws: CancellationError.self) { try await pull.value }
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
