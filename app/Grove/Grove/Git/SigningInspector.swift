// GitKit/SigningInspector.swift
// Grove
//
// The commit signing setup git will use, and a test signature made in a throwaway repository.

import Foundation
import GroveKit

struct SigningConfig: Equatable, Sendable {
    /// `gpg.format`: openpgp (the default), ssh or x509.
    var format = "openpgp"
    var signingKey: String?
    var signsCommits = false
    var signsTags = false
    /// The program for `format`: `gpg.program`, `gpg.ssh.program` or `gpg.x509.program`.
    var program: String?
    var allowedSignersFile: String?

    var formatTitle: String {
        switch format {
        case "ssh": "SSH"
        case "x509": "X.509 (S/MIME)"
        default: "GPG (OpenPGP)"
        }
    }

    var programKey: String {
        switch format {
        case "ssh": "gpg.ssh.program"
        case "x509": "gpg.x509.program"
        default: "gpg.program"
        }
    }

    var defaultProgram: String {
        switch format {
        case "ssh": "ssh-keygen"
        case "x509": "gpgsm"
        default: "gpg"
        }
    }
}

nonisolated enum SigningInspector {

    /// Effective config outside any repository: system and global files plus Grove's environment overrides.
    static func load(shell: GitShell = GitShell(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)) async -> SigningConfig {
        func value(_ key: String) async -> String? {
            let result = try? await shell.runAllowingFailure(["config", "--get", key])
            let text = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return result?.isSuccess == true && !text.isEmpty ? text : nil
        }
        var config = SigningConfig()
        config.format = await value("gpg.format")?.lowercased() ?? "openpgp"
        config.signingKey = await value("user.signingkey")
        config.signsCommits = await value("commit.gpgsign")?.lowercased() == "true"
        config.signsTags = await value("tag.gpgsign")?.lowercased() == "true"
        config.program = await value(config.programKey)
        config.allowedSignersFile = await value("gpg.ssh.allowedSignersFile")
        return config
    }

    /// Signs an empty commit in a temporary repository, so nothing real is touched; returns git's signature check.
    static func testSign(environment: [String: String] = [:]) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grove-signing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shell = GitShell(workingDirectory: directory, extraEnvironment: environment)
        try await shell.run(["init", "-q"])
        // GPG picks the key by committer email when no signing key is set, so the real identity is kept when there is one.
        let hasIdentity = try await shell.runAllowingFailure(["config", "--get", "user.email"]).isSuccess
        let identity = hasIdentity ? [] : ["-c", "user.name=Grove", "-c", "user.email=signing-test@grove.invalid"]
        try await shell.run(identity + ["commit", "-q", "--allow-empty", "-S", "-m", "Grove signing test"])
        let check = try await shell.runAllowingFailure(["log", "-1", "--format=%G? %GS %GK"])
        return check.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `%G?` status letters from `git log`.
    static func describe(signatureStatus line: String) -> String {
        switch line.first {
        case "G": "Signed and verified."
        case "U": "Signed; the key isn't marked as trusted."
        case "N" where !line.isEmpty: "Signed. git can't verify it here, e.g. SSH signing without an allowed signers file."
        case "E": "Signed. git couldn't check it, e.g. the public key is missing."
        default: "Signed."
        }
    }
}
