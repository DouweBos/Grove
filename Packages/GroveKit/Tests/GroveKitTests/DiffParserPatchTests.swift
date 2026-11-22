// DiffParserPatchTests.swift
// GroveKitTests
//
// The shape of the patches DiffParser builds; HunkPatches/ checks what git does with them.

import Foundation
import Testing
@testable import GroveKit

struct DiffParserPatchTests {

    // MARK: buildPatch

    @Test func diffParser_buildPatch_producesValidHeader() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: hunk.lines, in: hunk, filePath: "Sources/App/Foo.swift")

        #expect(patch.hasPrefix("diff --git a/Sources/App/Foo.swift b/Sources/App/Foo.swift\n"))
        #expect(patch.contains("--- a/Sources/App/Foo.swift\n"))
        #expect(patch.contains("+++ b/Sources/App/Foo.swift\n"))
        #expect(patch.contains("@@ -1,4 +1,5 @@"))
    }

    @Test func diffParser_buildPatch_linesHaveCorrectPrefixes() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: hunk.lines, in: hunk, filePath: "Sources/App/Foo.swift")
        let lines = patch.components(separatedBy: "\n")

        // After the 4-line header (diff, ---, +++, @@), patch lines start at index 4.
        let patchBodyLines = lines.dropFirst(4)
        for line in patchBodyLines where !line.isEmpty {
            let first = line.first
            #expect(first == "+" || first == "-" || first == " ",
                    "Unexpected prefix character '\(first as Any)' in patch line: \(line)")
        }
    }

    @Test func diffParser_buildPatch_withCustomOldPath() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(
            from: hunk.lines,
            in: hunk,
            filePath: "Sources/App/Foo.swift",
            oldPath: "Sources/App/OldFoo.swift"
        )

        #expect(patch.contains("a/Sources/App/OldFoo.swift"))
        #expect(patch.contains("b/Sources/App/Foo.swift"))
    }

    // MARK: buildPatch (undoing)

    @Test func buildPatchUndoing_keepsUnselectedAdditionsAndDropsUnselectedDeletions() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first,
              let selected = hunk.lines.first(where: { $0.type == .addition }) else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: [selected], in: hunk, filePath: "Foo.swift", undoing: true)

        #expect(patch.contains("-func newFunction() {\n"))
        #expect(patch.contains("\n     // added line\n"))
        #expect(!patch.contains("oldFunction"))
    }

    @Test func buildPatchUndoing_recreatesADeletedFileWithItsMode() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.deletedFile),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse deletedFile fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: hunk.lines, in: hunk, filePath: result.filePath,
                                          change: .deleted(mode: "100755"), undoing: true)

        #expect(patch.contains("new file mode 100755\n--- /dev/null\n"))
    }

    // MARK: buildPatch (selectedLines)

    @Test func buildPatchSelectedLines_allSelected_matchesFullPatch() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let fullPatch = DiffParser.buildPatch(from: hunk.lines, in: hunk, filePath: "Sources/App/Foo.swift")
        let selectedPatch = DiffParser.buildPatch(
            from: hunk.lines,
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )

        // Body lines (everything after the 4-line header) must be identical.
        let fullBody = fullPatch.components(separatedBy: "\n").dropFirst(4)
        let selectedBody = selectedPatch.components(separatedBy: "\n").dropFirst(4)
        #expect(Array(fullBody) == Array(selectedBody))
    }

    @Test func buildPatchSelectedLines_noneSelected_additionsSkippedDeletionsBecomeContext() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(
            from: [],
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let lines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // With nothing selected: additions vanish, deletions become context.
        #expect(!lines.contains(where: { $0.hasPrefix("+") }), "No additions expected when selection is empty")
        #expect(!lines.contains(where: { $0.hasPrefix("-") }), "No deletions expected when selection is empty")
        #expect(lines.allSatisfy { $0.hasPrefix(" ") }, "All remaining lines must be context")
    }

    @Test func buildPatchSelectedLines_onlyAdditionsSelected() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let additions = hunk.lines.filter { $0.type == .addition }
        let patch = DiffParser.buildPatch(
            from: additions,
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // Additions appear as +, the deletion becomes a context line, no - lines.
        let additionLines = bodyLines.filter { $0.hasPrefix("+") }
        let deletionLines = bodyLines.filter { $0.hasPrefix("-") }
        #expect(additionLines.count == 2)
        #expect(deletionLines.isEmpty, "Unselected deletion must not appear as a - line")
        // The unselected deletion should have become a context line.
        #expect(bodyLines.contains(where: { $0.hasPrefix(" ") && $0.contains("oldFunction") }))
    }

    @Test func buildPatchSelectedLines_onlyDeletionsSelected() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let deletions = hunk.lines.filter { $0.type == .deletion }
        let patch = DiffParser.buildPatch(
            from: deletions,
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // Deletion appears as -, unselected additions are skipped entirely.
        let deletionLines = bodyLines.filter { $0.hasPrefix("-") }
        let additionLines = bodyLines.filter { $0.hasPrefix("+") }
        #expect(deletionLines.count == 1)
        #expect(additionLines.isEmpty, "Unselected additions must be skipped")
    }

    @Test func buildPatchSelectedLines_headerCountsRecalculated() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        // Select only the two additions; the deletion becomes context.
        // Effective lines: 3 context (original) + 1 context (was deletion) + 2 additions = 6 lines.
        // oldCount = context lines only = 3 + 1 = 4; newCount = context + additions = 4 + 2 = 6.
        let additions = hunk.lines.filter { $0.type == .addition }
        let patch = DiffParser.buildPatch(
            from: additions,
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )

        #expect(patch.contains("@@ -\(hunk.oldStart),4 +\(hunk.newStart),6 @@"))
    }

    @Test func buildPatchSelectedLines_contextLinesAlwaysPresent() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let contextLines = hunk.lines.filter { $0.type == .context }

        // Test with empty selection — context lines must still appear.
        let patch = DiffParser.buildPatch(
            from: [],
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }
        let contextBodyLines = bodyLines.filter { $0.hasPrefix(" ") }

        // At minimum, the original context lines are present (deletion also becomes context,
        // so total context can be >= original context count).
        #expect(contextBodyLines.count >= contextLines.count)
        // Specifically, "import Foundation" and "}" are always present.
        #expect(contextBodyLines.contains(where: { $0.contains("import Foundation") }))
        #expect(contextBodyLines.contains(where: { $0.contains("}") }))
    }

    @Test func buildPatchSelectedLines_withOldPath() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(
            from: hunk.lines,
            in: hunk,
            filePath: "Sources/App/Foo.swift",
            oldPath: "Sources/App/OldFoo.swift"
        )

        #expect(patch.hasPrefix("diff --git a/Sources/App/OldFoo.swift b/Sources/App/Foo.swift\n"))
        #expect(patch.contains("--- a/Sources/App/OldFoo.swift\n"))
        #expect(patch.contains("+++ b/Sources/App/Foo.swift\n"))
    }

    @Test func buildPatchSelectedLines_singleAdditionSelected() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        guard let firstAddition = hunk.lines.first(where: { $0.type == .addition }) else {
            Issue.record("Expected at least one addition in singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(
            from: [firstAddition],
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // Exactly one addition line in the output.
        let additionLines = bodyLines.filter { $0.hasPrefix("+") }
        #expect(additionLines.count == 1)
        #expect(additionLines[0].contains(firstAddition.content))
    }

    @Test func buildPatchSelectedLines_singleDeletionSelected() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        guard let deletion = hunk.lines.first(where: { $0.type == .deletion }) else {
            Issue.record("Expected a deletion line in singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(
            from: [deletion],
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // Exactly one deletion line; additions (unselected) are skipped.
        let deletionLines = bodyLines.filter { $0.hasPrefix("-") }
        #expect(deletionLines.count == 1)
        #expect(deletionLines[0].contains("oldFunction"))
        #expect(!bodyLines.contains(where: { $0.hasPrefix("+") }))
    }

    @Test func buildPatchSelectedLines_unselectedDeletionBecomesContextLine() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        guard let deletion = hunk.lines.first(where: { $0.type == .deletion }) else {
            Issue.record("Expected a deletion line in singleHunk fixture")
            return
        }

        // Select everything except the deletion.
        let withoutDeletion = hunk.lines.filter { $0.id != deletion.id }
        let patch = DiffParser.buildPatch(
            from: withoutDeletion,
            in: hunk,
            filePath: "Sources/App/Foo.swift"
        )
        let bodyLines = patch.components(separatedBy: "\n").dropFirst(4).filter { !$0.isEmpty }

        // The deletion must appear as a space-prefixed context line, not as a - line.
        let expectedContextLine = " \(deletion.content)"
        #expect(bodyLines.contains(expectedContextLine),
                "Unselected deletion '\(deletion.content)' must appear as context line '\(expectedContextLine)'")
        #expect(!bodyLines.contains(where: { $0.hasPrefix("-") }), "No - lines expected when deletion is unselected")
    }
}
