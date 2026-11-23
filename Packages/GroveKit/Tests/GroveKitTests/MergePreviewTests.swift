// MergePreviewTests.swift
// GroveKitTests
//
// Compare's merge base and conflict check, against a scratch repository it removes.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct MergePreviewTests {

    @Test func findsTheMergeBaseAndWhetherMergingConflicts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-merge-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func commit(_ file: String, _ text: String, _ message: String) throws {
            try text.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            _ = try git(["add", "-A"])
            _ = try git(["commit", "-q", "-m", message])
        }
        _ = try git(["init", "-q", "-b", "main"])
        _ = try git(["config", "user.name", "Tester"])
        _ = try git(["config", "user.email", "tester@example.com"])
        _ = try git(["config", "commit.gpgsign", "false"])
        try commit("a.txt", "one\n", "base")
        let base = try git(["rev-parse", "HEAD"])
        _ = try git(["checkout", "-q", "-b", "clean"])
        try commit("b.txt", "new\n", "clean side")
        _ = try git(["checkout", "-q", "-b", "clash", "main"])
        try commit("a.txt", "clash\n", "clash side")
        _ = try git(["checkout", "-q", "main"])
        try commit("a.txt", "main\n", "main side")

        let repository = try await GitRepository(path: root, runner: LocalGitRunner())
        let clean = await repository.mergePreview(base: "main", compare: "clean")
        #expect(clean.mergeBase == base)
        #expect(clean.conflicts == false || clean.conflicts == nil)
        let clash = await repository.mergePreview(base: "main", compare: "clash")
        #expect(clash.mergeBase == base)
        #expect(clash.conflicts == true || clash.conflicts == nil)
        #expect(await repository.mergePreview(base: "main", compare: "nowhere") == MergePreview())
    }
}
