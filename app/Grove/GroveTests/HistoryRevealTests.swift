// HistoryRevealTests.swift
// GroveTests
//
// Reveal in History pages a commit in when HEAD's history has it and falls back to the ref's own history.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct HistoryRevealTests {

    private let root: URL

    /// 250 commits on main, more than two pages, and a `side` branch forking off the first one.
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-reveal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        var stream = ""
        for index in 1...250 {
            let message = "commit \(index)\n"
            stream += "commit refs/heads/main\nmark :\(index)\n"
            stream += "committer Tester <tester@example.com> \(1_700_000_000 + index * 60) +0000\n"
            stream += "data \(message.utf8.count)\n\(message)"
            if index > 1 { stream += "from :\(index - 1)\n" }
            stream += "\n"
        }
        let side = "side work\n"
        stream += "commit refs/heads/side\ncommitter Tester <tester@example.com> 1800000000 +0000\n"
        stream += "data \(side.utf8.count)\n\(side)from :1\n\n"
        try git(["fast-import", "--quiet"], input: stream)
    }

    @Test func revealPagesInADeepCommit() async throws {
        let session = RepositorySession(repository: try await GitRepository(path: root))
        let deep = try git(["rev-parse", "main~220"]).trimmingCharacters(in: .whitespacesAndNewlines)
        await session.revealInHistory(deep)
        #expect(session.sidebarVM.selection == .history)
        #expect(session.historyVM.selectedCommit?.id == deep)
        #expect(session.historyVM.selection.count == 1)
        #expect(session.historyVM.commits.count > 200)
    }

    @Test func refOutsideHeadsHistoryOpensItsOwnHistory() async throws {
        let repo = try await GitRepository(path: root)
        let session = RepositorySession(repository: repo)
        await session.refs.refresh()
        let side = try #require(session.refs.localBranches.first { $0.name == "side" })
        #expect(await !session.historyVM.contains(side.targetSHA))
        await session.revealInHistory(side.targetSHA, fallback: .branch(side))
        #expect(session.sidebarVM.selection == .branch(side))
    }

    // MARK: Helpers

    @discardableResult
    private func git(_ args: [String], input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }
        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}
