// DiffParserTests.swift
// GroveTests
//
// Tests for DiffParser — covers unified diff parsing, hunk structure,
// line numbering, DiffStats calculation, and patch construction.

import Foundation
import Testing
@testable import Grove

// MARK: - Fixtures

private enum DiffFixtures {

    // A minimal single-hunk diff with context, deletions, and additions.
    static let singleHunk = """
    diff --git a/Sources/App/Foo.swift b/Sources/App/Foo.swift
    index abc1234..def5678 100644
    --- a/Sources/App/Foo.swift
    +++ b/Sources/App/Foo.swift
    @@ -1,5 +1,6 @@
     import Foundation

    -func oldFunction() {
    +func newFunction() {
    +    // added line
     }
    """

    // Two hunks in the same file.
    static let multiHunk = """
    diff --git a/Sources/App/Bar.swift b/Sources/App/Bar.swift
    index 111aaaa..222bbbb 100644
    --- a/Sources/App/Bar.swift
    +++ b/Sources/App/Bar.swift
    @@ -1,3 +1,4 @@
     import Foundation
    +import Combine

    @@ -10,3 +11,3 @@
    -let old = 1
    +let new = 2
     // end
    """

    // A newly added file — all lines are additions (old file is /dev/null).
    static let addedFile = """
    diff --git a/Sources/App/Brand.swift b/Sources/App/Brand.swift
    new file mode 100644
    index 0000000..aabbccd
    --- /dev/null
    +++ b/Sources/App/Brand.swift
    @@ -0,0 +1,3 @@
    +import Foundation
    +
    +struct Brand {}
    """

    // A completely deleted file — all lines are deletions.
    static let deletedFile = """
    diff --git a/Sources/App/Legacy.swift b/Sources/App/Legacy.swift
    deleted file mode 100644
    index abc1234..0000000
    --- a/Sources/App/Legacy.swift
    +++ /dev/null
    @@ -1,3 +0,0 @@
    -import Foundation
    -
    -struct Legacy {}
    """

    // A renamed file diff (no content changes).
    static let renamedFile = """
    diff --git a/Sources/App/Old.swift b/Sources/App/New.swift
    similarity index 100%
    rename from Sources/App/Old.swift
    rename to Sources/App/New.swift
    """

    // Binary file marker.
    static let binaryFile = """
    diff --git a/Resources/Icon.png b/Resources/Icon.png
    index 000000..abcdef 100644
    Binary files a/Resources/Icon.png and b/Resources/Icon.png differ
    """

    // Diff with the "no newline at end of file" marker.
    static let noNewlineAtEnd = """
    diff --git a/Sources/App/Baz.swift b/Sources/App/Baz.swift
    index abc1234..def5678 100644
    --- a/Sources/App/Baz.swift
    +++ b/Sources/App/Baz.swift
    @@ -1,2 +1,2 @@
     import Foundation
    -let x = 1
    +let x = 2
    \\ No newline at end of file
    """

    // Two separate files in one diff output.
    static let twoFiles = """
    diff --git a/Sources/App/Alpha.swift b/Sources/App/Alpha.swift
    index aaaaaaa..bbbbbbb 100644
    --- a/Sources/App/Alpha.swift
    +++ b/Sources/App/Alpha.swift
    @@ -1,2 +1,2 @@
    -let alpha = 1
    +let alpha = 2
    diff --git a/Sources/App/Beta.swift b/Sources/App/Beta.swift
    index ccccccc..ddddddd 100644
    --- a/Sources/App/Beta.swift
    +++ b/Sources/App/Beta.swift
    @@ -1,2 +1,2 @@
    -let beta = 1
    +let beta = 2
    """
}

// MARK: - DiffParserTests

struct DiffParserTests {

    // MARK: Empty input

    @Test func diffParser_returnsEmptyForEmptyString() {
        let results = DiffParser.parse("")
        #expect(results.isEmpty)
    }

    // MARK: Single-hunk diff

    @Test func diffParser_parsesSingleHunk() {
        let results = DiffParser.parse(DiffFixtures.singleHunk)

        #expect(results.count == 1)
        let result = results[0]
        #expect(result.filePath == "Sources/App/Foo.swift")
        #expect(!result.isBinary)
        #expect(result.hunks.count == 1)
    }

    @Test func diffParser_singleHunk_hunkHeaderValues() {
        let result = DiffParser.parse(DiffFixtures.singleHunk)[0]
        let hunk = result.hunks[0]

        #expect(hunk.oldStart == 1)
        #expect(hunk.oldCount == 5)
        #expect(hunk.newStart == 1)
        #expect(hunk.newCount == 6)
    }

