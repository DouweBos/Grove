// Models/CIModels.swift
// Grove
//
// CI/CD runs as every provider reports them: a workflow's runs, their jobs and steps, and what they produced.

import Foundation

/// Where a run, job or step stands; providers' finer states fold into these.
nonisolated enum CIRunStatus: String, CaseIterable, Hashable, Sendable {
    case queued, inProgress, success, failure, cancelled, skipped, neutral

    /// Still going to change on the host, so worth polling.
    var isActive: Bool { self == .queued || self == .inProgress }

    var title: String {
        switch self {
        case .queued: "Queued"
        case .inProgress: "In Progress"
        case .success: "Success"
        case .failure: "Failed"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        case .neutral: "Neutral"
        }
    }
}

/// A pipeline definition, e.g. one file under `.github/workflows`.
nonisolated struct CIWorkflow: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// Path of the definition in the repository.
    let path: String
    /// False for workflows disabled on the host.
    let isEnabled: Bool
}

/// One execution of a workflow.
nonisolated struct CIRun: Identifiable, Hashable, Sendable {
    let id: Int
    /// The workflow's own counter, shown as `#12`.
    let number: Int
    /// Goes up with every re-run.
    let attempt: Int
    let title: String
    let workflowID: Int
    let workflowName: String
    /// What started it: `push`, `pull_request`, `workflow_dispatch`, …
    let event: String
    let branch: String?
    let headSHA: String
    let status: CIRunStatus
    let actor: String
    let createdDate: Date
    let updatedDate: Date
    /// When this attempt began; nil while queued.
    let startedDate: Date?
    let webURL: String

    var shortSHA: String { String(headSHA.prefix(7)) }

    /// Running time of a finished attempt, or time so far of an active one.
    func duration(now: Date = Date()) -> TimeInterval? {
        guard let startedDate else { return nil }
        return max(0, (status.isActive ? now : updatedDate).timeIntervalSince(startedDate))
    }
}

nonisolated struct CIJob: Identifiable, Hashable, Sendable {
    let id: Int
    let runID: Int
    let name: String
    let status: CIRunStatus
    let startedDate: Date?
    let completedDate: Date?
    let steps: [CIStep]
    let webURL: String

    func duration(now: Date = Date()) -> TimeInterval? {
        guard let startedDate else { return nil }
        return max(0, (completedDate ?? now).timeIntervalSince(startedDate))
    }
}

nonisolated struct CIStep: Identifiable, Hashable, Sendable {
    /// Position in the job, starting at 1.
    let number: Int
    let name: String
    let status: CIRunStatus
    let startedDate: Date?
    let completedDate: Date?

    var id: Int { number }

    var duration: TimeInterval? {
        guard let startedDate, let completedDate else { return nil }
        return max(0, completedDate.timeIntervalSince(startedDate))
    }
}

/// A file a run uploaded, downloadable as a zip until it expires.
nonisolated struct CIArtifact: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let sizeInBytes: Int
    let isExpired: Bool
    let createdDate: Date
    let expiresDate: Date?
}

/// Which runs to list; nil fields don't filter.
nonisolated struct CIRunQuery: Hashable, Sendable {
    var workflowID: Int?
    var branch: String?
    var status: CIRunStatus?

    var isEmpty: Bool { workflowID == nil && branch == nil && status == nil }
}

nonisolated enum CIDuration {
    /// `42s`, `3m 07s`, `1h 12m`.
    static func text(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", seconds % 3600 / 60))m"
    }
}
