// LogParserTests.swift
// GroveTests
//
// Tests for LogParser — covers single commit, multiple commits, merge
// commits, signed/unsigned, multi-line bodies, and empty input.

import Foundation
import Testing
@testable import Grove

// MARK: - Helpers

/// Builds a minimal log record in the exact format LogParser expects.
/// Fields are NUL-separated; records end with U+0001.
private func makeLogRecord(
    sha: String = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
    summary: String = "fix: some bug",
    body: String = "",
    authorName: String = "Jane Dev",
    authorEmail: String = "jane@example.com",
    authorDate: String = "2024-01-15T12:00:00+00:00",
    committerName: String = "Jane Dev",
    committerEmail: String = "jane@example.com",
    committerDate: String = "2024-01-15T12:00:00+00:00",
    parents: String = "b1c2d3e4f5a6b1c2d3e4f5a6b1c2d3e4f5a6b1c2",
    signatureStatus: String = "N"
) -> String {
    [sha, summary, body, authorName, authorEmail, authorDate,
     committerName, committerEmail, committerDate, parents, signatureStatus, ""]
        .joined(separator: "\0") + "\u{01}"
}

// MARK: - LogParserTests

struct LogParserTests {

    // MARK: Empty input

    @Test func logParser_returnsEmptyForEmptyString() {
        let commits = LogParser.parse("")
        #expect(commits.isEmpty)
    }

    // MARK: Single commit

    @Test func logParser_parsesSingleCommit() {
        let record = makeLogRecord()
        let commits = LogParser.parse(record)

        #expect(commits.count == 1)
    }

    @Test func logParser_singleCommit_sha() {
        let sha = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let commits = LogParser.parse(makeLogRecord(sha: sha))

        #expect(commits[0].id == sha)
    }

    @Test func logParser_singleCommit_shortSHA() {
        let sha = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let commits = LogParser.parse(makeLogRecord(sha: sha))

        #expect(commits[0].shortSHA == "a1b2c3d")
    }

    @Test func logParser_singleCommit_summary() {
        let commits = LogParser.parse(makeLogRecord(summary: "feat: add login screen"))

        #expect(commits[0].summary == "feat: add login screen")
    }

    @Test func logParser_singleCommit_emptyBody_isNil() {
        let commits = LogParser.parse(makeLogRecord(body: ""))

        #expect(commits[0].body == nil)
    }

    @Test func logParser_singleCommit_authorFields() {
        let commits = LogParser.parse(
            makeLogRecord(authorName: "Bob Contributor", authorEmail: "bob@example.com")
        )

        #expect(commits[0].authorName == "Bob Contributor")
        #expect(commits[0].authorEmail == "bob@example.com")
    }

    @Test func logParser_singleCommit_committerFields() {
        let commits = LogParser.parse(
            makeLogRecord(committerName: "CI Bot", committerEmail: "ci@example.com")
        )

        #expect(commits[0].committerName == "CI Bot")
        #expect(commits[0].committerEmail == "ci@example.com")
    }

    @Test func logParser_singleCommit_authorDateParsed() {
        let commits = LogParser.parse(makeLogRecord(authorDate: "2024-06-01T10:30:00+00:00"))

        #expect(commits[0].authorDate != Date(timeIntervalSince1970: 0))
    }

    @Test func logParser_singleCommit_singleParent() {
        let parentSHA = "b1c2d3e4f5a6b1c2d3e4f5a6b1c2d3e4f5a6b1c2"
        let commits = LogParser.parse(makeLogRecord(parents: parentSHA))

        #expect(commits[0].parentIDs == [parentSHA])
        #expect(!commits[0].isMerge)
    }

    // MARK: Multiple commits

    @Test func logParser_parsesMultipleCommits() {
        let sha1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let sha2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let output = makeLogRecord(sha: sha1, summary: "first") +
                     makeLogRecord(sha: sha2, summary: "second")
        let commits = LogParser.parse(output)

        #expect(commits.count == 2)
        #expect(commits[0].summary == "first")
        #expect(commits[1].summary == "second")
    }

    @Test func logParser_multipleCommits_preserveOrder() {
        let shas = [
            "1111111111111111111111111111111111111111",
            "2222222222222222222222222222222222222222",
            "3333333333333333333333333333333333333333"
        ]
        let output = shas.map { makeLogRecord(sha: $0) }.joined()
        let commits = LogParser.parse(output)

        #expect(commits.map(\.id) == shas)
    }

