// Domain/Hosting/HostingJSON.swift
// Grove
//
// Shared pieces for turning service JSON into Grove's pull request and commit models.

import Foundation

nonisolated enum HostingJSON {

    typealias Object = [String: Any]

    static func object(_ data: Data) -> Object? {
        try? JSONSerialization.jsonObject(with: data) as? Object
    }

    /// Every object in one array, several concatenated arrays (paginated CLI output) or one object per line.
    static func objects(_ text: String) -> [Object] {
        var result: [Object] = []
        for chunk in topLevelValues(text) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(chunk.utf8)) else { continue }
            if let array = value as? [Object] { result += array } else if let single = value as? Object { result.append(single) }
        }
        return result
    }

    /// Splits text into its top-level JSON values by tracking bracket depth outside strings.
    private static func topLevelValues(_ text: String) -> [Substring] {
        var values: [Substring] = []
        var depth = 0
        var inString = false
        var escaped = false
        var start: String.Index?
        for index in text.indices {
            let char = text[index]
            if inString {
                (inString, escaped) = stringState(after: char, escaped: escaped)
                continue
            }
            switch char {
            case "\"": inString = true
            case "[", "{":
                if depth == 0 { start = index }
                depth += 1
            case "]", "}":
                depth -= 1
                if depth == 0, let begin = start { values.append(text[begin...index]) }
            default: break
            }
        }
        return values
    }

    /// Inside a JSON string: whether it continues after `char`, and whether the next character is escaped.
    private static func stringState(after char: Character, escaped: Bool) -> (inString: Bool, escaped: Bool) {
        if escaped { return (true, false) }
        if char == "\\" { return (true, true) }
        return (char != "\"", false)
    }

    static func date(_ value: Any?) -> Date {
        (value as? String).flatMap(GitDate.parse) ?? .distantPast
    }

    /// A commit from its full message, split into summary and body the way git does.
    static func commit(id: String, message: String, authorName: String, authorEmail: String, authored: Date,
                       committed: Date? = nil) -> CommitInfo {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let body = trimmed.dropFirst(summary.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommitInfo(id: id, message: trimmed, summary: summary, body: body.isEmpty ? nil : body,
                          authorName: authorName, authorEmail: authorEmail, authorDate: authored,
                          committerName: authorName, committerEmail: authorEmail, committerDate: committed ?? authored,
                          parentIDs: [], isSigned: false)
    }

    /// `"Jane Doe <jane@example.com>"` → ("Jane Doe", "jane@example.com").
    static func nameAndEmail(_ raw: String) -> (String, String) {
        guard let open = raw.firstIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close else { return (raw, "") }
        return (raw[..<open].trimmingCharacters(in: .whitespaces), String(raw[raw.index(after: open)..<close]))
    }

    /// Branch-row summaries of open and merged pull requests; closed ones say nothing about their branch.
    static func branchPullRequests(_ raws: [Object], parse: (Object) -> PullRequestInfo?, headSHA: (Object) -> String?,
                                   url: (Int, Object) -> String) -> [String: BranchPullRequest] {
        BranchPullRequest.index(raws.compactMap { raw in
            guard let pr = parse(raw), pr.state != .closed else { return nil }
            return BranchPullRequest(number: pr.id, title: pr.title, headBranch: pr.sourceBranch, isDraft: pr.isDraft,
                                     url: url(pr.id, raw), isMerged: pr.state == .merged, headSHA: headSHA(raw))
        })
    }
}

extension String {
    /// `refs/heads/feature` → `feature`, for services that report full ref names.
    nonisolated var withoutHeadsPrefix: String { hasPrefix("refs/heads/") ? String(dropFirst("refs/heads/".count)) : self }
}
