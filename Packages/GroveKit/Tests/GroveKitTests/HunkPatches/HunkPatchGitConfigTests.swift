// HunkPatchGitConfigTests.swift
// GroveKitTests
//
// Patches hold up under the repository's diff settings, odd paths and end-of-line conversion.

import Foundation
import Testing
@testable import GroveKit

@MainActor
struct HunkPatchGitConfigTests {

    @Test(arguments: [
        "diff.noprefix=true", "diff.mnemonicPrefix=true", "core.quotePath=false", "color.diff=always",
        "diff.suppressBlankEmpty=true", "diff.context=0", "apply.whitespace=fix", "apply.ignoreWhitespace=change",
    ], PatchOperation.allCases)
    func ignoresDiffAndApplySettings(_ setting: String, _ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("café.txt", "one\n\ntwo  \n")
        try await scratch.commitAll()
        let parts = setting.split(separator: "=").map(String.init)
        try await scratch.git("config", parts[0], parts[1])
        try scratch.write("café.txt", "one\n\nTWO  \n")

        try await expectRoundTrip(scratch, "café.txt", operation, before: "one\n\ntwo  \n", after: "one\n\nTWO  \n")
    }

    @Test(arguments: [
        "quote\"d.txt", "back\\slash.txt", "tab\there.txt", "trailing ", "x b/y.txt", "-dash.txt", "[id].txt", ":colon.txt",
    ], PatchOperation.allCases)
    func handlesOddPaths(_ path: String, _ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        // "[id].txt" as a glob would also pick these two.
        for file in [path, "d.txt", "i.txt"] { try scratch.write(file, "one\n") }
        try await scratch.commitAll()
        for file in [path, "d.txt", "i.txt"] { try scratch.write(file, "ONE\n") }

        try await expectRoundTrip(scratch, path, operation, before: "one\n", after: "ONE\n")
    }

    @Test(arguments: PatchOperation.allCases)
    func keepsLinesStartingWithCombiningMarks(_ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        let before = "\u{301}one\n\u{301}same\n", after = "\u{301}ONE\n\u{301}same\n"
        try scratch.write("file.txt", before)
        try await scratch.commitAll()
        try scratch.write("file.txt", after)

        try await expectRoundTrip(scratch, "file.txt", operation, before: before, after: after)
    }

    @Test func convertsLineEndingsAsGitAddAndRestoreDo() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try await scratch.git("config", "core.autocrlf", "true")
        try scratch.write("edited.txt", "one\r\ntwo\r\n")
        try scratch.write("kept.txt", "one\r\ntwo\r\n")
        try await scratch.commitAll()
        try scratch.write("edited.txt", "ONE\r\ntwo\r\n")
        try scratch.write("kept.txt", "ONE\r\ntwo\r\n")
        try scratch.write("new.txt", "new\r\n")

        for file in ["edited.txt", "new.txt"] {
            try await scratch.perform(.stage, try await scratch.diff(file, staged: false).hunks[0], in: file)
        }
        try await scratch.perform(.discard, try await scratch.diff("kept.txt", staged: false).hunks[0], in: "kept.txt")

        let result = try await scratch.snapshot()
        #expect(result.index["edited.txt"] == PatchBlob("ONE\ntwo\n"))
        #expect(result.index["new.txt"] == PatchBlob("new\n"))
        #expect(result.worktree["kept.txt"] == PatchBlob("one\r\ntwo\r\n"))
    }

    @Test(arguments: [PatchOperation.unstage, .discard])
    func takesBackAHunkShownWithoutWhitespaceChanges(_ operation: PatchOperation) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\ntwo\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", "  one\nTWO\n")
        if operation.actsOnStaged { try await scratch.git("add", "-A") }
        let hunk = try await scratch.diff("file.txt", staged: operation.actsOnStaged, ignoreWhitespace: true).hunks[0]

        try await scratch.perform(operation, hunk, in: "file.txt")

        let result = try await scratch.snapshot()
        let changed = operation.actsOnStaged ? result.index : result.worktree
        #expect(changed["file.txt"] == PatchBlob("  one\ntwo\n"))
    }

    @Test func refusesToStageAHunkThatHidesWhitespaceChanges() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "one\ntwo\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", "  one\nTWO\n")
        let hunk = try await scratch.diff("file.txt", staged: false, ignoreWhitespace: true).hunks[0]

        do {
            try await scratch.perform(.stage, hunk, in: "file.txt")
            Issue.record("The action wasn't refused")
        } catch {
            #expect(error.localizedDescription.contains("whitespace"))
        }
    }

    @Test func refusesPartOfATypeChange() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "text\n")
        try await scratch.commitAll()
        try scratch.delete("file.txt")
        try FileManager.default.createSymbolicLink(atPath: scratch.root.appendingPathComponent("file.txt").path,
                                                   withDestinationPath: "elsewhere")
        let hunk = try await scratch.diff("file.txt", staged: false).hunks[0]

        do {
            try await scratch.perform(.stage, hunk, in: "file.txt")
            Issue.record("The action wasn't refused")
        } catch {
            #expect(error.localizedDescription.contains("type"))
        }
        #expect(try await scratch.snapshot().index["file.txt"] == PatchBlob("text\n"))
    }

    private func expectRoundTrip(_ scratch: HunkPatchScratch, _ path: String, _ operation: PatchOperation,
                                 before: String, after: String) async throws {
        if operation.actsOnStaged { try await scratch.git("add", "-A") }
        let diff = try await scratch.diff(path, staged: operation.actsOnStaged)
        #expect(diff.filePath == path)
        var expected = try await scratch.snapshot()
        switch operation {
        case .stage: expected.index[path] = PatchBlob(after)
        case .unstage: expected.index[path] = PatchBlob(before)
        case .discard: expected.worktree[path] = PatchBlob(before)
        }

        try await scratch.perform(operation, try #require(diff.hunks.first), in: path)

        #expect(try await scratch.snapshot() == expected)
    }
}
