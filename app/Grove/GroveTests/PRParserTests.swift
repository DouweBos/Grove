// PRParserTests.swift
// GroveTests
//
// Tests for PRParser — covers parseList, parseSingle, parseComments, state
// mapping, optional field defaults, labels, reviewers, checks status, and
// author extraction.

import Foundation
import Testing
@testable import Grove

// MARK: - Fixtures

private enum PRFixtures {

    // MARK: Core helpers

    /// A minimal valid PR object with only the required fields.
    static let minimal = """
    {
        "number": 1,
        "title": "Minimal PR"
    }
    """

    // MARK: parseList fixtures

    static let emptyArray = "[]"

    static let nonArrayJSON = "{}"

    static let malformedJSON = "{ this is not json }"

    static let missingNumber = """
    [{"title": "No number here"}]
    """

    static let missingTitle = """
    [{"number": 42}]
    """

    static let singlePR = """
    [
        {
            "number": 7,
            "title": "Add dark mode",
            "body": "Implements dark mode support.",
            "state": "OPEN",
            "headRefName": "feature/dark-mode",
            "baseRefName": "main",
            "createdAt": "2025-01-10T09:00:00Z",
            "updatedAt": "2025-01-11T12:30:00Z",
            "isDraft": false,
            "author": {"login": "alice"},
            "labels": [],
            "reviewRequests": [],
            "statusCheckRollup": []
        }
    ]
    """

    static let multiplePRs = """
    [
        {
            "number": 1,
            "title": "First PR",
            "state": "OPEN",
            "createdAt": "2025-02-01T08:00:00Z",
            "updatedAt": "2025-02-01T08:00:00Z"
        },
        {
            "number": 2,
            "title": "Second PR",
            "state": "OPEN",
            "createdAt": "2025-02-02T08:00:00Z",
            "updatedAt": "2025-02-02T08:00:00Z"
        },
        {
            "number": 3,
            "title": "Third PR",
            "state": "OPEN",
            "createdAt": "2025-02-03T08:00:00Z",
            "updatedAt": "2025-02-03T08:00:00Z"
        }
    ]
    """

    // MARK: parseSingle fixtures

    static let singleObject = """
    {
        "number": 42,
        "title": "Fix login crash",
        "body": "Fixes a crash that occurs during login.",
        "state": "OPEN",
        "headRefName": "bugfix/login-crash",
        "baseRefName": "main",
        "createdAt": "2025-03-05T14:00:00Z",
        "updatedAt": "2025-03-06T10:15:00Z",
        "isDraft": false,
        "author": {"login": "bob"},
        "labels": [],
        "reviewRequests": [],
        "statusCheckRollup": []
    }
    """

    static let nonObjectJSON = "[]"

    static let singleMissingNumber = """
    {"title": "No number"}
    """

    static let singleMissingTitle = """
    {"number": 99}
    """

    // MARK: State fixtures

    static let stateOpen = """
    {"number": 10, "title": "Open PR", "state": "OPEN"}
    """

    static let stateClosed = """
    {"number": 11, "title": "Closed PR", "state": "closed"}
    """

    static let stateMerged = """
    {"number": 12, "title": "Merged PR", "state": "MERGED"}
    """

    static let stateUnknown = """
    {"number": 13, "title": "Unknown state PR", "state": "UNKNOWN_VALUE"}
    """

    static let stateMissing = """
    {"number": 14, "title": "No state field PR"}
    """

    // MARK: isDraft fixtures

    static let isDraftTrue = """
    {"number": 20, "title": "Draft PR", "isDraft": true}
    """

    static let isDraftFalse = """
    {"number": 21, "title": "Ready PR", "isDraft": false}
    """

    static let isDraftMissing = """
    {"number": 22, "title": "No draft field PR"}
    """

    // MARK: Optional field defaults

    static let missingBody = """
    {"number": 30, "title": "No body"}
    """

    static let missingBranches = """
    {"number": 31, "title": "No branches"}
    """

    // MARK: Labels

