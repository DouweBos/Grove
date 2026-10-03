// SigningEnvironmentTests.swift
// GroveTests
//
// 1Password environment overrides, reading the signing setup, and a real SSH test signature with a throwaway key.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

struct SigningEnvironmentTests {

    @Test func onePasswordSettingsBecomeEnvironment() throws {
        let suite = "grove-env-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(GitEnvironment.variables(forRepositoryAt: "/tmp/x", base: [:], defaults: defaults).isEmpty)

        defaults.set(true, forKey: GitEnvironment.Key.useOnePasswordAgent)
        defaults.set(true, forKey: GitEnvironment.Key.useOnePasswordSigning)
        let env = GitEnvironment.variables(forRepositoryAt: "/tmp/x", base: ["GIT_CONFIG_COUNT": "1"], defaults: defaults)

        #expect(env["SSH_AUTH_SOCK"] == GitEnvironment.onePasswordAgentSocket)
        // Appended after the one override the environment already had.
        #expect(env["GIT_CONFIG_COUNT"] == "3")
        #expect(env["GIT_CONFIG_KEY_1"] == "gpg.format" && env["GIT_CONFIG_VALUE_1"] == "ssh")
        #expect(env["GIT_CONFIG_KEY_2"] == "gpg.ssh.program" && env["GIT_CONFIG_VALUE_2"] == GitEnvironment.onePasswordSigner)
    }

    @Test func signingConfigReflectsEnvironmentOverrides() async {
        let overrides = GitEnvironment.configOverrides(["gpg.format": "ssh", "gpg.ssh.program": "/opt/signer",
                                                        "user.signingkey": "~/.ssh/id.pub", "commit.gpgsign": "true"], base: [:])
        let shell = GitShell(workingDirectory: FileManager.default.temporaryDirectory, extraEnvironment: overrides)
        let config = await SigningInspector.load(shell: shell)
        #expect(config.format == "ssh")
        #expect(config.program == "/opt/signer")
        #expect(config.signingKey == "~/.ssh/id.pub")
        #expect(config.signsCommits)
    }

    @Test func testSignWithThrowawaySSHKey() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("grove-sshkey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = dir.appendingPathComponent("id_ed25519").path
        let keygen = Process()
        keygen.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        keygen.arguments = ["-q", "-t", "ed25519", "-N", "", "-f", key]
        try keygen.run()
        keygen.waitUntilExit()

        let env = GitEnvironment.configOverrides(["gpg.format": "ssh", "user.signingkey": key + ".pub"], base: [:])
        let status = try await SigningInspector.testSign(environment: env)
        #expect(!status.isEmpty)
        #expect(!SigningInspector.describe(signatureStatus: status).isEmpty)
    }

    @Test func failedSigningThrows() async {
        let env = GitEnvironment.configOverrides(["gpg.format": "ssh", "user.signingkey": "/nonexistent/key.pub"], base: [:])
        await #expect(throws: (any Error).self) { try await SigningInspector.testSign(environment: env) }
    }
}
