// FileHistoryPathTests.swift
// GroveKitTests
//
// File History knows what a file was called at each of its commits.

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct FileHistoryPathTests {

    @Test func followsEveryRename() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("first name.txt", "one\ntwo\nthree\n")
        try await scratch.commitAll()
        try await scratch.git("mv", "first name.txt", "café.txt")
        try await scratch.commitAll()
        try await scratch.git("mv", "café.txt", "last.txt")
        try await scratch.commitAll()

        let shas = try await scratch.repository.fileLog(path: "last.txt", maxCount: 10).map(\.id)
        let paths = try await scratch.repository.filePaths(inHistoryOf: "last.txt", maxCount: 10)

        #expect(shas.map { paths[$0] } == ["last.txt", "café.txt", "first name.txt"])
    }

    @Test func offersBlameOnlyWhenTheHistoryCanOpenIt() {
        let history = HistoryViewModel(repository: MockGitRepository())
        #expect(history.fileHistory(path: "README.md").onOpenBlame == nil)
        history.onOpenBlame = { _, _ in }
        #expect(history.fileHistory(path: "README.md").onOpenBlame != nil)
    }
}
