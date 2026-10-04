// SubmoduleActionTests.swift
// GroveTests
//
// Add, update, fetch and remove submodules against a local library repository in a temp directory.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct SubmoduleActionTests {

    private let root: URL

    init() throws {
        // Git refuses local-path submodule clones unless the file protocol is allowed.
        setenv("GIT_ALLOW_PROTOCOL", "file", 1)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-submodule-\(UUID().uuidString)")
        for name in ["library", "app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            try git(["init", "-q", "-b", "main"], in: name)
            try git(["config", "user.name", "Tester"], in: name)
            try git(["config", "user.email", "tester@example.com"], in: name)
            try git(["config", "commit.gpgsign", "false"], in: name)
            try commit(name, file: "\(name).txt", message: "\(name) initial")
        }
    }

    private var libraryURL: String { root.appendingPathComponent("library").path }

    @Test func addListsTheSubmoduleAndStagesIt() async throws {
        let repo = try await GitRepository(path: root.appendingPathComponent("app"))
        try await repo.addSubmodule(url: libraryURL, path: "vendor/library", branch: nil)

        let submodules = try await repo.submodules()
        #expect(submodules.map(\.path) == ["vendor/library"])
        #expect(submodules.first?.state == .upToDate)
        let staged = try git(["diff", "--cached", "--name-only"], in: "app")
        #expect(staged.contains(".gitmodules") && staged.contains("vendor/library"))
    }

    @Test func updateToRemoteMovesToTheLibraryTip() async throws {
        let repo = try await GitRepository(path: root.appendingPathComponent("app"))
        try await repo.addSubmodule(url: libraryURL, path: "lib", branch: "main")
        try git(["commit", "-q", "-m", "add lib"], in: "app")
        try commit("library", file: "new.txt", message: "library moved on")

        try await repo.fetchSubmodule(path: "lib")
        try await repo.updateSubmodule(path: "lib", toRemote: true)

        #expect(try git(["rev-parse", "HEAD"], in: "app/lib") == git(["rev-parse", "HEAD"], in: "library"))
        #expect(try await repo.submodules().first?.state == .modified)

        try await repo.updateSubmodule(path: "lib", toRemote: false)
        #expect(try await repo.submodules().first?.state == .upToDate)
    }

    @Test func removeDeletesFolderEntryAndClone() async throws {
        let repo = try await GitRepository(path: root.appendingPathComponent("app"))
        try await repo.addSubmodule(url: libraryURL, path: "lib", branch: nil)
        try git(["commit", "-q", "-m", "add lib"], in: "app")

        try await repo.removeSubmodule(path: "lib")

        let app = root.appendingPathComponent("app")
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("lib").path))
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent(".git/modules/lib").path))
        let gitmodules = (try? String(contentsOf: app.appendingPathComponent(".gitmodules"), encoding: .utf8)) ?? ""
        #expect(!gitmodules.contains("lib"))
        #expect(try await repo.submodules().isEmpty)
    }

    @Test func initClonesAnUninitializedSubmodule() async throws {
        let repo = try await GitRepository(path: root.appendingPathComponent("app"))
        try await repo.addSubmodule(url: libraryURL, path: "lib", branch: nil)
        try git(["commit", "-q", "-m", "add lib"], in: "app")
        try git(["clone", "-q", root.appendingPathComponent("app").path, "copy"])

        let copy = try await GitRepository(path: root.appendingPathComponent("copy"))
        #expect(try await copy.submodules().first?.state == .uninitialized)
        try await copy.initSubmodule(path: "lib")
        #expect(try await copy.submodules().first?.state == .upToDate)
    }

    @Test func suggestsPathFromURL() {
        #expect(RefActionsViewModel.suggestedSubmodulePath(for: "https://github.com/example/icons.git") == "icons")
        #expect(RefActionsViewModel.suggestedSubmodulePath(for: "git@github.com:example/analytics") == "analytics")
    }

    // MARK: Helpers

    private func commit(_ repo: String, file: String, message: String) throws {
        try Data(message.utf8).write(to: root.appendingPathComponent(repo).appendingPathComponent(file))
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", message], in: repo)
    }

    @discardableResult
    private func git(_ args: [String], in directory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory.map { root.appendingPathComponent($0) } ?? root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
