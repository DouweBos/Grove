// GitKit/Parsers/PRParser.swift
// Grove
//
// Parses JSON output from the `gh` CLI into PullRequestInfo and PRComment values.
// All methods are `nonisolated` and free of actor requirements.

import Foundation

// MARK: - PRParserError

/// Errors thrown when `gh` CLI JSON output cannot be decoded.
enum PRParserError: LocalizedError {
    case invalidJSON(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Could not parse pull request JSON: \(detail)"
        case .missingField(let field):
            return "Pull request JSON is missing required field: \(field)"
        }
    }
}

// MARK: - PRParser

/// Parses `gh pr list` and `gh pr view` JSON into domain types.
enum PRParser {

    // MARK: - Parse List

    /// Parse the JSON array emitted by `gh pr list --json ...`.
    static func parseList(_ json: String) throws -> [PullRequestInfo] {
        guard let data = json.data(using: .utf8) else {
            throw PRParserError.invalidJSON("Not valid UTF-8")
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PRParserError.invalidJSON("Expected a JSON array at the top level")
        }
        return try array.map { try parsePRObject($0) }
    }

    // MARK: - Parse Single

    /// Parse the JSON object emitted by `gh pr view <number> --json ...`.
    static func parseSingle(_ json: String) throws -> PullRequestInfo {
        guard let data = json.data(using: .utf8) else {
            throw PRParserError.invalidJSON("Not valid UTF-8")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PRParserError.invalidJSON("Expected a JSON object at the top level")
        }
        return try parsePRObject(object)
    }

    // MARK: - Parse Comments

    /// Parse the JSON emitted by `gh pr view <number> --json comments,reviews`.
    ///
    /// Returns a chronologically-sorted combination of plain comments and reviews.
    static func parseComments(_ json: String) throws -> [PRComment] {
        guard let data = json.data(using: .utf8) else {
            throw PRParserError.invalidJSON("Not valid UTF-8")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PRParserError.invalidJSON("Expected a JSON object at the top level")
        }

        var comments: [PRComment] = []

        // Plain comments
        if let rawComments = object["comments"] as? [[String: Any]] {
            for (index, raw) in rawComments.enumerated() {
                let author  = authorName(from: raw)
                let body    = raw["body"] as? String ?? ""
                let date    = parseDate(raw["createdAt"] as? String)
                comments.append(PRComment(
                    id: "comment-\(index)",
                    authorName: author,
                    authorAvatarURL: nil,
                    body: body,
                    createdDate: date,
                    isReview: false
                ))
            }
        }

        // Review comments
        if let rawReviews = object["reviews"] as? [[String: Any]] {
            for (index, raw) in rawReviews.enumerated() {
                let author = authorName(from: raw)
                let body   = raw["body"] as? String ?? ""
                let date   = parseDate(raw["submittedAt"] as? String)
                guard !body.isEmpty else { continue }
                comments.append(PRComment(
                    id: "review-\(index)",
                    authorName: author,
                    authorAvatarURL: nil,
                    body: body,
                    createdDate: date,
                    isReview: true
                ))
            }
        }

        return comments.sorted { $0.createdDate < $1.createdDate }
    }

    // MARK: - Private Helpers

    private static func parsePRObject(_ raw: [String: Any]) throws -> PullRequestInfo {
        guard let number = raw["number"] as? Int else {
            throw PRParserError.missingField("number")
        }
        guard let title = raw["title"] as? String else {
            throw PRParserError.missingField("title")
        }

        let body         = raw["body"] as? String
        let author       = authorName(from: raw)
        let stateString  = (raw["state"] as? String ?? "open").lowercased()
        let sourceBranch = raw["headRefName"] as? String ?? ""
        let targetBranch = raw["baseRefName"] as? String ?? ""
        let createdDate  = parseDate(raw["createdAt"] as? String)
        let updatedDate  = parseDate(raw["updatedAt"] as? String)
        let isDraft      = raw["isDraft"] as? Bool ?? false

        let state: PRState
        switch stateString {
        case "closed": state = .closed
        case "merged": state = .merged
        default:       state = .open
        }

        // Labels
        let labels: [PRLabel]
        if let rawLabels = raw["labels"] as? [[String: Any]] {
            labels = rawLabels.compactMap { labelObj -> PRLabel? in
                guard let name = labelObj["name"] as? String else { return nil }
                let color = labelObj["color"] as? String ?? "6e7781"
                return PRLabel(id: name, name: name, color: color)
            }
        } else {
            labels = []
        }

        // Reviewers
        let reviewers: [String]
        if let rawReviewers = raw["reviewRequests"] as? [[String: Any]] {
            reviewers = rawReviewers.compactMap { authorName(from: $0) }.filter { !$0.isEmpty }
        } else {
            reviewers = []
        }

        // Checks status
        let checksStatus: PRChecksStatus
        if let rollup = raw["statusCheckRollup"] as? [[String: Any]] {
            let statuses = rollup.compactMap { $0["conclusion"] as? String }
            if statuses.isEmpty {
                let states = rollup.compactMap { $0["state"] as? String }
                if states.contains(where: { $0.lowercased() == "pending" || $0.lowercased() == "in_progress" }) {
                    checksStatus = .pending
                } else {
                    checksStatus = states.isEmpty ? .none : .passing
                }
            } else if statuses.contains(where: { $0.lowercased() == "failure" || $0.lowercased() == "error" }) {
                checksStatus = .failing
            } else if statuses.contains(where: { $0.lowercased() == "pending" }) {
                checksStatus = .pending
            } else {
                checksStatus = .passing
            }
        } else {
            checksStatus = .none
        }

        return PullRequestInfo(
            id: number,
            title: title,
            body: body,
            authorName: author,
            authorAvatarURL: nil,
            state: state,
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            createdDate: createdDate,
            updatedDate: updatedDate,
            isDraft: isDraft,
            labels: labels,
            reviewers: reviewers,
            checksStatus: checksStatus
        )
    }

    /// Extract the login name from an author or reviewer object.
    private static func authorName(from object: [String: Any]) -> String {
        if let author = object["author"] as? [String: Any] {
            return author["login"] as? String ?? author["name"] as? String ?? "Unknown"
        }
        return object["login"] as? String ?? object["name"] as? String ?? "Unknown"
    }

    /// Parse an ISO 8601 date string produced by the `gh` CLI.
    private static func parseDate(_ string: String?) -> Date {
        guard let string else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string) ?? Date()
    }
}
