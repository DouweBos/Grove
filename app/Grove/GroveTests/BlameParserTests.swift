// BlameParserTests.swift
// GroveTests
//
// Tests for BlameParser — covers single block, multiple blocks from
// different commits, consecutive blocks from the same commit (merging),
// and empty input.

import Foundation
import Testing
@testable import Grove

// MARK: - Fixtures

private enum BlameFixtures {

    /// A valid 40-character hex SHA used across tests.
    static let sha1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let sha2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    /// Minimal porcelain blame block for one line at line 1, from sha1.
    static let singleLine = """
    \(sha1) 1 1 1
    author Alice
    author-mail <alice@example.com>
    author-time 1700000000
    author-tz +0000
    committer Alice
    committer-mail <alice@example.com>
    committer-time 1700000000
    committer-tz +0000
    summary Initial commit
    filename Sources/App/Main.swift
    \tlet x = 1
    """

    /// Two consecutive lines both from sha1, then one line from sha2.
    static let threeLines = """
    \(sha1) 1 1 1
    author Alice
    author-mail <alice@example.com>
    author-time 1700000000
    author-tz +0000
    committer Alice
    committer-mail <alice@example.com>
    committer-time 1700000000
    committer-tz +0000
    summary First commit
    filename Sources/App/Main.swift
    \tlet x = 1
    \(sha1) 2 2 1
    author Alice
    author-mail <alice@example.com>
    author-time 1700000000
    author-tz +0000
    committer Alice
    committer-mail <alice@example.com>
    committer-time 1700000000
    committer-tz +0000
    summary First commit
    filename Sources/App/Main.swift
    \tlet y = 2
    \(sha2) 3 3 1
    author Bob
    author-mail <bob@example.com>
    author-time 1700100000
    author-tz +0000
    committer Bob
    committer-mail <bob@example.com>
    committer-time 1700100000
    committer-tz +0000
    summary Second commit
    filename Sources/App/Main.swift
    \tlet z = 3
    """

    /// Two consecutive blocks with the same SHA (should collapse into one entry).
    static let sameCommitTwoBlocks = """
    \(sha1) 1 1 3
    author Alice
    author-mail <alice@example.com>
    author-time 1700000000
    author-tz +0000
    committer Alice
    committer-mail <alice@example.com>
    committer-time 1700000000
    committer-tz +0000
    summary First commit
    filename Sources/App/Main.swift
    \tline one
    \(sha1) 4 4 2
    author Alice
    author-mail <alice@example.com>
    author-time 1700000000
    author-tz +0000
    committer Alice
    committer-mail <alice@example.com>
    committer-time 1700000000
    committer-tz +0000
    summary First commit
    filename Sources/App/Main.swift
    \tline four
    """
}

// MARK: - BlameParserTests

struct BlameParserTests {

    // MARK: Empty input

    @Test func blameParser_returnsEmptyForEmptyString() {
        let entries = BlameParser.parse("")
        #expect(entries.isEmpty)
    }

    // MARK: Single block

    @Test func blameParser_parsesSingleBlock() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)

        #expect(entries.count == 1)
    }

    @Test func blameParser_singleBlock_commitSHA() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].commitSHA == BlameFixtures.sha1)
    }

    @Test func blameParser_singleBlock_lineStart() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].lineStart == 1)
    }

    @Test func blameParser_singleBlock_lineCount() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].lineCount == 1)
    }

    @Test func blameParser_singleBlock_authorName() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].authorName == "Alice")
    }

    @Test func blameParser_singleBlock_authorEmail() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].authorEmail == "alice@example.com")
    }

    @Test func blameParser_singleBlock_authorDate() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        // Timestamp 1700000000 should parse to a non-epoch date.
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(entries[0].authorDate == expectedDate)
    }

    @Test func blameParser_singleBlock_summary() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].summary == "Initial commit")
    }

    @Test func blameParser_singleBlock_stableID() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        // ID is formed as "<sha>-<lineStart>".
        #expect(entries[0].id == "\(BlameFixtures.sha1)-1")
    }

    // MARK: Multiple blocks from different commits

    @Test func blameParser_parsesThreeLinesMixedCommits_producesCorrectBlockCount() {
        // Lines 1-2 are from sha1, line 3 is from sha2.
        // Since the two sha1 blocks are consecutive, they should collapse into one.
        let entries = BlameParser.parse(BlameFixtures.threeLines)
        // After collapsing: one sha1 block + one sha2 block = 2 entries
        #expect(entries.count == 2)
    }

    @Test func blameParser_mixedCommits_firstEntryIsSha1() {
        let entries = BlameParser.parse(BlameFixtures.threeLines)
        #expect(entries[0].commitSHA == BlameFixtures.sha1)
    }

    @Test func blameParser_mixedCommits_secondEntryIsSha2() {
        let entries = BlameParser.parse(BlameFixtures.threeLines)
        #expect(entries[1].commitSHA == BlameFixtures.sha2)
    }

    @Test func blameParser_mixedCommits_collapsedSha1BlockLineCount() {
        let entries = BlameParser.parse(BlameFixtures.threeLines)
        // The two sha1 raw entries each cover 1 line → collapsed count = 2
        #expect(entries[0].lineCount == 2)
    }

    @Test func blameParser_mixedCommits_sha2BlockLineCount() {
        let entries = BlameParser.parse(BlameFixtures.threeLines)
        #expect(entries[1].lineCount == 1)
    }

    // MARK: Consecutive blocks from same commit (should merge)

    @Test func blameParser_consecutiveSameCommitBlocks_mergedIntoOne() {
        // Two separate raw blocks, both from sha1.
        let entries = BlameParser.parse(BlameFixtures.sameCommitTwoBlocks)
        #expect(entries.count == 1)
    }

    @Test func blameParser_consecutiveSameCommitBlocks_mergedLineCount() {
        let entries = BlameParser.parse(BlameFixtures.sameCommitTwoBlocks)
        // Block 1 has numLines=3, block 2 has numLines=2 → collapsed = 5
        #expect(entries[0].lineCount == 5)
    }

    @Test func blameParser_consecutiveSameCommitBlocks_lineStartIsFirst() {
        let entries = BlameParser.parse(BlameFixtures.sameCommitTwoBlocks)
        #expect(entries[0].lineStart == 1)
    }

    // MARK: Original path (rename tracking)

    @Test func blameParser_filenameFieldSetAsOriginalPath() {
        let entries = BlameParser.parse(BlameFixtures.singleLine)
        #expect(entries[0].originalPath == "Sources/App/Main.swift")
    }
}