    static let labelsPresent = """
    {
        "number": 40,
        "title": "Labelled PR",
        "labels": [
            {"name": "bug", "color": "d73a4a"},
            {"name": "enhancement", "color": "0075ca"}
        ]
    }
    """

    static let labelsMissing = """
    {"number": 41, "title": "No labels key"}
    """

    static let labelWithoutName = """
    {
        "number": 42,
        "title": "Bad label PR",
        "labels": [
            {"color": "ff0000"},
            {"name": "valid", "color": "00ff00"}
        ]
    }
    """

    // MARK: Reviewers

    static let reviewersPresent = """
    {
        "number": 50,
        "title": "Reviewer PR",
        "reviewRequests": [
            {"login": "charlie"},
            {"login": "diana"}
        ]
    }
    """

    static let reviewersMissing = """
    {"number": 51, "title": "No reviewer key"}
    """

    // MARK: Checks status

    static let checksAllSuccess = """
    {
        "number": 60,
        "title": "All passing PR",
        "statusCheckRollup": [
            {"conclusion": "SUCCESS"},
            {"conclusion": "success"}
        ]
    }
    """

    static let checksContainsFailure = """
    {
        "number": 61,
        "title": "Failing PR",
        "statusCheckRollup": [
            {"conclusion": "SUCCESS"},
            {"conclusion": "failure"}
        ]
    }
    """

    static let checksContainsPendingConclusion = """
    {
        "number": 62,
        "title": "Pending conclusion PR",
        "statusCheckRollup": [
            {"conclusion": "SUCCESS"},
            {"conclusion": "pending"}
        ]
    }
    """

    static let checksNoConclusionsPendingState = """
    {
        "number": 63,
        "title": "Pending state PR",
        "statusCheckRollup": [
            {"state": "PENDING"},
            {"state": "in_progress"}
        ]
    }
    """

    static let checksNoRollupKey = """
    {"number": 64, "title": "No checks PR"}
    """

    static let checksNoConclusionsNoStates = """
    {
        "number": 65,
        "title": "Empty rollup PR",
        "statusCheckRollup": []
    }
    """

    static let checksNoConclusionsPassingStates = """
    {
        "number": 66,
        "title": "Non-pending state PR",
        "statusCheckRollup": [
            {"state": "COMPLETED"}
        ]
    }
    """

    static let checksContainsError = """
    {
        "number": 67,
        "title": "Error check PR",
        "statusCheckRollup": [
            {"conclusion": "error"}
        ]
    }
    """

    // MARK: Author extraction

    static let authorWithLogin = """
    {
        "number": 70,
        "title": "Login author PR",
        "author": {"login": "eve"}
    }
    """

    static let authorWithNameOnly = """
    {
        "number": 71,
        "title": "Name-only author PR",
        "author": {"name": "Frank Furter"}
    }
    """

    static let authorMissing = """
    {"number": 72, "title": "No author PR"}
    """

    // MARK: parseComments fixtures

    static let commentsAndReviewsEmpty = """
    {"comments": [], "reviews": []}
    """

    static let commentsMissingBothKeys = """
    {"number": 1, "title": "just a pr"}
    """

    static let commentsOnlyPlain = """
    {
        "comments": [
            {
                "author": {"login": "alice"},
                "body": "Looks good to me!",
                "createdAt": "2025-04-01T10:00:00Z"
            },
            {
                "author": {"login": "bob"},
                "body": "Please add tests.",
                "createdAt": "2025-04-01T11:00:00Z"
            }
        ],
        "reviews": []
    }
    """

    static let reviewsOnly = """
    {
        "comments": [],
        "reviews": [
            {
                "author": {"login": "charlie"},
                "body": "Approved!",
                "submittedAt": "2025-04-02T09:00:00Z"
            }
        ]
    }
    """

    static let reviewWithEmptyBody = """
    {
        "comments": [],
        "reviews": [
            {
                "author": {"login": "diana"},
                "body": "",
                "submittedAt": "2025-04-03T08:00:00Z"
            },
            {
                "author": {"login": "eve"},
                "body": "Changes requested.",
                "submittedAt": "2025-04-03T09:00:00Z"
            }
        ]
    }
    """

