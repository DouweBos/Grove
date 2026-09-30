// Domain/Hosting/GitHubCIParser.swift
// Grove
//
// GitHub Actions JSON into Grove's CI models.

import Foundation

nonisolated enum GitHubCIParser {

    /// GitHub splits state into `status` (queued, in_progress, completed, …) and, once completed, `conclusion`.
    static func status(_ status: String?, conclusion: String?) -> CIRunStatus {
        switch status {
        case "in_progress": return .inProgress
        case "queued", "waiting", "requested", "pending": return .queued
        default: break
        }
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        case "cancelled": return .cancelled
        case "skipped": return .skipped
        default: return .neutral
        }
    }

    /// The `status` query value that lists runs in `status`.
    static func statusParameter(_ status: CIRunStatus) -> String {
        switch status {
        case .queued: "queued"
        case .inProgress: "in_progress"
        case .success: "success"
        case .failure: "failure"
        case .cancelled: "cancelled"
        case .skipped: "skipped"
        case .neutral: "neutral"
        }
    }

    static func workflow(_ raw: HostingJSON.Object) -> CIWorkflow? {
        guard let id = raw["id"] as? Int, let name = raw["name"] as? String else { return nil }
        return CIWorkflow(id: id, name: name, path: raw["path"] as? String ?? "", isEnabled: raw["state"] as? String == "active")
    }

    static func run(_ raw: HostingJSON.Object) -> CIRun? {
        guard let id = raw["id"] as? Int else { return nil }
        let name = raw["name"] as? String ?? ""
        let created = HostingJSON.date(raw["created_at"])
        return CIRun(
            id: id, number: raw["run_number"] as? Int ?? 0, attempt: raw["run_attempt"] as? Int ?? 1,
            title: (raw["display_title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name,
            workflowID: raw["workflow_id"] as? Int ?? 0, workflowName: name, event: raw["event"] as? String ?? "",
            branch: raw["head_branch"] as? String, headSHA: raw["head_sha"] as? String ?? "",
            status: status(raw["status"] as? String, conclusion: raw["conclusion"] as? String),
            actor: ((raw["triggering_actor"] ?? raw["actor"]) as? HostingJSON.Object)?["login"] as? String ?? "",
            createdDate: created, updatedDate: date(raw["updated_at"]) ?? created, startedDate: date(raw["run_started_at"]),
            webURL: raw["html_url"] as? String ?? ""
        )
    }

    static func job(_ raw: HostingJSON.Object) -> CIJob? {
        guard let id = raw["id"] as? Int else { return nil }
        let steps = (raw["steps"] as? [HostingJSON.Object] ?? []).compactMap(step).sorted { $0.number < $1.number }
        return CIJob(id: id, runID: raw["run_id"] as? Int ?? 0, name: raw["name"] as? String ?? "",
                     status: status(raw["status"] as? String, conclusion: raw["conclusion"] as? String),
                     startedDate: date(raw["started_at"]), completedDate: date(raw["completed_at"]), steps: steps,
                     webURL: raw["html_url"] as? String ?? "")
    }

    static func step(_ raw: HostingJSON.Object) -> CIStep? {
        guard let number = raw["number"] as? Int else { return nil }
        return CIStep(number: number, name: raw["name"] as? String ?? "",
                      status: status(raw["status"] as? String, conclusion: raw["conclusion"] as? String),
                      startedDate: date(raw["started_at"]), completedDate: date(raw["completed_at"]))
    }

    static func artifact(_ raw: HostingJSON.Object) -> CIArtifact? {
        guard let id = raw["id"] as? Int, let name = raw["name"] as? String else { return nil }
        return CIArtifact(id: id, name: name, sizeInBytes: raw["size_in_bytes"] as? Int ?? 0, isExpired: raw["expired"] as? Bool ?? false,
                          createdDate: HostingJSON.date(raw["created_at"]), expiresDate: date(raw["expires_at"]))
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap(GitDate.parse)
    }
}
