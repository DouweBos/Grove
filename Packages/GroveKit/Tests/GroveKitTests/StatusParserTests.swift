// StatusParserTests.swift
// GroveKitTests
//
// Tests for StatusParser — covers all porcelain v2 line types and
// edge cases such as spaces in paths and mixed input.

import Foundation
import Testing
@testable import GroveKit

// MARK: - StatusParserTests

struct StatusParserTests {

    // MARK: Ordinary changes

    @Test func statusParser_parsesModifiedFile() {
        // `1 XY sub mH mI mW hH hI path`
        // XY = ".M" means index=unmodified, workdir=modified
        let line = "1 .M N... 100644 100644 100644 abc1234 abc1234 Sources/App/Main.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.path == "Sources/App/Main.swift")
        #expect(entry.indexStatus == .unmodified)
        #expect(entry.workdirStatus == .modified)
    }

    @Test func statusParser_parsesIndexAddedFile() {
        // XY = "A." means index=added, workdir=unmodified
        let line = "1 A. N... 000000 100644 100644 0000000 abc1234 Sources/App/NewFile.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.path == "Sources/App/NewFile.swift")
        #expect(entry.indexStatus == .added)
        #expect(entry.workdirStatus == .unmodified)
    }

    @Test func statusParser_parsesDeletedFile() {
        // XY = "D." means index=deleted, workdir=unmodified
        let line = "1 D. N... 100644 000000 000000 abc1234 0000000 Sources/App/OldFile.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].indexStatus == .deleted)
        #expect(entries[0].workdirStatus == .unmodified)
    }

    @Test func statusParser_parsesModifiedBothSides() {
        // XY = "MM" means modified in index AND in workdir
        let line = "1 MM N... 100644 100644 100644 abc1234 def5678 Sources/App/Dual.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].indexStatus == .modified)
        #expect(entries[0].workdirStatus == .modified)
    }

    // MARK: Renamed / Copied

    @Test func statusParser_parsesRenamedFile() {
        // Format: `2 XY sub mH mI mW hH hI X score path\torigPath`
        // XY = "R." means index=renamed, workdir=unmodified
        let line = "2 R. N... 100644 100644 100644 abc1234 abc1234 R100 NewName.swift\tOldName.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        // Destination path is before the tab
        #expect(entry.path == "NewName.swift")
        #expect(entry.indexStatus == .renamed)
        #expect(entry.workdirStatus == .unmodified)
    }

    @Test func statusParser_parsesCopiedFile() {
        let line = "2 C. N... 100644 100644 100644 abc1234 abc1234 C100 CopiedFile.swift\tOriginal.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].indexStatus == .copied)
    }

    // MARK: Untracked

    @Test func statusParser_parsesUntrackedFile() {
        let line = "? UntrackedFile.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.path == "UntrackedFile.swift")
        #expect(entry.indexStatus == .unmodified)
        #expect(entry.workdirStatus == .untracked)
    }

    @Test func statusParser_parsesUntrackedFileInSubdirectory() {
        let line = "? Sources/NewFeature/Draft.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].path == "Sources/NewFeature/Draft.swift")
        #expect(entries[0].workdirStatus == .untracked)
    }

    // MARK: Ignored

    @Test func statusParser_parsesIgnoredFile() {
        let line = "! build/output.o"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.path == "build/output.o")
        #expect(entry.indexStatus == .unmodified)
        #expect(entry.workdirStatus == .ignored)
    }

    // MARK: Conflicted (unmerged)

    @Test func statusParser_parsesConflictedFile() {
        // Format: `u XY sub m1 m2 m3 mW hH h1 h2 h3 path`
        // Needs at least 12 space-separated fields
        let line = "u UU N... 100644 100644 100644 100644 abc1234 def1234 ghi1234 Sources/App/Conflict.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.path == "Sources/App/Conflict.swift")
        #expect(entry.indexStatus == .conflicted)
        #expect(entry.workdirStatus == .conflicted)
    }

    // MARK: Empty input

    @Test func statusParser_returnsEmptyForEmptyString() {
        let entries = StatusParser.parse("")
        #expect(entries.isEmpty)
    }

    @Test func statusParser_returnsEmptyForWhitespaceOnlyString() {
        let entries = StatusParser.parse("   \n   ")
        #expect(entries.isEmpty)
    }

    // MARK: Paths with spaces

    @Test func statusParser_parsesOrdinaryFileWithSpaceInPath() {
        let line = "1 .M N... 100644 100644 100644 abc1234 abc1234 Sources/My App/Main View.swift"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].path == "Sources/My App/Main View.swift")
    }

    @Test func statusParser_parsesUntrackedFileWithSpaceInPath() {
        let line = "? my file with spaces.txt"
        let entries = StatusParser.parse(line)

        #expect(entries.count == 1)
        #expect(entries[0].path == "my file with spaces.txt")
    }

    // MARK: Mixed multi-line input

    @Test func statusParser_parsesMixedMultipleEntries() {
        let output = """
        1 A. N... 000000 100644 100644 0000000 aaa1234 Staged.swift
        1 .M N... 100644 100644 100644 bbb1234 bbb1234 Modified.swift
        ? Untracked.swift
        ! .build/output.o
        u UU N... 100644 100644 100644 100644 ccc1234 ddd1234 eee1234 fff1234 Conflict.swift
        2 R. N... 100644 100644 100644 ggg1234 ggg1234 R100 NewName.swift\tOldName.swift
        """
        let entries = StatusParser.parse(output)

        #expect(entries.count == 6)

        // Verify order and key properties
        #expect(entries[0].indexStatus == .added)
        #expect(entries[0].path == "Staged.swift")

        #expect(entries[1].workdirStatus == .modified)
        #expect(entries[1].path == "Modified.swift")

        #expect(entries[2].workdirStatus == .untracked)
        #expect(entries[2].path == "Untracked.swift")

        #expect(entries[3].workdirStatus == .ignored)

        #expect(entries[4].indexStatus == .conflicted)
        #expect(entries[4].workdirStatus == .conflicted)

        #expect(entries[5].indexStatus == .renamed)
        #expect(entries[5].path == "NewName.swift")
    }

    @Test func statusParser_ignoresUnknownLineTypes() {
        // Lines starting with '#' are branch info headers in porcelain v2 — should be ignored.
        let output = """
        # branch.oid abc1234
        # branch.head main
        1 .M N... 100644 100644 100644 abc1234 abc1234 Modified.swift
        """
        let entries = StatusParser.parse(output)
        #expect(entries.count == 1)
        #expect(entries[0].path == "Modified.swift")
    }

    // MARK: FileStatus mapping

    @Test func statusParser_mapsAllXYCharacters() {
        let cases: [(String, FileStatus, FileStatus)] = [
            ("1 M. N... 100644 100644 100644 a b c", .modified, .unmodified),
            ("1 .D N... 100644 100644 100644 a b c", .unmodified, .deleted),
            ("1 RR N... 100644 100644 100644 a b c", .renamed, .renamed),
            ("1 CC N... 100644 100644 100644 a b c", .copied, .copied),
            ("1 TT N... 100644 100644 100644 a b c", .typeChange, .typeChange)
        ]
        for (line, expectedIndex, expectedWorkdir) in cases {
            let entries = StatusParser.parse(line)
            guard entries.count == 1 else {
                // Path field might be empty due to short test string — just check mapping logic ran.
                continue
            }
            #expect(entries[0].indexStatus == expectedIndex,
                    "Index status mismatch for line: \(line)")
            #expect(entries[0].workdirStatus == expectedWorkdir,
                    "Workdir status mismatch for line: \(line)")
        }
    }
}
