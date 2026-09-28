// Domain/CommitMessageDrafter.swift
// Grove
//
// Drafts a commit summary and description from a staged diff with the Anthropic Messages API.

import Foundation

struct CommitMessageDraft: Decodable, Equatable, Sendable {
    let summary: String
    let description: String
}

struct CommitMessageDrafter: Sendable {

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-sonnet-5"
    /// Larger diffs are refused rather than cut, since a partial diff would describe the wrong change.
    static let maxDiffBytes = 400_000

    enum Failure: LocalizedError, Equatable {
        case emptyDiff
        case diffTooLarge(Int)
        case api(status: Int, message: String)
        case refused
        case unreadableResponse

        var errorDescription: String? {
            switch self {
            case .emptyDiff: "Stage some changes first; the draft is written from the staged diff."
            case .diffTooLarge(let bytes): "The staged diff is \(bytes / 1024) KB, too large to draft a message from. Stage fewer files."
            case .api(let status, let message): "Anthropic returned an error (\(status)): \(message)"
            case .refused: "Claude declined to draft a message for this diff."
            case .unreadableResponse: "Claude\u{2019}s reply couldn\u{2019}t be read as a commit message."
            }
        }
    }

    var session: URLSession = .shared

    func draft(diff: String, apiKey: String, branch: String?) async throws -> CommitMessageDraft {
        let request = try Self.request(diff: diff, apiKey: apiKey, branch: branch)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw Failure.api(status: status, message: message ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return try Self.parse(data)
    }

    static func request(diff: String, apiKey: String, branch: String?) throws -> URLRequest {
        guard !diff.isEmpty else { throw Failure.emptyDiff }
        let bytes = diff.utf8.count
        guard bytes <= maxDiffBytes else { throw Failure.diffTooLarge(bytes) }
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let context = branch.map { "Branch: \($0)\n\n" } ?? ""
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": context + "Staged diff:\n\n" + diff]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parse(_ data: Data) throws -> CommitMessageDraft {
        guard let message = try? JSONDecoder().decode(MessageBody.self, from: data) else { throw Failure.unreadableResponse }
        if message.stopReason == "refusal" { throw Failure.refused }
        guard message.stopReason != "max_tokens",
              let text = message.content.first(where: { $0.type == "text" })?.text,
              let draft = try? JSONDecoder().decode(CommitMessageDraft.self, from: Data(text.utf8)),
              !draft.summary.trimmingCharacters(in: .whitespaces).isEmpty else { throw Failure.unreadableResponse }
        return CommitMessageDraft(summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                  description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let systemPrompt = """
        You write git commit messages for the staged diff you are given. \
        The summary is one line in the imperative mood, under 72 characters, with no trailing period. \
        If the diff's context shows the project uses a convention such as Conventional Commits, follow it. \
        The description explains what changed and why in a few short lines, wrapped at 72 characters; \
        leave it empty when the summary says everything.
        """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string", "description": "One-line commit summary"],
            "description": ["type": "string", "description": "Commit body, may be empty"]
        ],
        "required": ["summary", "description"],
        "additionalProperties": false
    ]

    private struct MessageBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}