    static let mixedChronological = """
    {
        "comments": [
            {
                "author": {"login": "alice"},
                "body": "First comment",
                "createdAt": "2025-05-01T08:00:00Z"
            },
            {
                "author": {"login": "bob"},
                "body": "Third comment",
                "createdAt": "2025-05-01T10:00:00Z"
            }
        ],
        "reviews": [
            {
                "author": {"login": "charlie"},
                "body": "Second review",
                "submittedAt": "2025-05-01T09:00:00Z"
            }
        ]
    }
    """
}

// MARK: - PRParserTests

struct PRParserTests {

    // MARK: parseList — empty

    @Test func prParser_parseList_emptyArrayReturnsEmpty() throws {
        let result = try PRParser.parseList(PRFixtures.emptyArray)
        #expect(result.isEmpty)
    }

    // MARK: parseList — single

    @Test func prParser_parseList_singlePRParsedCorrectly() throws {
        let result = try PRParser.parseList(PRFixtures.singlePR)

        #expect(result.count == 1)
        let pr = result[0]
        #expect(pr.id == 7)
        #expect(pr.title == "Add dark mode")
        #expect(pr.body == "Implements dark mode support.")
        #expect(pr.sourceBranch == "feature/dark-mode")
        #expect(pr.targetBranch == "main")
        #expect(pr.isDraft == false)
        #expect(pr.authorName == "alice")
    }

    // MARK: parseList — multiple

    @Test func prParser_parseList_multiplePRsReturnsCorrectCount() throws {
        let result = try PRParser.parseList(PRFixtures.multiplePRs)
        #expect(result.count == 3)
    }

    // MARK: parseList — error cases