    @Test func diffParser_singleHunk_lineTypes() {
        let result = DiffParser.parse(DiffFixtures.singleHunk)[0]
        let lines = result.hunks[0].lines

        let additions = lines.filter { $0.type == .addition }
        let deletions = lines.filter { $0.type == .deletion }
        let context   = lines.filter { $0.type == .context }

        #expect(additions.count == 2)
        #expect(deletions.count == 1)
        #expect(context.count == 3)
    }

    @Test func diffParser_singleHunk_lineNumbering() {
        let result = DiffParser.parse(DiffFixtures.singleHunk)[0]
        let lines = result.hunks[0].lines

        // First context line: old=1, new=1
        #expect(lines[0].oldLineNumber == 1)
        #expect(lines[0].newLineNumber == 1)

        // Second context line
        #expect(lines[1].oldLineNumber == 2)
        #expect(lines[1].newLineNumber == 2)

        // Deletion line: has old number but no new
        let deletion = lines.first(where: { $0.type == .deletion })
        #expect(deletion?.oldLineNumber != nil)
        #expect(deletion?.newLineNumber == nil)

        // Addition line: has new number but no old
        let addition = lines.first(where: { $0.type == .addition })
        #expect(addition?.oldLineNumber == nil)
        #expect(addition?.newLineNumber != nil)
    }

    // MARK: Multi-hunk diff

    @Test func diffParser_parsesMultipleHunks() {
        let results = DiffParser.parse(DiffFixtures.multiHunk)

        #expect(results.count == 1)
        #expect(results[0].hunks.count == 2)
    }

    @Test func diffParser_multiHunk_secondHunkValues() {
        let hunk = DiffParser.parse(DiffFixtures.multiHunk)[0].hunks[1]

        #expect(hunk.oldStart == 10)
        #expect(hunk.newStart == 11)
    }

    // MARK: Added file

    @Test func diffParser_parsesAddedFile() {
        let results = DiffParser.parse(DiffFixtures.addedFile)

        #expect(results.count == 1)
        let result = results[0]
        #expect(result.filePath == "Sources/App/Brand.swift")

        let lines = result.hunks[0].lines
        #expect(lines.allSatisfy { $0.type == .addition })
        #expect(lines.count == 3)
    }

    @Test func diffParser_addedFile_noOldLineNumbers() {
        let lines = DiffParser.parse(DiffFixtures.addedFile)[0].hunks[0].lines
        #expect(lines.allSatisfy { $0.oldLineNumber == nil })
    }

    @Test func diffParser_addedFile_newLineNumbersAreSequential() {
        let lines = DiffParser.parse(DiffFixtures.addedFile)[0].hunks[0].lines
        let newNumbers = lines.compactMap(\.newLineNumber)
        #expect(newNumbers == [1, 2, 3])
    }

    // MARK: Deleted file

    @Test func diffParser_parsesDeletedFile() {
        let results = DiffParser.parse(DiffFixtures.deletedFile)

        #expect(results.count == 1)
        let lines = results[0].hunks[0].lines
        #expect(lines.allSatisfy { $0.type == .deletion })
        #expect(lines.count == 3)
    }

    @Test func diffParser_deletedFile_noNewLineNumbers() {
        let lines = DiffParser.parse(DiffFixtures.deletedFile)[0].hunks[0].lines
        #expect(lines.allSatisfy { $0.newLineNumber == nil })
    }

    // MARK: Renamed file

    @Test func diffParser_parsesRenamedFile() {
        let results = DiffParser.parse(DiffFixtures.renamedFile)

        #expect(results.count == 1)
        let result = results[0]
        #expect(result.filePath == "Sources/App/New.swift")
        #expect(result.oldPath == "Sources/App/Old.swift")
        #expect(result.hunks.isEmpty)
    }

    // MARK: Binary file

    @Test func diffParser_parsesBinaryFile() {
        let results = DiffParser.parse(DiffFixtures.binaryFile)

        #expect(results.count == 1)
        #expect(results[0].isBinary)
        #expect(results[0].hunks.isEmpty)
    }

    // MARK: No newline at end of file

    @Test func diffParser_handlesNoNewlineMarker() {
        // The `\ No newline at end of file` line must be skipped — not treated as a diff line.
        let results = DiffParser.parse(DiffFixtures.noNewlineAtEnd)

        #expect(results.count == 1)
        let lines = results[0].hunks[0].lines
        // Should have: 1 context, 1 deletion, 1 addition — no extra line for the marker
        let additions = lines.filter { $0.type == .addition }
        let deletions = lines.filter { $0.type == .deletion }
        #expect(additions.count == 1)
        #expect(deletions.count == 1)
    }

    // MARK: DiffStats

    @Test func diffParser_calculatesStats_singleHunk() {
        let result = DiffParser.parse(DiffFixtures.singleHunk)[0]

        #expect(result.stats.additions == 2)
        #expect(result.stats.deletions == 1)
    }

