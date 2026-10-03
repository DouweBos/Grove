// SVNTests.swift
// GroveKitTests
//
// git-svn detection from config and unsent commit counts, in a scratch repository shaped like a git svn clone.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct SVNTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-svn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try git(["commit", "-q", "--allow-empty", "-m", "r1"])
    }

    @Test func parsesStandardLayoutRemote() {
        let status = SVNStatus(configValues: ["svn-remote.svn.url": "https://svn.example.com/project",
                                              "svn-remote.svn.fetch": "trunk:refs/remotes/origin/trunk",
                                              "svn-remote.svn.branches": "branches/*:refs/remotes/origin/*"])
        #expect(status.isSVN)
        #expect(status.url == "https://svn.example.com/project")
        #expect(status.trackingRef == "refs/remotes/origin/trunk")
    }

    @Test func plainGitRepositoryIsNotSVN() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(await repo.svnStatus().isSVN == false)
    }

    @Test func countsCommitsNotYetSentToSubversion() async throws {
        // What git svn clone leaves behind: the remote in config and the tracking ref at the last revision.
        try git(["config", "svn-remote.svn.url", "https://svn.example.com/project"])
        try git(["config", "svn-remote.svn.fetch", ":refs/remotes/git-svn"])
        try git(["update-ref", "refs/remotes/git-svn", "HEAD"])
        try git(["commit", "-q", "--allow-empty", "-m", "local 1"])
        try git(["commit", "-q", "--allow-empty", "-m", "local 2"])

        let status = try await GitRepository(path: root, runner: LocalGitRunner()).svnStatus()
        #expect(status.isSVN)
        #expect(status.trackingRef == "refs/remotes/git-svn")
        #expect(status.unsentCount == 2)
    }

    @Test func missingGitSVNGivesAnInstallHint() async throws {
        guard await SVNSupport.gitPath(using: LocalGitRunner()) == nil else { return }
        try git(["config", "svn-remote.svn.url", "https://svn.example.com/project"])
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(await repo.svnStatus().isAvailable == false)
        await #expect(throws: SVNError.self) { try await repo.svnDcommit() }
        #expect(SVNError.notInstalled.localizedDescription.contains("brew install git subversion"))
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
