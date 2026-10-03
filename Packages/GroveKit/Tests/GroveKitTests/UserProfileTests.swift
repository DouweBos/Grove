// UserProfileTests.swift
// GroveKitTests
//
// Profiles persist in their own defaults suite, match identities, and write a scratch repository's local config.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct UserProfileTests {

    private let root: URL
    private let suiteName = "grove-profiles-\(UUID().uuidString)"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
    }

    @Test func matchesIdentityIgnoringEmailCase() {
        let profile = UserProfile(label: "Work", userName: "Ada", email: "Ada@Work.example")
        #expect(profile.matches(CommitIdentity(name: "Ada", email: "ada@work.example")))
        #expect(!profile.matches(CommitIdentity(name: "Grace", email: "ada@work.example")))
    }

    @Test func applyWritesLocalConfigAndUnsetsAnEmptyKey() async throws {
        try git(["config", "user.signingkey", "OLDKEY"])
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        try await repo.apply(UserProfile(label: "Home", userName: "Ada", email: "ada@home.example"))

        #expect(try await repo.localConfigValue("user.name") == "Ada")
        #expect(try await repo.localConfigValue("user.email") == "ada@home.example")
        #expect(try await repo.localConfigValue("user.signingkey") == nil)
    }

    // MARK: Helpers

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
        return text
    }
}