    @Test func diffParser_calculatesStats_addedFile() {
        let result = DiffParser.parse(DiffFixtures.addedFile)[0]

        #expect(result.stats.additions == 3)
        #expect(result.stats.deletions == 0)
    }

    @Test func diffParser_calculatesStats_deletedFile() {
        let result = DiffParser.parse(DiffFixtures.deletedFile)[0]

        #expect(result.stats.additions == 0)
        #expect(result.stats.deletions == 3)
    }

    // MARK: Multiple files

    @Test func diffParser_parsesTwoFiles() {
        let results = DiffParser.parse(DiffFixtures.twoFiles)

        #expect(results.count == 2)
        #expect(results[0].filePath == "Sources/App/Alpha.swift")
        #expect(results[1].filePath == "Sources/App/Beta.swift")
    }

    @Test func diffParser_twoFiles_eachHasOneHunk() {
        let results = DiffParser.parse(DiffFixtures.twoFiles)
        #expect(results[0].hunks.count == 1)
        #expect(results[1].hunks.count == 1)
    }

    // MARK: parseSingleFile

    @Test func diffParser_parseSingleFile_returnsFirstResult() {
        let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk)
        #expect(result != nil)
        #expect(result?.filePath == "Sources/App/Foo.swift")
    }

    @Test func diffParser_parseSingleFile_returnsNilForEmpty() {
        let result = DiffParser.parseSingleFile("")
        #expect(result == nil)
    }

    // MARK: buildPatch

    @Test func diffParser_buildPatch_producesValidHeader() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: hunk, filePath: "Sources/App/Foo.swift")

        #expect(patch.hasPrefix("diff --git a/Sources/App/Foo.swift b/Sources/App/Foo.swift\n"))
        #expect(patch.contains("--- a/Sources/App/Foo.swift\n"))
        #expect(patch.contains("+++ b/Sources/App/Foo.swift\n"))
        #expect(patch.contains(hunk.header))
    }

    @Test func diffParser_buildPatch_linesHaveCorrectPrefixes() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let patch = DiffParser.buildPatch(from: hunk, filePath: "Sources/App/Foo.swift")
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
            from: hunk,
            filePath: "Sources/App/Foo.swift",
            oldPath: "Sources/App/OldFoo.swift"
        )

        #expect(patch.contains("a/Sources/App/OldFoo.swift"))
        #expect(patch.contains("b/Sources/App/Foo.swift"))
    }

    // MARK: buildReversePatch

    @Test func diffParser_buildReversePatch_swapsAdditionsAndDeletions() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let forwardPatch = DiffParser.buildPatch(from: hunk, filePath: "Sources/App/Foo.swift")
        let reversePatch = DiffParser.buildReversePatch(from: hunk, filePath: "Sources/App/Foo.swift")

        // Count + and - prefix lines in each patch body (skip the header lines).
        let forwardBody = forwardPatch.components(separatedBy: "\n").dropFirst(4)
        let reverseBody = reversePatch.components(separatedBy: "\n").dropFirst(4)

        let fwdAdditions = forwardBody.filter { $0.hasPrefix("+") }.count
        let fwdDeletions = forwardBody.filter { $0.hasPrefix("-") }.count
        let revAdditions = reverseBody.filter { $0.hasPrefix("+") }.count
        let revDeletions = reverseBody.filter { $0.hasPrefix("-") }.count

        // In the reverse patch, what was added becomes deleted and vice versa.
        #expect(revAdditions == fwdDeletions)
        #expect(revDeletions == fwdAdditions)
    }

    @Test func diffParser_buildReversePatch_headerSwapsOldAndNewRanges() {
        guard let result = DiffParser.parseSingleFile(DiffFixtures.singleHunk),
              let hunk = result.hunks.first else {
            Issue.record("Failed to parse singleHunk fixture")
            return
        }

        let reverse = DiffParser.buildReversePatch(from: hunk, filePath: "Sources/App/Foo.swift")

        // The reverse header should reference newStart/newCount as the old range.
        let expectedHeader = "@@ -\(hunk.newStart),\(hunk.newCount) +\(hunk.oldStart),\(hunk.oldCount) @@"
        #expect(reverse.contains(expectedHeader))
    }

    // MARK: Line content (no leading +/-/space)

    @Test func diffParser_lineContentStripsLeadingCharacter() {
        let result = DiffParser.parse(DiffFixtures.singleHunk)[0]
        let hunk = result.hunks[0]

        for line in hunk.lines {
            // Content must not start with the diff prefix character.
            #expect(!line.content.hasPrefix("+"), "Addition content should not start with '+'")
            #expect(!line.content.hasPrefix("-"), "Deletion content should not start with '-'")
        }
    }
}
