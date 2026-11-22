// HunkSafetyTests.swift
// GroveKitTests
//
// An action only ever changes the content its hunk showed.

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct HunkSafetyTests {

    @Test(arguments: PatchOperation.allCases, [false, true])
    func refusesAHunkWhoseContentChangedUnderTheSameHeader(_ operation: PatchOperation, lines: Bool) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\ntwo\nthree\n")
        try await scratch.commitAll()
        try await change(scratch, to: "one\nFIRST\nthree\n", for: operation)
        let shown = try await scratch.diff("file.txt", staged: operation.actsOnStaged).hunks[0]
        try await change(scratch, to: "one\nSECOND\nthree\n", for: operation)
        let current = try await scratch.diff("file.txt", staged: operation.actsOnStaged).hunks[0]
        #expect(current.header == shown.header)
        #expect(current.id != shown.id)
        #expect(Set(current.lines.map(\.id)).isDisjoint(with: shown.lines.map(\.id)))

        try await expectRefusal(scratch, saying: "changed since") {
            try await scratch.perform(operation, shown, in: "file.txt", lines: lines ? ["-two"] : nil)
        }
    }

    @Test func refusesLinesThatArentInTheHunk() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\ntwo\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", "one\nFIRST\n")
        let old = try await scratch.diff("file.txt", staged: false).hunks[0]
        try scratch.write("file.txt", "one\nSECOND\n")
        let current = try await scratch.diff("file.txt", staged: false).hunks[0]

        try await expectRefusal(scratch, saying: "changed since") {
            try await scratch.repository.stageLines(old.lines.filter { $0.type != .context }, in: current, file: "file.txt")
        }
    }

    @Test func refusesAnEmptyLineSelection() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", "ONE\n")
        let hunk = try await scratch.diff("file.txt", staged: false).hunks[0]
        try await expectRefusal(scratch, saying: "Select") {
            try await scratch.repository.stageLines([], in: hunk, file: "file.txt")
        }
    }

    @Test(arguments: PatchOperation.allCases)
    func refusesAnotherFilesHunk(_ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        for file in ["a.txt", "b.txt"] { try scratch.write(file, "one\n") }
        try await scratch.commitAll()
        for file in ["a.txt", "b.txt"] { try scratch.write(file, "ONE\n") }
        if operation.actsOnStaged { try await scratch.git("add", "-A") }
        let hunk = try await scratch.diff("a.txt", staged: operation.actsOnStaged).hunks[0]

        try await expectRefusal(scratch, saying: "changed since") { try await scratch.perform(operation, hunk, in: "b.txt") }
    }

    @Test func refusesAnEmptyFilesHunkOnceTheFileIsUntracked() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "")
        try await scratch.commitAll()
        try scratch.write("file.txt", "text\n")
        let hunk = try await scratch.diff("file.txt", staged: false).hunks[0]
        try await scratch.git("rm", "--cached", "-q", "file.txt")

        // The same header and lines would now delete the file.
        try await expectRefusal(scratch, saying: "changed since") { try await scratch.perform(.discard, hunk, in: "file.txt") }
    }

    @Test func aConfirmedDiscardOfAStaleHunkIsRefused() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", "FIRST\n")
        let vm = WorkingCopyViewModel(repository: scratch.repository)
        await vm.refresh()
        await vm.select(try #require(vm.statusEntries.first))
        let pending = PendingHunkDiscard(action: .discardHunk, hunk: try #require(vm.currentDiff?.hunks.first),
                                         lines: [], path: "file.txt")
        try scratch.write("file.txt", "SECOND\n")
        let before = try await scratch.snapshot()

        await vm.confirmHunkDiscard(pending, dontAskAgain: false)
        #expect(vm.errorMessage?.contains("changed since") == true)
        #expect(try await scratch.snapshot() == before)
        #expect(vm.currentDiff?.hunks.first?.lines.contains { $0.content == "SECOND" } == true)
    }

    @Test func aSecondClickDoesntApplyTheHunkTwice() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        let repeated = String(repeating: "x\n", count: 10)
        try scratch.write("file.txt", "top\n" + repeated)
        try await scratch.commitAll()
        try scratch.write("file.txt", "top\n" + repeated + "x\n")
        let hunk = try await scratch.diff("file.txt", staged: false).hunks[0]

        let clicks = (0..<2).map { _ in Task { try await scratch.repository.stageHunk(hunk, in: "file.txt") } }
        var refusals = 0
        for click in clicks where await !click.result.succeeded { refusals += 1 }

        #expect(refusals == 1)
        #expect(try await scratch.snapshot().index["file.txt"] == PatchBlob("top\n" + repeated + "x\n"))
    }

    @Test(arguments: PatchOperation.allCases)
    func changesTheShownOneOfIdenticalBlocks(_ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        let block = Array("abcdefghij").map(String.init)
        let base = Array(Array(repeating: block, count: 5).joined())
        var edited = base
        // An earlier hunk moves the second one by exactly one block.
        edited[24] = "CHANGED"
        edited.insert(contentsOf: Array(repeating: "new", count: 10), at: 1)
        let text = { (lines: [String]) in lines.map { $0 + "\n" }.joined() }
        try scratch.write("file.txt", text(base))
        try await scratch.commitAll()
        try scratch.write("file.txt", text(edited))
        if operation.actsOnStaged { try await scratch.git("add", "-A") }
        let diff = try await scratch.diff("file.txt", staged: operation.actsOnStaged)
        try #require(diff.hunks.count == 2)

        try await scratch.perform(operation, diff.hunks[1], in: "file.txt")

        var staged = base
        staged[24] = "CHANGED"
        var reverted = edited
        reverted[34] = "e"
        let result = try await scratch.snapshot()
        switch operation {
        case .stage: #expect(result.index["file.txt"] == PatchBlob(text(staged)))
        case .unstage: #expect(result.index["file.txt"] == PatchBlob(text(reverted)))
        case .discard: #expect(result.worktree["file.txt"] == PatchBlob(text(reverted)))
        }
    }

    private func change(_ scratch: HunkPatchScratch, to text: String, for operation: PatchOperation) async throws {
        try scratch.write("file.txt", text)
        if operation.actsOnStaged { try await scratch.git("add", "-A") }
    }

    private func expectRefusal(_ scratch: HunkPatchScratch, saying reason: String, _ action: () async throws -> Void) async throws {
        let before = try await scratch.snapshot()
        do {
            try await action()
            Issue.record("The action wasn't refused")
        } catch {
            #expect(error.localizedDescription.contains(reason), "\(error.localizedDescription)")
        }
        #expect(try await scratch.snapshot() == before)
    }
}

private extension Result {
    var succeeded: Bool {
        if case .success = self { true } else { false }
    }
}
