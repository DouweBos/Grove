// WorktreeResolverTests.swift
// GroveTests
//
// Linking worktrees to their main repository from git's files, and folding them on Tower import.

import Foundation
import Testing
@testable import Grove

@Suite(.serialized)
struct WorktreeResolverTests {

    private let root: URL
    private var repo: String { root.appendingPathComponent("main").path }
    private var worktree: String { root.appendingPathComponent("wt-feature").path }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-worktree-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main", "main"])
        try git(["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"], in: repo)
        try git(["worktree", "add", "-q", "-b", "feature/login", worktree], in: repo)
    }

    @Test func worktreeResolvesToMainRepository() {
        #expect(WorktreeResolver.mainRepositoryPath(forWorktreeAt: worktree) == repo)
        #expect(WorktreeResolver.mainRepositoryPath(forWorktreeAt: repo) == nil)
    }

    @Test func submoduleIsNotAWorktree() throws {
        // A submodule's `.git` file points into the superproject's `.git/modules`, which has no commondir.
        let modules = root.appendingPathComponent("main/.git/modules/vendor/lib")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: modules.appendingPathComponent("HEAD"))
        let submodule = root.appendingPathComponent("main/vendor/lib")
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        try Data("gitdir: ../../.git/modules/vendor/lib\n".utf8).write(to: submodule.appendingPathComponent(".git"))

        #expect(WorktreeResolver.mainRepositoryPath(forWorktreeAt: submodule.path) == nil)
    }

    @Test func repositoryListsItsWorktreesWithBranch() {
        let linked = WorktreeResolver.linkedWorktrees(ofRepositoryAt: repo)
        #expect(linked.map(\.path) == [worktree])
        #expect(linked.first?.branch == "feature/login")
        #expect(linked.first?.isMissing == false)
    }

    @Test func deletedWorktreeFolderIsMissing() throws {
        try FileManager.default.removeItem(atPath: worktree)
        #expect(WorktreeResolver.linkedWorktrees(ofRepositoryAt: repo).first?.isMissing == true)
    }

    @Test func worktreeBookmarkNestsUnderBookmarkedRepository() {
        let index = WorktreeIndex(bookmarks: [bookmark(repo), bookmark(worktree)])
        #expect(index.isNested(bookmark(worktree)))
        #expect(!index.isNested(bookmark(repo)))
        #expect(index.worktreesByRepository[repo]?.count == 1)
    }

    @Test func worktreeBookmarkStaysTopLevelWithoutItsRepository() {
        #expect(!WorktreeIndex(bookmarks: [bookmark(worktree)]).isNested(bookmark(worktree)))
    }

    @Test func towerImportReplacesWorktreesWithTheirRepository() {
        #expect(TowerImporter.foldingWorktrees([bookmark(repo), bookmark(worktree)]).map(\.path) == [repo])
        #expect(TowerImporter.foldingWorktrees([bookmark(worktree), bookmark(worktree)]).map(\.path) == [repo])
    }

    @Test func syntheticIDIsStablePerPath() {
        #expect(WorktreeIndex.syntheticID(forPath: worktree) == WorktreeIndex.syntheticID(forPath: worktree))
        #expect(WorktreeIndex.syntheticID(forPath: worktree) != WorktreeIndex.syntheticID(forPath: repo))
    }

    // MARK: - Helpers

    private func bookmark(_ path: String) -> RepositoryBookmarkData {
        RepositoryBookmarkData(id: UUID(), path: path, displayName: URL(fileURLWithPath: path).lastPathComponent,
                               addedDate: Date(), lastOpenedDate: nil, sortOrder: 0, groupID: nil)
    }

    @discardableResult
    private func git(_ args: [String], in directory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory ?? root.path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad, userInfo: [NSDebugDescriptionErrorKey: output]) }
        return output
    }
}
