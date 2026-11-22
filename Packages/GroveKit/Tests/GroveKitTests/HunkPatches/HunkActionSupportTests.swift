// HunkActionSupportTests.swift
// GroveKitTests
//
// The statuses that offer hunk actions are the ones real git lets GroveKit act on.

import Foundation
import Testing
@testable import GroveKit

nonisolated enum SupportCase: CaseIterable, Sendable {
    case modified, untracked, intentToAdd, deleted
    case stagedModified, stagedAdded, stagedDeleted, stagedRename, stagedCopy
    case typeChange, stagedTypeChange

    var isStaged: Bool {
        switch self {
        case .modified, .untracked, .intentToAdd, .deleted, .typeChange: false
        default: true
        }
    }

    var status: FileStatus {
        switch self {
        case .modified, .stagedModified: .modified
        case .untracked: .untracked
        case .intentToAdd, .stagedAdded: .added
        case .deleted, .stagedDeleted: .deleted
        case .stagedRename: .renamed
        case .stagedCopy: .copied
        case .typeChange, .stagedTypeChange: .typeChange
        }
    }

    var path: String {
        switch self {
        case .untracked, .intentToAdd, .stagedAdded: "new.txt"
        case .stagedRename, .stagedCopy: "other.txt"
        default: "file.txt"
        }
    }
}

@MainActor
struct HunkActionSupportTests {

    @Test func theRuleCoversEveryStatus() {
        let supported = Set(FileStatus.allCases.filter(\.supportsHunkActions))
        #expect(supported == [.modified, .added, .deleted, .renamed, .copied, .untracked])
    }

    @Test(arguments: SupportCase.allCases)
    func offersExactlyWhatGitTakes(_ test: SupportCase) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        let base = (1...12).map { "line \($0)\n" }.joined()
        try scratch.write("file.txt", base)
        try await scratch.commitAll()
        try await change(test, base: base, in: scratch)

        let entry = try #require(try await scratch.repository.status().first { $0.path == test.path })
        let shown = test.isStaged ? entry.indexStatus : entry.workdirStatus
        #expect(shown == test.status)
        let diff = try await scratch.repository.diff(for: entry, staged: test.isStaged, ignoreWhitespace: false)
        let hunk = try #require(diff.hunks.first)
        let operation: PatchOperation = test.isStaged ? .unstage : .stage

        if shown.supportsHunkActions {
            let before = try await scratch.snapshot()
            try await scratch.perform(operation, hunk, in: test.path)
            #expect(try await scratch.snapshot().index != before.index)
        } else {
            let before = try await scratch.snapshot()
            await #expect(throws: (any Error).self) { try await scratch.perform(operation, hunk, in: test.path) }
            #expect(try await scratch.snapshot() == before)
        }
    }

    private func change(_ test: SupportCase, base: String, in scratch: HunkPatchScratch) async throws {
        let edited = base.replacingOccurrences(of: "line 5\n", with: "five\n")
        switch test {
        case .modified, .stagedModified:
            try scratch.write("file.txt", edited)
        case .untracked, .stagedAdded:
            try scratch.write("new.txt", "new\n")
        case .intentToAdd:
            try scratch.write("new.txt", "new\n")
            try await scratch.git("add", "-N", "new.txt")
        case .deleted, .stagedDeleted:
            try scratch.delete("file.txt")
        case .stagedRename:
            try scratch.delete("file.txt")
            try scratch.write("other.txt", edited)
        case .stagedCopy:
            try await scratch.git("config", "status.renames", "copies")
            try scratch.write("file.txt", base + "source edit\n")
            try scratch.write("other.txt", edited)
        case .typeChange, .stagedTypeChange:
            try scratch.delete("file.txt")
            try FileManager.default.createSymbolicLink(at: scratch.root.appendingPathComponent("file.txt"),
                                                       withDestinationURL: URL(fileURLWithPath: "/nowhere"))
        }
        if test.isStaged { try await scratch.git("add", "-A") }
    }
}
