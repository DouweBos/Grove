// HistoryExportTests.swift
// GroveTests
//
// Patches that git am applies, and ZIP archives of a commit or ref, against a scratch repository.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct HistoryExportTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        for index in 1...3 {
            try Data("\(index)\n".utf8).write(to: root.appendingPathComponent("f\(index).txt"))
            try git(["add", "-A"])
            try git(["commit", "-q", "-m", "commit \(index)"])
        }
        try git(["tag", "v1", "HEAD~1"])
    }

    @Test func patchOfSelectedCommitsAppliesInOrder() async throws {
        let vm = HistoryViewModel(repository: try await GitRepository(path: root))
        await vm.loadInitial()
        let url = root.appendingPathComponent("../\(UUID().uuidString).patch").standardizedFileURL
        await vm.savePatch(Array(vm.commits[0...1]), to: url)
        #expect(vm.errorMessage == nil)

        try git(["checkout", "-q", "-b", "replay", "HEAD~2"])
        try git(["am", "-q", url.path])
        #expect(try git(["log", "--format=%s"]).split(separator: "\n") == ["commit 3", "commit 2", "commit 1"])
    }

    @Test func commitAndRefArchivesHoldTheirFiles() async throws {
        let repo = try await GitRepository(path: root)
        let history = HistoryViewModel(repository: repo)
        await history.loadInitial()
        let commitZip = root.appendingPathComponent("../\(UUID().uuidString).zip").standardizedFileURL
        await history.exportArchive(of: history.commits[2], to: commitZip)
        #expect(try zipEntries(commitZip) == ["f1.txt"])

        let sidebar = SidebarViewModel(repository: repo)
        let tagZip = root.appendingPathComponent("../\(UUID().uuidString).zip").standardizedFileURL
        await sidebar.exportFiles(of: "v1", to: tagZip)
        #expect(try zipEntries(tagZip) == ["f1.txt", "f2.txt"])
    }

    // MARK: Helpers

    private func zipEntries(_ url: URL) throws -> [String] {
        try run("/usr/bin/zipinfo", ["-1", url.path]).split(separator: "\n").map(String.init).sorted()
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        try run("/usr/bin/git", args)
    }

    private func run(_ executable: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}
