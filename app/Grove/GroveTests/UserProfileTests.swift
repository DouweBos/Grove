// UserProfileTests.swift
// GroveTests
//
// Profiles persist in their own defaults suite, match identities, and write a scratch repository's local config.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

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

    @Test func profilesPersistAcrossStores() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserProfileStore(defaults: defaults)
        var work = store.add(label: "Work", userName: "Ada", email: "ada@work.example")
        work.signingKey = "ABC123"
        store.update(work)

        let reloaded = UserProfileStore(defaults: defaults)
        #expect(reloaded.profiles == [work])
        reloaded.delete(id: work.id)
        #expect(UserProfileStore(defaults: defaults).profiles.isEmpty)
    }

    @Test func settingsFillFromProfileAndSave() async throws {
        let repo = try await GitRepository(path: root)
        let settings = RepositorySettingsViewModel(repository: repo)
        await settings.load()
        let profile = UserProfile(label: "Work", userName: "Ada", email: "ada@work.example", signingKey: "~/.ssh/work.pub")

        settings.applyProfile(profile)
        #expect(settings.matchingProfile(in: [profile]) == profile)
        await settings.save()

        #expect(try await repo.localConfigValue("user.signingkey") == "~/.ssh/work.pub")
        #expect(await repo.commitIdentity() == CommitIdentity(name: "Ada", email: "ada@work.example"))
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
