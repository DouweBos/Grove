// GitNamingTests.swift
// GroveKitTests
//
// What GroveKit writes into a repository and the user defaults carries the names the app chose.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct GitNamingTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Tester"], ["config", "user.email", "t@example.com"],
                     ["config", "commit.gpgsign", "false"], ["commit", "-q", "--allow-empty", "-m", "first"]] {
            try git(args)
        }
    }

    @Test func branchParentsUseTheAppsKey() async throws {
        let argus = try await GitRepository(path: root, runner: LocalGitRunner(), naming: GitNaming(name: "argus"))
        try await argus.createBranch(name: "feature", from: "main", checkout: false, track: false, parent: "main")
        #expect(try git(["config", "--local", "branch.feature.argus-parent"]) == "main")
        #expect(try await argus.branchParents() == ["feature": "main"])

        let other = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(try await other.branchParents().isEmpty)
    }

    @Test func scratchFilesUseTheAppsPrefix() async throws {
        let repository = try await GitRepository(path: root, runner: LocalGitRunner(), naming: GitNaming(name: "argus"))
        #expect(repository.scratchURL("todo").lastPathComponent.hasPrefix("argus-todo-"))
        #expect(GitNaming.default.stateDirectory == "grovekit")
    }

    @Test func preferencesLiveUnderTheAppsPrefix() {
        let suite = "grovekit-naming-\(UUID().uuidString)"
        let store = try! #require(UserDefaults(suiteName: suite))
        let (oldStore, oldPrefix) = (ViewModelPreferences.store, ViewModelPreferences.keyPrefix)
        defer {
            (ViewModelPreferences.store, ViewModelPreferences.keyPrefix) = (oldStore, oldPrefix)
            store.removePersistentDomain(forName: suite)
        }
        ViewModelPreferences.store = store
        ViewModelPreferences.keyPrefix = "argus.git."
        ViewModelPreferences.warnOnHunkDiscard = false
        #expect(store.object(forKey: "argus.git.warnOnHunkDiscard") as? Bool == false)
        #expect(store.object(forKey: "warnOnHunkDiscard") == nil)
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: "")
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
