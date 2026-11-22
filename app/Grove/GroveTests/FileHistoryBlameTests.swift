// FileHistoryBlameTests.swift
// GroveTests
//
// File History's Open Blame at This Revision lands in the Blame tab, against a scratch repository.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct FileHistoryBlameTests {

    @Test(arguments: [false, true])
    func opensBlameAtTheRevision(fromABranchsHistory: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-history-blame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runner = LocalGitRunner(environment: { _, _ in
            ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
             "GIT_AUTHOR_NAME": "Tester", "GIT_AUTHOR_EMAIL": "tester@example.com",
             "GIT_COMMITTER_NAME": "Tester", "GIT_COMMITTER_EMAIL": "tester@example.com"]
        })
        let shell = GitShell(workingDirectory: root, runner: runner)
        try await shell.run(["init", "-q", "-b", "main"])
        let original = "one\ntwo\nthree\nfour\nfive\n"
        try Data(original.utf8).write(to: root.appendingPathComponent("old name.txt"))
        try await shell.run(["add", "-A"])
        try await shell.run(["commit", "-q", "-m", "add it"])
        try await shell.run(["mv", "old name.txt", "café.txt"])
        try Data("ONE\ntwo\nthree\nfour\nfive\n".utf8).write(to: root.appendingPathComponent("café.txt"))
        // Another file in the commit, so the old name can't be guessed from it.
        try Data("other\n".utf8).write(to: root.appendingPathComponent("other.txt"))
        try await shell.run(["add", "-A"])
        try await shell.run(["commit", "-q", "-m", "rename it"])

        let session = RepositorySession(repository: try await GitRepository(path: root, runner: runner))
        let history = fromABranchsHistory ? session.filteredHistoryVM(for: "main") : session.historyVM
        history.request(.fileHistory("café.txt"))
        let fileHistory = history.fileHistory(path: "café.txt")
        await fileHistory.loadHistory()
        let first = try #require(fileHistory.commits.last)

        await fileHistory.openBlame(first)

        #expect(history.pendingAction == nil)
        #expect(session.sidebarVM.selection == .blame)
        #expect(session.blameVM.revision == first.id)
        #expect(session.blameVM.selectedFile == "old name.txt")
        #expect(session.blameVM.errorMessage == nil)
        #expect(session.blameVM.lines.map(\.text) == ["one", "two", "three", "four", "five"])
    }
}
