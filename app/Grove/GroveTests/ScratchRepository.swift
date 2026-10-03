// ScratchRepository.swift
// GroveTests
//
// The scratch repository GroveKitTests use, for Grove's own tests that drive git.

import Foundation
@testable import GroveKit

/// A scratch repository under the temporary directory, driven with `/usr/bin/git`.
struct ScratchRepository {
    let root: URL

    init(_ name: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try commit("base.txt", "base\n", "base")
    }

    func commit(_ file: String, _ text: String, _ message: String, in directory: URL? = nil) throws {
        let folder = directory ?? root
        try Data(text.utf8).write(to: folder.appendingPathComponent(file))
        try git(["add", "-A"], in: folder)
        try git(["commit", "-q", "-m", message], in: folder)
    }

    func sha(_ revision: String) throws -> String {
        try git(["rev-parse", revision]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func git(_ args: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory ?? root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 { throw GitShellError.nonZeroExit(command: args.first ?? "", exitCode: process.terminationStatus, stderr: text) }
        return text
    }
}