    @Test func prParser_parseList_nonArrayJSONThrowsInvalidJSON() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseList(PRFixtures.nonArrayJSON)
        }
    }

    @Test func prParser_parseList_malformedJSONThrowsInvalidJSON() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseList(PRFixtures.malformedJSON)
        }
    }

    @Test func prParser_parseList_missingNumberThrowsMissingField() throws {
        #expect(throws: PRParserError.self) {
            try PRParser.parseList(PRFixtures.missingNumber)
        }
    }

    @Test func prParser_parseList_missingTitleThrowsMissingField() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseList(PRFixtures.missingTitle)
        }
    }

    // MARK: parseSingle — complete

    @Test func prParser_parseSingle_completePRAllFieldsPresent() throws {
        let pr = try PRParser.parseSingle(PRFixtures.singleObject)

        #expect(pr.id == 42)
        #expect(pr.title == "Fix login crash")
        #expect(pr.body == "Fixes a crash that occurs during login.")
        #expect(pr.sourceBranch == "bugfix/login-crash")
        #expect(pr.targetBranch == "main")
        #expect(pr.isDraft == false)
        #expect(pr.authorName == "bob")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expectedCreated = formatter.date(from: "2025-03-05T14:00:00Z")!
        let expectedUpdated = formatter.date(from: "2025-03-06T10:15:00Z")!
        #expect(pr.createdDate == expectedCreated)
        #expect(pr.updatedDate == expectedUpdated)
    }

    // MARK: parseSingle — error cases

    @Test func prParser_parseSingle_nonObjectJSONThrowsInvalidJSON() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseSingle(PRFixtures.nonObjectJSON)
        }
    }

    @Test func prParser_parseSingle_missingNumberThrowsMissingField() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseSingle(PRFixtures.singleMissingNumber)
        }
    }

    @Test func prParser_parseSingle_missingTitleThrowsMissingField() {
        #expect(throws: PRParserError.self) {
            try PRParser.parseSingle(PRFixtures.singleMissingTitle)
        }
    }

    // MARK: State mapping

    @Test func prParser_state_openUppercasedMapsToOpen() throws {
        let pr = try PRParser.parseSingle(PRFixtures.stateOpen)
        #expect(pr.state == .open)
    }

    @Test func prParser_state_closedLowercasedMapsToClosed() throws {
        let pr = try PRParser.parseSingle(PRFixtures.stateClosed)
        #expect(pr.state == .closed)
    }

    @Test func prParser_state_mergedUppercasedMapsToMerged() throws {
        let pr = try PRParser.parseSingle(PRFixtures.stateMerged)
        #expect(pr.state == .merged)
    }

    @Test func prParser_state_unknownStringDefaultsToOpen() throws {
        let pr = try PRParser.parseSingle(PRFixtures.stateUnknown)
        #expect(pr.state == .open)
    }

    @Test func prParser_state_missingFieldDefaultsToOpen() throws {
        let pr = try PRParser.parseSingle(PRFixtures.stateMissing)
        #expect(pr.state == .open)
    }

    // MARK: isDraft

    @Test func prParser_isDraft_trueValueParsedCorrectly() throws {
        let pr = try PRParser.parseSingle(PRFixtures.isDraftTrue)
        #expect(pr.isDraft == true)
    }

    @Test func prParser_isDraft_falseValueParsedCorrectly() throws {
        let pr = try PRParser.parseSingle(PRFixtures.isDraftFalse)
        #expect(pr.isDraft == false)
    }

    @Test func prParser_isDraft_missingFieldDefaultsFalse() throws {
        let pr = try PRParser.parseSingle(PRFixtures.isDraftMissing)
        #expect(pr.isDraft == false)
    }

    // MARK: Optional field defaults

    @Test func prParser_body_missingFieldIsNil() throws {
        let pr = try PRParser.parseSingle(PRFixtures.missingBody)
        #expect(pr.body == nil)
    }

    @Test func prParser_branches_missingFieldsDefaultToEmptyString() throws {
        let pr = try PRParser.parseSingle(PRFixtures.missingBranches)
        #expect(pr.sourceBranch == "")
        #expect(pr.targetBranch == "")
    }

    // MARK: Labels

    @Test func prParser_labels_parsedWithNameAndColor() throws {
        let pr = try PRParser.parseSingle(PRFixtures.labelsPresent)

        #expect(pr.labels.count == 2)
        let bug = pr.labels.first(where: { $0.name == "bug" })
        let enhancement = pr.labels.first(where: { $0.name == "enhancement" })
        #expect(bug?.color == "d73a4a")
        #expect(enhancement?.color == "0075ca")
    }

    @Test func prParser_labels_missingKeyReturnsEmptyArray() throws {
        let pr = try PRParser.parseSingle(PRFixtures.labelsMissing)
        #expect(pr.labels.isEmpty)
    }

    @Test func prParser_labels_labelWithoutNameIsFiltered() throws {
        let pr = try PRParser.parseSingle(PRFixtures.labelWithoutName)

        #expect(pr.labels.count == 1)
        #expect(pr.labels[0].name == "valid")
    }

    // MARK: Reviewers

    @Test func prParser_reviewers_parsedFromReviewRequests() throws {
        let pr = try PRParser.parseSingle(PRFixtures.reviewersPresent)

        #expect(pr.reviewers.count == 2)
        #expect(pr.reviewers.contains("charlie"))
        #expect(pr.reviewers.contains("diana"))
    }

    @Test func prParser_reviewers_missingKeyReturnsEmptyArray() throws {
        let pr = try PRParser.parseSingle(PRFixtures.reviewersMissing)
        #expect(pr.reviewers.isEmpty)
    }

    // MARK: Checks status

    @Test func prParser_checksStatus_allSuccessIsPassing() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksAllSuccess)
        #expect(pr.checksStatus == .passing)
    }

    @Test func prParser_checksStatus_containsFailureIsFailing() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksContainsFailure)
        #expect(pr.checksStatus == .failing)
    }

    @Test func prParser_checksStatus_containsPendingConclusionIsPending() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksContainsPendingConclusion)
        #expect(pr.checksStatus == .pending)
    }

    @Test func prParser_checksStatus_noConclusionsPendingStateIsPending() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksNoConclusionsPendingState)
        #expect(pr.checksStatus == .pending)
    }

    @Test func prParser_checksStatus_noRollupKeyIsNone() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksNoRollupKey)
        #expect(pr.checksStatus == .none)
    }

    @Test func prParser_checksStatus_emptyRollupArrayIsNone() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksNoConclusionsNoStates)
        #expect(pr.checksStatus == .none)
    }

    @Test func prParser_checksStatus_noConclusionsNonPendingStateIsPassing() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksNoConclusionsPassingStates)
        #expect(pr.checksStatus == .passing)
    }

    @Test func prParser_checksStatus_errorConclusionIsFailing() throws {
        let pr = try PRParser.parseSingle(PRFixtures.checksContainsError)
        #expect(pr.checksStatus == .failing)
    }

    // MARK: Author extraction

    @Test func prParser_author_nestedLoginUsed() throws {
        let pr = try PRParser.parseSingle(PRFixtures.authorWithLogin)
        #expect(pr.authorName == "eve")
    }

    @Test func prParser_author_nestedNameUsedWhenNoLogin() throws {
        let pr = try PRParser.parseSingle(PRFixtures.authorWithNameOnly)
        #expect(pr.authorName == "Frank Furter")
    }

    @Test func prParser_author_missingAuthorDefaultsToUnknown() throws {
        let pr = try PRParser.parseSingle(PRFixtures.authorMissing)
        #expect(pr.authorName == "Unknown")
    }

    // MARK: parseComments — empty

    @Test func prParser_parseComments_emptyArraysReturnsEmpty() throws {
        let comments = try PRParser.parseComments(PRFixtures.commentsAndReviewsEmpty)
        #expect(comments.isEmpty)
    }

    @Test func prParser_parseComments_missingBothKeysReturnsEmpty() throws {
        let comments = try PRParser.parseComments(PRFixtures.commentsMissingBothKeys)
        #expect(comments.isEmpty)
    }

    // MARK: parseComments — plain comments

    @Test func prParser_parseComments_plainCommentsHaveIsReviewFalse() throws {
        let comments = try PRParser.parseComments(PRFixtures.commentsOnlyPlain)

        #expect(comments.count == 2)
        #expect(comments.allSatisfy { !$0.isReview })
        #expect(comments[0].authorName == "alice")
        #expect(comments[0].body == "Looks good to me!")
        #expect(comments[1].authorName == "bob")
        #expect(comments[1].body == "Please add tests.")
    }

    // MARK: parseComments — reviews

    @Test func prParser_parseComments_reviewsHaveIsReviewTrue() throws {
        let comments = try PRParser.parseComments(PRFixtures.reviewsOnly)

        #expect(comments.count == 1)
        #expect(comments[0].isReview == true)
        #expect(comments[0].authorName == "charlie")
        #expect(comments[0].body == "Approved!")
    }

    @Test func prParser_parseComments_reviewWithEmptyBodyIsSkipped() throws {
        let comments = try PRParser.parseComments(PRFixtures.reviewWithEmptyBody)

        #expect(comments.count == 1)
        #expect(comments[0].authorName == "eve")
        #expect(comments[0].body == "Changes requested.")
    }

    // MARK: parseComments — chronological sort

    @Test func prParser_parseComments_mixedCommentsAndReviewsSortedChronologically() throws {
        let comments = try PRParser.parseComments(PRFixtures.mixedChronological)

        #expect(comments.count == 3)
        #expect(comments[0].body == "First comment")
        #expect(comments[1].body == "Second review")
        #expect(comments[2].body == "Third comment")
    }

    @Test func prParser_parseComments_chronologicalSortUsesCreatedDate() throws {
        let comments = try PRParser.parseComments(PRFixtures.mixedChronological)

        for i in 0..<(comments.count - 1) {
            #expect(comments[i].createdDate <= comments[i + 1].createdDate)
        }
    }
}
