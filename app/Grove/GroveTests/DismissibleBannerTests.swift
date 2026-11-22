// DismissibleBannerTests.swift
// GroveTests
//
// What Grove's own banners dismiss stays dismissed when the read behind it runs again.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct DismissibleBannerTests {

    @Test func aDismissedArtifactsErrorStaysGoneWhilePolling() async {
        let repo = MockGitRepository()
        repo.ci.error = .noHostedRemote
        let detail = CIRunDetailViewModel(repository: repo)
        let run = MockData.ciRuns[0]
        await detail.show(run)
        #expect(detail.artifactsError != nil)

        detail.dismissArtifactsError()
        await detail.show(run)
        #expect(detail.artifactsError == nil)

        await detail.reload()
        #expect(detail.artifactsError != nil, "Asking again shows why it fails")
    }

    @Test func aDismissedGraphErrorStaysGoneWhilePolling() async {
        let repo = MockGitRepository()
        repo.ci.error = .noHostedRemote
        let detail = CIRunDetailViewModel(repository: repo)
        let run = MockData.ciRuns[0]
        await detail.show(run)
        #expect(detail.graphError != nil)

        detail.dismissGraphError()
        await detail.show(run)
        #expect(detail.graphError == nil)
    }

    @Test func anotherRunDoesntInheritAGraphError() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        let good = MockData.ciRuns[2]
        await detail.show(good)
        repo.ci.error = .noHostedRemote
        let bad = CIRun(id: 9001, number: 1, attempt: 1, title: "broken", workflowID: 9, workflowName: "Broken", event: "push",
                        branch: "main", headSHA: "f00", status: .success, actor: "tester", createdDate: good.createdDate,
                        updatedDate: good.updatedDate, webURL: "", workflowPath: ".github/workflows/missing.yml")
        await detail.show(bad)
        #expect(detail.graphError != nil)

        repo.ci.error = nil
        await detail.show(good)
        #expect(detail.graphError == nil)
    }

    @Test func aDismissedSnapshotErrorStaysGoneUntilAReadWorks() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.storeSnapshotError("Unreadable", for: "/tmp/repo")
        window.dismissSnapshotError(for: "/tmp/repo")
        window.storeSnapshotError("Unreadable", for: "/tmp/repo")
        #expect(window.snapshotErrors.isEmpty)

        window.storeSnapshot(RepositorySnapshot(branch: nil, changedCount: 0, remotes: [], commits: []), for: "/tmp/repo")
        window.storeSnapshotError("Unreadable", for: "/tmp/repo")
        #expect(window.snapshotErrors["/tmp/repo"] == "Unreadable")
    }

    @Test func aDismissedSettingsErrorStaysGoneThroughARefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-settings-error-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runner = LocalGitRunner(environment: { _, _ in ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"] })
        try await GitShell(workingDirectory: root, runner: runner).run(["init", "-q", "-b", "main"])
        let repository = try await GitRepository(path: root, runner: runner)
        // An unreadable config fails every read of the settings.
        try Data("[broken\n".utf8).write(to: root.appendingPathComponent(".git/config"))
        let settings = RepositorySettingsViewModel(repository: repository)
        await settings.load()
        #expect(settings.errorMessage != nil)

        settings.dismissError()
        await settings.load()
        #expect(settings.errorMessage == nil)
    }
}
