// GitFlowTests.swift
// GroveTests
//
// git-flow done natively: config, start and finish of features, releases and hotfixes in a scratch repository.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct GitFlowTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["config", "tag.gpgsign", "false"])
        try commit(file: "base.txt", message: "initial")
    }

    @Test func configRoundTripsThroughGitConfig() async throws {
        let repo = try await GitRepository(path: root)
        #expect(await repo.gitFlowConfig() == nil)
        var config = GitFlowConfig()
        config.versionTagPrefix = "v"
        try await repo.initializeGitFlow(config)

        #expect(await repo.gitFlowConfig() == config)
        #expect(repo.currentBranch?.name == "develop")
        #expect(try git(["rev-parse", "develop"]) == git(["rev-parse", "main"]))
    }

    @Test func classifiesFlowBranches() {
        let config = GitFlowConfig()
        #expect(config.classify(branch: "feature/login")?.kind == .feature)
        #expect(config.classify(branch: "hotfix/1.0.1")?.name == "1.0.1")
        #expect(config.classify(branch: "main") == nil)
        #expect(config.classify(branch: "feature/") == nil)
    }

    @Test func featureFinishMergesIntoDevelopWithoutFastForward() async throws {
        let repo = try await GitRepository(path: root)
        let config = GitFlowConfig()
        try await repo.initializeGitFlow(config)
        try await repo.startFlowBranch(.feature, name: "login", base: nil, config: config)
        #expect(repo.currentBranch?.name == "feature/login")
        try commit(file: "login.txt", message: "login screen")

        try await repo.finishFlowBranch(.feature, name: "login", config: config, options: GitFlowFinishOptions())

        #expect(repo.currentBranch?.name == "develop")
        #expect(try git(["log", "-1", "--format=%P", "develop"]).split(separator: " ").count == 2)
        #expect(try git(["branch", "--list", "feature/login"]).isEmpty)
    }

    @Test func squashedFeatureLeavesOneCommit() async throws {
        let repo = try await GitRepository(path: root)
        let config = GitFlowConfig()
        try await repo.initializeGitFlow(config)
        try await repo.startFlowBranch(.feature, name: "search", base: nil, config: config)
        try commit(file: "a.txt", message: "a")
        try commit(file: "b.txt", message: "b")

        try await repo.finishFlowBranch(.feature, name: "search", config: config, options: GitFlowFinishOptions(squash: true))

        #expect(try git(["rev-list", "--count", "main..develop"]) == "1")
        #expect(try git(["branch", "--list", "feature/search"]).isEmpty)
    }

    @Test func releaseFinishTagsProductionAndMergesBack() async throws {
        let repo = try await GitRepository(path: root)
        var config = GitFlowConfig()
        config.versionTagPrefix = "v"
        try await repo.initializeGitFlow(config)
        try await repo.startFlowBranch(.release, name: "1.0.0", base: nil, config: config)
        try commit(file: "version.txt", message: "bump version")

        var options = GitFlowFinishOptions()
        options.tagMessage = "Release 1.0.0"
        options.keepBranch = true
        try await repo.finishFlowBranch(.release, name: "1.0.0", config: config, options: options)

        #expect(try git(["describe", "--tags", "main"]) == "v1.0.0")
        #expect(try git(["merge-base", "--is-ancestor", "release/1.0.0", "develop"]).isEmpty)
        #expect(try !git(["branch", "--list", "release/1.0.0"]).isEmpty)
    }

    @Test func hotfixMergesIntoReleaseInProgress() async throws {
        let repo = try await GitRepository(path: root)
        let config = GitFlowConfig()
        try await repo.initializeGitFlow(config)
        try await repo.startFlowBranch(.release, name: "2.0.0", base: nil, config: config)
        try await repo.startFlowBranch(.hotfix, name: "1.0.1", base: nil, config: config)
        try commit(file: "fix.txt", message: "fix crash")
        let fix = try git(["rev-parse", "HEAD"])

        try await repo.finishFlowBranch(.hotfix, name: "1.0.1", config: config, options: GitFlowFinishOptions())

        #expect(repo.currentBranch?.name == "release/2.0.0")
        #expect(try git(["merge-base", "--is-ancestor", fix, "release/2.0.0"]).isEmpty)
        #expect(try git(["merge-base", "--is-ancestor", fix, "main"]).isEmpty)
        #expect(throws: GitShellError.self) { try git(["merge-base", "--is-ancestor", fix, "develop"]) }
    }

    @Test func startRejectsExistingBranch() async throws {
        let repo = try await GitRepository(path: root)
        let config = GitFlowConfig()
        try await repo.initializeGitFlow(config)
        try await repo.startFlowBranch(.feature, name: "dup", base: nil, config: config)
        await #expect(throws: GitFlowError.self) {
            try await repo.startFlowBranch(.feature, name: "dup", base: nil, config: config)
        }
    }

    // MARK: Helpers

    private func commit(file: String, message: String) throws {
        try Data(message.utf8).write(to: root.appendingPathComponent(file))
        try git(["add", "."])
        try git(["commit", "-q", "-m", message])
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
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
