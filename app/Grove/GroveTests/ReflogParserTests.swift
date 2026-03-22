// ReflogParserTests.swift
// GroveTests
//
// Tests for ReflogParser — covers single entry, multiple entries,
// root commit (no parent), and empty input.

import Foundation
import Testing
@testable import Grove

// MARK: - Helpers

/// Builds one reflog record in the format ReflogParser expects.
/// Fields are NUL-separated; records end with U+0001.
private func makeReflogRecord(
    newSHA: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    parentSHA: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    message: String = "commit: feat: add feature",
    committerName: String = "Jane Dev",
    committerEmail: String = "jane@example.com",
    date: String = "2024-05-10T08:00:00+00:00"
) -> String {
    [newSHA, parentSHA, message, committerName, committerEmail, date, ""]
        .joined(separator: "\0") + "\u{01}"
}

// MARK: - ReflogParserTests

struct ReflogParserTests {

    // MARK: Empty input

    @Test func reflogParser_returnsEmptyForEmptyString() {
        let entries = ReflogParser.parse("")
        #expect(entries.isEmpty)
    }

    // MARK: Single entry

    @Test func reflogParser_parsesSingleEntry() {
        let record = makeReflogRecord()
        let entries = ReflogParser.parse(record)

        #expect(entries.count == 1)
    }

    @Test func reflogParser_singleEntry_newSHA() {
        let sha = "cccccccccccccccccccccccccccccccccccccccc"
        let entries = ReflogParser.parse(makeReflogRecord(newSHA: sha))
        #expect(entries[0].newSHA == sha)
    }

    @Test func reflogParser_singleEntry_oldSHAFromParent() {
        let parent = "dddddddddddddddddddddddddddddddddddddddd"
        let entries = ReflogParser.parse(makeReflogRecord(parentSHA: parent))
        #expect(entries[0].oldSHA == parent)
    }

    @Test func reflogParser_singleEntry_message() {
        let entries = ReflogParser.parse(makeReflogRecord(message: "checkout: moving from main to develop"))
        #expect(entries[0].message == "checkout: moving from main to develop")
    }

    @Test func reflogParser_singleEntry_committerName() {
        let entries = ReflogParser.parse(makeReflogRecord(committerName: "Bob Contributor"))
        #expect(entries[0].committerName == "Bob Contributor")
    }

    @Test func reflogParser_singleEntry_committerEmail() {
        let entries = ReflogParser.parse(makeReflogRecord(committerEmail: "bob@example.com"))
        #expect(entries[0].committerEmail == "bob@example.com")
    }

    @Test func reflogParser_singleEntry_dateParsed() {
        let entries = ReflogParser.parse(makeReflogRecord(date: "2024-05-10T08:00:00+00:00"))
        #expect(entries[0].date != Date(timeIntervalSince1970: 0))
    }

    @Test func reflogParser_singleEntry_idIsNotEmpty() {
        let entries = ReflogParser.parse(makeReflogRecord())
        #expect(!entries[0].id.isEmpty)
    }

    // MARK: Root commit (no parent SHA)

    @Test func reflogParser_rootCommit_emptyParentFallsBackToZeroSHA() {
        let entries = ReflogParser.parse(makeReflogRecord(parentSHA: ""))
        // When parent is empty, oldSHA should be the 40-character zero placeholder.
        #expect(entries[0].oldSHA == String(repeating: "0", count: 40))
    }

    // MARK: Multiple entries

    @Test func reflogParser_parsesMultipleEntries() {
        let sha1 = "1111111111111111111111111111111111111111"
        let sha2 = "2222222222222222222222222222222222222222"
        let sha3 = "3333333333333333333333333333333333333333"

        let output = makeReflogRecord(newSHA: sha1, message: "first") +
                     makeReflogRecord(newSHA: sha2, message: "second") +
                     makeReflogRecord(newSHA: sha3, message: "third")

        let entries = ReflogParser.parse(output)

        #expect(entries.count == 3)
    }

    @Test func reflogParser_multipleEntries_preserveOrder() {
        let shas = [
            "aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111",
            "bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222",
            "cccc3333cccc3333cccc3333cccc3333cccc3333"
        ]
        let output = shas.map { makeReflogRecord(newSHA: $0) }.joined()
        let entries = ReflogParser.parse(output)

        #expect(entries.map(\.newSHA) == shas)
    }

    @Test func reflogParser_multipleEntries_messagesPreserved() {
        let messages = [
            "commit: feat: new feature",
            "pull: Fast-forward",
            "rebase (finish): returning to refs/heads/main"
        ]
        let output = messages.map { makeReflogRecord(message: $0) }.joined()
        let entries = ReflogParser.parse(output)

        #expect(entries.map(\.message) == messages)
    }

    // MARK: formatString

    @Test func reflogParser_formatStringContainsAllPlaceholders() {
        let fmt = ReflogParser.formatString
        #expect(fmt.contains("%H"))
        #expect(fmt.contains("%P"))
        #expect(fmt.contains("%gs"))
        #expect(fmt.contains("%an"))
        #expect(fmt.contains("%ae"))
        #expect(fmt.contains("%aI"))
    }

    // MARK: Malformed records

    @Test func reflogParser_skipsRecordWithShortSHA() {
        let bad = makeReflogRecord(newSHA: "short")
        let entries = ReflogParser.parse(bad)
        #expect(entries.isEmpty)
    }

    @Test func reflogParser_skipsRecordWithBadDate() {
        let bad = makeReflogRecord(date: "not-a-valid-date")
        let entries = ReflogParser.parse(bad)
        #expect(entries.isEmpty)
    }
}
