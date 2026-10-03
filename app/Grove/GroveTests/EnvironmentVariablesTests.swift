// EnvironmentVariablesTests.swift
// GroveTests
//
// Custom environment variables: global and per-repository layering, persistence, and hooks receiving them.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@Suite(.serialized)
struct EnvironmentVariablesTests {

    private let suiteName = "grove-envvars-\(UUID().uuidString)"

    @Test func repositoryVariablesOverrideGlobalOnes() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        GitEnvironment.setCustomVariables([EnvironmentVariable(name: "HUSKY", value: "1"),
                                           EnvironmentVariable(name: "TEAM", value: "grove"),
                                           EnvironmentVariable(name: "BAD NAME", value: "x")], .global, defaults: defaults)
        GitEnvironment.setCustomVariables([EnvironmentVariable(name: "HUSKY", value: "0")], .repository("/tmp/repo"), defaults: defaults)

        let inRepo = GitEnvironment.variables(forRepositoryAt: "/tmp/repo", base: [:], defaults: defaults)
        #expect(inRepo == ["HUSKY": "0", "TEAM": "grove"])
        let elsewhere = GitEnvironment.variables(forRepositoryAt: "/tmp/other", base: [:], defaults: defaults)
        #expect(elsewhere == ["HUSKY": "1", "TEAM": "grove"])
    }

    @Test func clearingRemovesTheKey() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        GitEnvironment.setCustomVariables([EnvironmentVariable(name: "A", value: "1")], .global, defaults: defaults)
        GitEnvironment.setCustomVariables([], .global, defaults: defaults)
        #expect(defaults.object(forKey: GitEnvironment.Key.globalVariables) == nil)
    }

    @Test func hooksSeeTheVariables() async throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("grove-hookenv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        GitEnvironment.setCustomVariables([EnvironmentVariable(name: "GROVE_HOOK_VALUE", value: "from grove")],
                                          .repository(repo.path), defaults: defaults)

        let env = GitEnvironment.variables(forRepositoryAt: repo.path, base: [:], defaults: defaults)
        let shell = GitShell(workingDirectory: repo, runner: LocalGitRunner(gitPath: "/usr/bin/git"), extraEnvironment: env)
        try await shell.run(["init", "-q"])
        let hook = repo.appendingPathComponent(".git/hooks/pre-commit")
        try Data("#!/bin/sh\nprintf '%s' \"$GROVE_HOOK_VALUE\" > hook-output.txt\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try await shell.run(["-c", "user.name=T", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false",
                             "commit", "-q", "--allow-empty", "-m", "hooked"])

        #expect(try String(contentsOf: repo.appendingPathComponent("hook-output.txt"), encoding: .utf8) == "from grove")
    }
}
