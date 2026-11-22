// ErrorDismissalTests.swift
// GroveKitTests
//
// A dismissed error stays dismissed through the refreshes that would report it again, until a read works.

import Foundation
import os
import Testing
@testable import GroveKit

/// Runs git, failing the subcommands a test names.
private nonisolated final class FailingRunner: GitRunner {
    private let git = LocalGitRunner(environment: { _, _ in ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"] })
    private let failing = OSAllocatedUnfairLock(initialState: Set<String>())

    func fail(_ commands: Set<String>) {
        failing.withLock { $0 = commands }
    }

    func run(_ invocation: GitInvocation) async throws -> ShellResult {
        let arguments = invocation.arguments
        // By subcommand, or by a format field such as `ahead-behind`.
        let broken = failing.withLock { commands in
            commands.first { name in arguments.first == name || arguments.contains { $0.contains("%(\(name):") } }
        }
        if let broken {
            return ShellResult(stdout: "", stderr: "fatal: \(broken) broke", exitCode: 128)
        }
        return try await git.run(invocation)
    }

    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        try await run(invocation)
    }

    var temporaryDirectory: URL { git.temporaryDirectory }
    func itemKind(at url: URL) async -> FileItemKind? { await git.itemKind(at: url) }
    func readFile(at url: URL) async throws -> Data { try await git.readFile(at: url) }
    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws { throw CocoaError(.featureUnsupported) }
    func removeItem(at url: URL) async throws { throw CocoaError(.featureUnsupported) }
    func createDirectory(at url: URL) async throws { throw CocoaError(.featureUnsupported) }
    func moveItem(at source: URL, to destination: URL) async throws { throw CocoaError(.featureUnsupported) }
    func contentsOfDirectory(at url: URL) async throws -> [String] { try await git.contentsOfDirectory(at: url) }
}

@MainActor
struct ErrorDismissalTests {

    @Test func aDismissedRefsErrorStaysGone() async throws {
        try await withRepository { repository, runner in
            let refs = RepositoryRefs(repository: repository)
            runner.fail(["for-each-ref"])
            await refs.refresh()
            #expect(refs.errorMessage != nil)

            refs.dismissError()
            await refs.refresh()
            #expect(refs.errorMessage == nil)

            runner.fail([])
            await refs.refresh()
            runner.fail(["for-each-ref"])
            await refs.refresh()
            #expect(refs.errorMessage != nil, "It failed again after working")
        }
    }

    @Test func aDismissedHistoryErrorStaysGone() async throws {
        try await withRepository { repository, runner in
            let history = HistoryViewModel(repository: repository)
            await history.loadInitial()
            runner.fail(["log"])
            await history.reload()
            #expect(history.errorMessage != nil)

            history.dismissError()
            await history.reload()
            #expect(history.errorMessage == nil)

            runner.fail([])
            await history.reload()
            runner.fail(["log"])
            await history.reload()
            #expect(history.errorMessage != nil, "It failed again after working")
        }
    }

    @Test func aDismissedStackErrorStaysGone() async throws {
        try await withRepository { repository, runner in
            let layer = StackLayer(branch: "feature", tipSHA: "HEAD", base: "", commits: [], health: [],
                                   ahead: 0, behind: 0, hasUpstream: false, isHEAD: false, depth: 0)
            let refs = RepositoryRefs(repository: repository)
            refs.replace(stacks: [BranchStack(name: "feature", trunk: "main", layers: [layer])])
            let stack = StackViewModel(repository: repository, refs: refs)
            runner.fail(["log"])
            stack.toggleExpanded(layer)
            await stack.refresh()
            #expect(stack.errorMessage != nil)

            stack.dismissError()
            await stack.refresh()
            #expect(stack.errorMessage == nil)
        }
    }

    @Test func aDismissedMergeStatusWarningStaysGoneAndKeepsDeletingOff() async throws {
        try await withRepository { repository, runner in
            try await repository.createBranch(name: "feature", from: nil, checkout: false)
            let review = BranchesReviewViewModel(repository: repository)
            runner.fail(["rev-list", "ahead-behind"])
            await review.refresh()
            #expect(review.mergeStatusWarning != nil)

            review.dismissMergeStatusWarning()
            await review.refresh()
            #expect(review.mergeStatusWarning == nil)
            #expect(!review.canDelete)
        }
    }

    @Test func dismissingABlameErrorReturnsToPickingAFile() async throws {
        try await withRepository { repository, _ in
            let blame = BlameViewModel(repository: repository)
            await blame.open(file: "missing.txt")
            #expect(blame.errorMessage != nil)

            blame.dismissError()
            #expect(blame.errorMessage == nil)
            #expect(blame.selectedFile == nil)
        }
    }

    @Test func aFileHistoryErrorCanBeDismissed() async throws {
        try await withRepository { repository, runner in
            let history = FileHistoryViewModel(repository: repository, filePath: "file.txt")
            runner.fail(["log"])
            await history.loadHistory()
            #expect(history.errorMessage != nil)

            history.dismissError()
            #expect(history.errorMessage == nil)
        }
    }

    @Test func theMissingLFSWarningStaysDismissed() async throws {
        try await withRepository { repository, _ in
            // Set directly: GroveKit caches that git-lfs is installed for the whole process.
            let missing = WorkingCopyLFS(status: LFSStatus(usesLFS: true, isInstalled: false))
            let changes = WorkingCopyViewModel(repository: repository)
            changes.lfs = missing
            #expect(changes.showsLFSWarning)

            changes.dismissLFSWarning()
            await changes.refresh()
            changes.lfs = missing
            #expect(!changes.showsLFSWarning)
        }
    }

    private func withRepository(_ body: (GitRepository, FailingRunner) async throws -> Void) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\n")
        try await scratch.commitAll()
        let runner = FailingRunner()
        try await body(GitRepository(path: scratch.root, runner: runner), runner)
    }
}
