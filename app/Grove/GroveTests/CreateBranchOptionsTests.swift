// CreateBranchOptionsTests.swift
// GroveTests
//
// New Branch options: tracking the starting branch, a recorded parent, pinning, and pulling from the parent.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct CreateBranchOptionsTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-newbranch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "T"])
        try git(["config", "user.email", "t@t"])
        try "base\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."])
        try git(["commit", "-qm", "base"])
    }

    @Test func pinningPersistsForTheRepository() {
        let path = root.path
        BranchPins.pin("feature/x", inRepositoryAt: path)
        #expect(BranchPins.names(forRepositoryAt: path) == ["feature/x"])
        UserDefaults.standard.removeObject(forKey: BranchPins.key(forRepositoryAt: path))
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