    // MARK: Merge commit

    @Test func logParser_parsesMergeCommit_twoParents() {
        let parent1 = "cccccccccccccccccccccccccccccccccccccccc"
        let parent2 = "dddddddddddddddddddddddddddddddddddddddd"
        let commits = LogParser.parse(
            makeLogRecord(
                summary: "Merge pull request #1",
                parents: "\(parent1) \(parent2)"
            )
        )

        #expect(commits[0].isMerge)
        #expect(commits[0].parentIDs.count == 2)
        #expect(commits[0].parentIDs[0] == parent1)
        #expect(commits[0].parentIDs[1] == parent2)
    }

    // MARK: Root commit (no parents)

    @Test func logParser_parsesRootCommit_emptyParents() {
        let commits = LogParser.parse(makeLogRecord(parents: ""))

        #expect(commits[0].parentIDs.isEmpty)
        #expect(!commits[0].isMerge)
    }

    // MARK: Signed commits

    @Test func logParser_signatureStatus_G_isSigned() {
        let commits = LogParser.parse(makeLogRecord(signatureStatus: "G"))
        #expect(commits[0].isSigned)
    }

    @Test func logParser_signatureStatus_U_isSigned() {
        // U = good signature, unknown validity
        let commits = LogParser.parse(makeLogRecord(signatureStatus: "U"))
        #expect(commits[0].isSigned)
    }

    @Test func logParser_signatureStatus_E_isSigned() {
        // E = cannot check (e.g. missing key) — still treated as signed
        let commits = LogParser.parse(makeLogRecord(signatureStatus: "E"))
        #expect(commits[0].isSigned)
    }

    @Test func logParser_signatureStatus_N_isNotSigned() {
        let commits = LogParser.parse(makeLogRecord(signatureStatus: "N"))
        #expect(!commits[0].isSigned)
    }

    @Test func logParser_signatureStatus_B_isNotSigned() {
        // B = bad signature
        let commits = LogParser.parse(makeLogRecord(signatureStatus: "B"))
        #expect(!commits[0].isSigned)
    }

    // MARK: Multi-line body

    @Test func logParser_parsesMultiLineBody() {
        let body = "This is the first paragraph.\n\nThis is the second paragraph.\nWith multiple lines."
        let commits = LogParser.parse(makeLogRecord(body: body))

        #expect(commits[0].body == body)
    }

    @Test func logParser_multiLineBody_fullMessageIncludesSummaryAndBody() {
        let summary = "feat: add dark mode"
        let body = "Implements system-level dark mode.\n\nAll views updated."
        let commits = LogParser.parse(makeLogRecord(summary: summary, body: body))

        #expect(commits[0].message == "\(summary)\n\n\(body)")
    }

    // MARK: Empty body

    @Test func logParser_emptyBody_fullMessageIsSummaryOnly() {
        let summary = "chore: bump version"
        let commits = LogParser.parse(makeLogRecord(summary: summary, body: ""))

        #expect(commits[0].message == summary)
    }

    // MARK: Invalid / malformed records

    @Test func logParser_skipsRecordWithShortSHA() {
        // Replace the SHA with something too short
        let badRecord = makeLogRecord(sha: "tooshort")
        let commits = LogParser.parse(badRecord)
        #expect(commits.isEmpty)
    }

    @Test func logParser_skipsRecordWithUnparsableDatee() {
        let badDate = "not-a-date"
        let badRecord = makeLogRecord(authorDate: badDate)
        let commits = LogParser.parse(badRecord)
        #expect(commits.isEmpty)
    }

    // MARK: formatString

    @Test func logParser_formatStringContainsAllFields() {
        let fmt = LogParser.formatString
        // Must contain all 11 format placeholders plus the record separator.
        #expect(fmt.contains("%H"))
        #expect(fmt.contains("%s"))
        #expect(fmt.contains("%b"))
        #expect(fmt.contains("%an"))
        #expect(fmt.contains("%ae"))
        #expect(fmt.contains("%aI"))
        #expect(fmt.contains("%cn"))
        #expect(fmt.contains("%ce"))
        #expect(fmt.contains("%cI"))
        #expect(fmt.contains("%P"))
        #expect(fmt.contains("%G?"))
    }
}
