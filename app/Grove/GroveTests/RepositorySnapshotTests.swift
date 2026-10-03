// RepositorySnapshotTests.swift
// GroveTests
//
// The browser keeps a repository's last snapshot visible while it re-reads it.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct RepositorySnapshotTests {

    @Test func reselectingKeepsTheLastSnapshotWhileRefreshing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grove-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = RepositoryBookmarkData(id: UUID(), path: folder.path, displayName: "repo",
                                              addedDate: Date(), lastOpenedDate: nil, sortOrder: 0, groupID: nil)
        let window = WindowViewModel(manager: MockRepositoryManager())

        await window.refreshSnapshot(for: bookmark)
        let first = try #require(window.snapshot(for: bookmark))
        #expect(!window.isRefreshingSnapshot(for: bookmark))

        let refresh = Task { await window.refreshSnapshot(for: bookmark) }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(window.isRefreshingSnapshot(for: bookmark))
        #expect(window.snapshot(for: bookmark)?.commits.map(\.id) == first.commits.map(\.id))
        await refresh.value
        #expect(!window.isRefreshingSnapshot(for: bookmark))
        #expect(window.snapshot(for: bookmark) != nil)
    }
}
