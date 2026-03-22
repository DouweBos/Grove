// StashParserTests.swift
// GroveTests
//
// Tests for StashParser — covers single stash, multiple stashes,
// "WIP on" format, "On" format, branch name extraction, and empty input.

import Foundation
import Testing
@testable import Grove

// MARK: - Helpers

/// Build one stash line in the format StashParser expects.
/// Fields are NUL-separated; format = %gd %x00 %H %x00 %gs %x00 %aI
private func makeStashLine(
    descriptor: String = "stash@{0}",
    sha: String = "aabbccddeeff00112233445566778899aabbccdd",
    message: String = "WIP on main: abc1234 Some commit",
    date: String = "2024-03-01T10:00:00+00:00"
) -> String {
    [descriptor, sha, message, date].joined(separator: "\0")
}

// MARK: - StashParserTests

struct StashParserTests {

    // MARK: Empty input

    @Test func stashParser_returnsEmptyForEmptyString() {
        let entries = StashParser.parse("")
        #expect(entries.isEmpty)
    }

    // MARK: Single stash — WIP on format

    @Test func stashParser_parsesSingleStash() {
        let line = makeStashLine()
        let entries = StashParser.parse(line)

        #expect(entries.count == 1)
    }

    @Test func stashParser_singleStash_index() {
        let entries = StashParser.parse(makeStashLine(descriptor: "stash@{0}"))
        #expect(entries[0].id == 0)
    }

    @Test func stashParser_singleStash_sha() {
        let sha = "aabbccddeeff00112233445566778899aabbccdd"
        let entries = StashParser.parse(makeStashLine(sha: sha))
        #expect(entries[0].sha == sha)
    }

    @Test func stashParser_singleStash_message() {
        let message = "WIP on main: abc1234 Some commit"
        let entries = StashParser.parse(makeStashLine(message: message))
        #expect(entries[0].message == message)
    }

    @Test func stashParser_singleStash_dateParsed() {
        let entries = StashParser.parse(makeStashLine(date: "2024-03-01T10:00:00+00:00"))
        // Date should not be the epoch zero placeholder.
        #expect(entries[0].date != Date(timeIntervalSince1970: 0))
    }

    // MARK: WIP on branch format

    @Test func stashParser_wipOnFormat_extractsBranchName() {
        let entries = StashParser.parse(
            makeStashLine(message: "WIP on feature/auth: abc1234 Add login flow")
        )
        #expect(entries[0].branchName == "feature/auth")
    }

    @Test func stashParser_wipOnFormat_mainBranch() {
        let entries = StashParser.parse(
            makeStashLine(message: "WIP on main: abc1234 Some work")
        )
        #expect(entries[0].branchName == "main")
    }

    // MARK: On branch format

    @Test func stashParser_onFormat_extractsBranchName() {
        let entries = StashParser.parse(
            makeStashLine(message: "On develop: experimental layout refactor")
        )
        #expect(entries[0].branchName == "develop")
    }

    @Test func stashParser_onFormat_branchWithSlash() {
        let entries = StashParser.parse(
            makeStashLine(message: "On feature/dark-mode: tweaks")
        )
        #expect(entries[0].branchName == "feature/dark-mode")
    }

    // MARK: Custom message (no recognised prefix)

    @Test func stashParser_customMessage_branchNameIsNil() {
        let entries = StashParser.parse(
            makeStashLine(message: "My custom stash message")
        )
        #expect(entries[0].branchName == nil)
    }

    // MARK: Multiple stashes

    @Test func stashParser_parsesMultipleStashes() {
        let output = [
            makeStashLine(descriptor: "stash@{0}", message: "WIP on main: first"),
            makeStashLine(descriptor: "stash@{1}", message: "WIP on develop: second"),
            makeStashLine(descriptor: "stash@{2}", message: "On feature/x: third")
        ].joined(separator: "\n")

        let entries = StashParser.parse(output)

        #expect(entries.count == 3)
    }

    @Test func stashParser_multipleStashes_indicesAreCorrect() {
        let output = [
            makeStashLine(descriptor: "stash@{0}"),
            makeStashLine(descriptor: "stash@{1}"),
            makeStashLine(descriptor: "stash@{2}")
        ].joined(separator: "\n")

        let entries = StashParser.parse(output)
        #expect(entries[0].id == 0)
        #expect(entries[1].id == 1)
        #expect(entries[2].id == 2)
    }

    @Test func stashParser_multipleStashes_messagesPreserved() {
        let messages = [
            "WIP on main: first work",
            "On develop: layout experiments",
            "My custom stash"
        ]
        let output = zip(messages, 0...).map { message, idx in
            makeStashLine(descriptor: "stash@{\(idx)}", message: message)
        }.joined(separator: "\n")

        let entries = StashParser.parse(output)
        #expect(entries.map(\.message) == messages)
    }

    // MARK: formatString

    @Test func stashParser_formatStringContainsAllFields() {
        let fmt = StashParser.formatString
        #expect(fmt.contains("%gd"))
        #expect(fmt.contains("%H"))
        #expect(fmt.contains("%gs"))
        #expect(fmt.contains("%aI"))
    }

    // MARK: Malformed input

    @Test func stashParser_skipsLineWithTooFewFields() {
        // Only three NUL-separated fields instead of four.
        let bad = "stash@{0}\0someSHA\0WIP on main: msg"
        let entries = StashParser.parse(bad)
        #expect(entries.isEmpty)
    }

    @Test func stashParser_skipsLineWithBadDescriptor() {
        // Descriptor without braces.
        let line = makeStashLine(descriptor: "stash_no_braces")
        let entries = StashParser.parse(line)
        #expect(entries.isEmpty)
    }

    @Test func stashParser_skipsLineWithBadDate() {
        let line = makeStashLine(date: "not-a-date")
        let entries = StashParser.parse(line)
        #expect(entries.isEmpty)
    }
}
