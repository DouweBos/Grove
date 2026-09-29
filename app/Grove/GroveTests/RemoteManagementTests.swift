// RemoteManagementTests.swift
// GroveTests
//
// Adding and removing remotes from the sidebar and repository settings, against a scratch repository and bare server.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct RemoteManagementTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-remotes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", "-b", "main", "server.git"])
        try git(["clone", "-q", "server.git", "seed"])
        try git(["init", "-q", "-b", "main", "app"])
        for repo in ["seed", "app"] {
            try git(["config", "user.name", "Tester"], in: repo)
            try git(["config", "user.email", "tester@example.com"], in: repo)
            try git(["config", "commit.gpgsign", "false"], in: repo)
        }
        try commit("seed", file: "seed.txt", message: "initial")
        try git(["push", "-q", "origin", "main"], in: "seed")
        try commit("app", file: "app.txt", message: "local work")
    }

    private var serverURL: String { root.appendingPathComponent("server.git").path }

    private func makeSidebar() async throws -> SidebarViewModel {
        let vm = SidebarViewModel(repository: try await GitRepository(path: root.appendingPathComponent("app")))
        await vm.refresh()
        return vm
    }

    @Test func addingFetchesTheRemoteBranches() async throws {
        let vm = try await makeSidebar()
        #expect(vm.remotes.isEmpty && vm.suggestedRemoteName == "origin")
        vm.requestAddRemote()

        try await vm.addRemote(name: "origin", url: serverURL)

        #expect(!vm.isAddingRemote)
        #expect(vm.remotes.map(\.name) == ["origin"])
        #expect(vm.remoteBranches.map(\.name).contains("origin/main"))
        #expect(vm.suggestedRemoteName.isEmpty)
    }

    @Test func aFailedFetchKeepsTheRemoteAndReportsIt() async throws {
        let vm = try await makeSidebar()
        try await vm.addRemote(name: "origin", url: root.appendingPathComponent("missing.git").path)

        #expect(vm.remotes.map(\.name) == ["origin"])
        #expect(vm.errorMessage != nil)
    }

    @Test func aTakenNameStaysOpenWithTheError() async throws {
        try git(["remote", "add", "origin", serverURL], in: "app")
        let vm = try await makeSidebar()
        #expect(vm.remoteNameProblem("origin") != nil)
        #expect(vm.remoteNameProblem("my fork") != nil)
        #expect(vm.remoteNameProblem("upstream") == nil)

        vm.requestAddRemote()
        await #expect(throws: (any Error).self) { try await vm.addRemote(name: "origin", url: serverURL) }
        #expect(vm.isAddingRemote)
    }

    @Test func removingDropsItsRemoteBranches() async throws {
        try git(["remote", "add", "origin", serverURL], in: "app")
        try git(["fetch", "-q", "origin"], in: "app")
        let vm = try await makeSidebar()
        let origin = try #require(vm.remotes.first)

        await vm.removeRemote(origin)

        #expect(vm.remotes.isEmpty && vm.remoteBranches.isEmpty)
        #expect(try git(["remote"], in: "app").isEmpty)
    }

    @Test func settingsRemovesAndReloads() async throws {
        try git(["remote", "add", "origin", serverURL], in: "app")
        let settings = RepositorySettingsViewModel(repository: try await GitRepository(path: root.appendingPathComponent("app")))
        var changed = false
        settings.onRepositoryChanged = { changed = true }
        await settings.load()
        #expect(settings.remoteNames == ["origin"])

        await settings.removeRemote("origin")

        #expect(settings.remoteNames.isEmpty && changed)
        #expect(settings.errorMessage == nil)
    }

    @Test func addingTracksSameNamedBranchesLikeAClone() async throws {
        try git(["branch", "feature"], in: "app")
        let vm = try await makeSidebar()

        try await vm.addRemote(name: "origin", url: serverURL)

        let upstreams = Dictionary(uniqueKeysWithValues: vm.localBranches.map { ($0.name, $0.upstreamShortName) })
        #expect(upstreams["main"] == "origin/main")
        #expect(upstreams["feature"] == .some(nil))
    }

    @Test func addingLeavesAnExistingUpstreamAlone() async throws {
        try git(["remote", "add", "upstream", serverURL], in: "app")
        try git(["fetch", "-q", "upstream"], in: "app")
        try git(["branch", "--set-upstream-to=upstream/main", "main"], in: "app")
        let vm = try await makeSidebar()

        try await vm.addRemote(name: "origin", url: serverURL)

        #expect(vm.localBranches.first { $0.name == "main" }?.upstreamShortName == "upstream/main")
    }

    @Test func trackAndStopTracking() async throws {
        try git(["remote", "add", "origin", serverURL], in: "app")
        try git(["fetch", "-q", "origin"], in: "app")
        let vm = try await makeSidebar()
        let main = try #require(vm.localBranches.first { $0.name == "main" })
        #expect(main.upstream == nil)
        #expect(vm.trackableRemoteBranches == ["origin/main"])
        #expect(vm.suggestedUpstream(for: main) == "origin/main")

        try await vm.track(main, remoteBranch: "origin/main")
        let tracking = try #require(vm.localBranches.first { $0.name == "main" })
        #expect(tracking.upstreamShortName == "origin/main")

        await vm.stopTracking(tracking)
        #expect(vm.localBranches.first { $0.name == "main" }?.upstream == nil)
        #expect(vm.errorMessage == nil)
    }

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
