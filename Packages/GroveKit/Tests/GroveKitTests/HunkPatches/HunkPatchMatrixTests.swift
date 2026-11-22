// HunkPatchMatrixTests.swift
// GroveKitTests
//
// Every kind of change x whole hunk or lines x stage, unstage, discard, against real git.

import Foundation
import Testing
@testable import GroveKit

nonisolated struct PatchCase: Sendable, CustomStringConvertible {
    enum Scope: String, CaseIterable { case hunk, lines }

    let scenario: PatchScenario
    let operation: PatchOperation
    let scope: Scope
    let path: String
    let oldPath: String

    var description: String { "\(scenario.name) / \(operation.rawValue) / \(scope.rawValue) / \(path)" }

    static let paths = [
        (path: "file.txt", oldPath: "old.txt"),
        (path: "my dir/a file.txt", oldPath: "my dir/an old file.txt"),
        (path: "mü/日本 café.txt", oldPath: "mü/früher café.txt"),
    ]

    /// Why a combination can't exist, or nil when it's in the matrix.
    static func skipReason(_ scenario: PatchScenario, _ operation: PatchOperation) -> String? {
        scenario.kind == .untracked && operation == .unstage ? "an untracked file has nothing in the index to unstage" : nil
    }

    static var all: [PatchCase] {
        PatchScenario.all.flatMap { scenario in
            PatchOperation.allCases.filter { skipReason(scenario, $0) == nil }.flatMap { operation in
                Scope.allCases.flatMap { scope in
                    paths.map { PatchCase(scenario: scenario, operation: operation, scope: scope, path: $0.path, oldPath: $0.oldPath) }
                }
            }
        }
    }

    static var skipped: [PatchScenario] {
        PatchScenario.all.filter { skipReason($0, .unstage) != nil }
    }
}

@MainActor
struct HunkPatchMatrixTests {

    @Test(arguments: PatchCase.all)
    func leavesExactBytesAndModes(_ test: PatchCase) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try await prepare(test, in: scratch)

        let diff = try await scratch.diff(test.path, staged: test.operation.actsOnStaged)
        try #require(diff.hunks.count == 1)
        var expected = try await scratch.snapshot()
        expect(test, changes: &expected)

        try await scratch.perform(test.operation, diff.hunks[0], in: test.path,
                                  lines: test.scope == .lines ? test.scenario.selection : nil)

        let result = try await scratch.snapshot()
        #expect(result.index == expected.index)
        #expect(result.worktree == expected.worktree)
    }

    /// The combinations the matrix leaves out, each shown to have nothing to act on.
    @Test(arguments: PatchCase.skipped)
    func untrackedHasNothingToUnstage(_ scenario: PatchScenario) async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try await scratch.commitAll()
        try scratch.write("file.txt", scenario.after ?? "")
        #expect(try await scratch.diff("file.txt", staged: true).hunks.isEmpty)
    }

    @Test func aModeOnlyChangeHasNoHunks() async throws {
        let scratch = try await HunkPatchScratch()
        defer { scratch.remove() }
        try scratch.write("file.txt", "a\n")
        try await scratch.commitAll()
        try scratch.write("file.txt", PatchBlob(mode: "100755", "a\n"))
        #expect(try await scratch.diff("file.txt", staged: false).hunks.isEmpty)
    }

    private func prepare(_ test: PatchCase, in scratch: HunkPatchScratch) async throws {
        let scenario = test.scenario
        let source = scenario.kind == .renamed ? test.oldPath : test.path
        try scratch.write("keep.txt", "keep\n")
        if let before = scenario.before { try scratch.write(source, PatchBlob(mode: scenario.mode, before)) }
        try await scratch.commitAll()

        if scenario.kind == .renamed { try scratch.delete(source) }
        if let after = scenario.after {
            try scratch.write(test.path, PatchBlob(mode: scenario.changedMode ?? scenario.mode, after))
        } else {
            try scratch.delete(test.path)
        }
        if test.operation.actsOnStaged {
            try await scratch.git("add", "-A")
        } else if scenario.kind == .renamed || (scenario.kind == .tracked && scenario.before == nil) {
            // An unstaged addition or rename exists only once the new path is intent-to-add.
            try await scratch.git("add", "-N", "--", test.path)
        }
    }

    private func expect(_ test: PatchCase, changes expected: inout PatchSnapshot) {
        let scenario = test.scenario
        let wholeHunk = test.scope == .hunk
        let changedMode = scenario.changedMode ?? scenario.mode
        // Hunk and line actions change content; a chmod stays where it was.
        let forwardMode = scenario.before == nil ? changedMode : scenario.mode
        let reverseMode = scenario.after == nil ? scenario.mode : changedMode
        let forward = (wholeHunk ? scenario.after : scenario.staged).map { PatchBlob(mode: forwardMode, $0) }
        let reverse = (wholeHunk ? scenario.before : scenario.reverted).map { PatchBlob(mode: reverseMode, $0) }
        switch test.operation {
        case .stage:
            expected.index[test.path] = forward
            if scenario.kind == .renamed { expected.index[test.oldPath] = nil }
        case .unstage:
            expected.index[test.path] = reverse
        case .discard:
            expected.worktree[test.path] = reverse
        }
    }
}
