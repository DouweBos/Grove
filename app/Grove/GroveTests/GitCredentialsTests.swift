// GitCredentialsTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@Suite(.serialized)
struct GitCredentialsTests {

    private func ask(_ prompt: String, env: [String: String]) throws -> (status: Int32, answer: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(env["GIT_ASKPASS"]))
        process.arguments = [prompt]
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let answer = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, answer.trimmingCharacters(in: .newlines))
    }

    @Test func answersPromptsOnlyForKnownHosts() throws {
        defer { GitCredentials.update([]) }
        GitCredentials.update([
            (HostingAccount(kind: .github, username: "octo"), "gho_token"),
            (HostingAccount(kind: .gitlab, host: "gitlab.example.com", username: "tanuki"), "glpat")
        ])
        let env = GitCredentials.environment()
        #expect(env["GROVE_CREDENTIAL_COUNT"] == "2")
        #expect(try ask("Username for 'https://github.com': ", env: env) == (0, "octo"))
        #expect(try ask("Password for 'https://octo@github.com': ", env: env) == (0, "gho_token"))
        #expect(try ask("Username for 'https://gitlab.example.com': ", env: env) == (0, "oauth2"))
        #expect(try ask("Password for 'https://oauth2@gitlab.example.com': ", env: env) == (0, "glpat"))
        // A lookalike host gets nothing, so git fails as it would without Grove.
        #expect(try ask("Username for 'https://github.com.evil.example': ", env: env).status == 1)
    }

    @Test func noAccountsLeavesGitAlone() {
        GitCredentials.update([])
        #expect(GitCredentials.environment().isEmpty)
    }

    @Test func usernamesFollowEachService() {
        #expect(GitCredentials.username(for: HostingAccount(kind: .gitlab, username: "me")) == "oauth2")
        #expect(GitCredentials.username(for: HostingAccount(kind: .bitbucket, username: "me")) == "me")
        #expect(GitCredentials.username(for: HostingAccount(kind: .github, username: "")) == "x-access-token")
    }
}
