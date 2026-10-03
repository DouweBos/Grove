// Models/CIModels.swift
// GroveKit
//
// CI/CD runs as every provider reports them: a workflow's runs, their jobs and steps, and what they produced.

import Foundation

/// Where a run, job or step stands; providers' finer states fold into these.
public nonisolated enum CIRunStatus: String, CaseIterable, Hashable, Sendable {
    case queued, inProgress, success, failure, cancelled, skipped, neutral

    /// Still going to change on the host, so worth polling.
    public var isActive: Bool { self == .queued || self == .inProgress }

    public var title: String {
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
public nonisolated struct CIWorkflow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    /// Path of the definition in the repository.
    public let path: String
    /// False for workflows disabled on the host.
    public let isEnabled: Bool

    public init(id: Int, name: String, path: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
    }
}

/// One execution of a workflow.
public nonisolated struct CIRun: Identifiable, Hashable, Sendable {
    public let id: Int
    /// The workflow's own counter, shown as `#12`.
    public let number: Int
    /// Goes up with every re-run.
    public let attempt: Int
    public let title: String
    public let workflowID: Int
    public let workflowName: String
    /// What started it: `push`, `pull_request`, `workflow_dispatch`, …
    public let event: String
    public let branch: String?
    public let headSHA: String
    public let status: CIRunStatus
    public let actor: String
    public let createdDate: Date
    public let updatedDate: Date
    /// When this attempt began; nil while queued.
    public let startedDate: Date?
    public let webURL: String
    /// The workflow's definition file, e.g. `.github/workflows/ci.yml`.
    public var workflowPath = ""

    public init(id: Int, number: Int, attempt: Int, title: String, workflowID: Int, workflowName: String, event: String, branch: String? = nil, headSHA: String, status: CIRunStatus, actor: String, createdDate: Date, updatedDate: Date, startedDate: Date? = nil, webURL: String, workflowPath: String = "") {
        self.id = id
        self.number = number
        self.attempt = attempt
        self.title = title
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.event = event
        self.branch = branch
        self.headSHA = headSHA
        self.status = status
        self.actor = actor
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.startedDate = startedDate
        self.webURL = webURL
        self.workflowPath = workflowPath
    }

    public var shortSHA: String { String(headSHA.prefix(7)) }

    /// Running time of a finished attempt, or time so far of an active one.
    public func duration(now: Date = Date()) -> TimeInterval? {
        guard let startedDate else { return nil }
        return max(0, (status.isActive ? now : updatedDate).timeIntervalSince(startedDate))
    }
}

public nonisolated struct CIJob: Identifiable, Hashable, Sendable {
    public let id: Int
    public let runID: Int
    public let name: String
    public let status: CIRunStatus
    public let startedDate: Date?
    public let completedDate: Date?
    public let steps: [CIStep]
    let webURL: String

    public init(id: Int, runID: Int, name: String, status: CIRunStatus, startedDate: Date? = nil, completedDate: Date? = nil, steps: [CIStep], webURL: String) {
        self.id = id
        self.runID = runID
        self.name = name
        self.status = status
        self.startedDate = startedDate
        self.completedDate = completedDate
        self.steps = steps
        self.webURL = webURL
    }

    func duration(now: Date = Date()) -> TimeInterval? {
        guard let startedDate else { return nil }
        return max(0, (completedDate ?? now).timeIntervalSince(startedDate))
    }
}

public nonisolated struct CIStep: Identifiable, Hashable, Sendable {
    /// Position in the job, starting at 1.
    public let number: Int
    public let name: String
    public let status: CIRunStatus
    public let startedDate: Date?
    public let completedDate: Date?

    public init(number: Int, name: String, status: CIRunStatus, startedDate: Date? = nil, completedDate: Date? = nil) {
        self.number = number
        self.name = name
        self.status = status
        self.startedDate = startedDate
        self.completedDate = completedDate
    }

    public var id: Int { number }

    var duration: TimeInterval? {
        guard let startedDate, let completedDate else { return nil }
        return max(0, completedDate.timeIntervalSince(startedDate))
    }
}

/// A note a job left on the run, e.g. a deprecation warning or a test failure with its file and line.
public nonisolated struct CIAnnotation: Identifiable, Hashable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case failure, warning, notice

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let jobID: Int
    /// Position among the job's annotations.
    let index: Int
    public let level: Level
    public let title: String?
    public let message: String
    /// The file and line it points at; nil for notes about the job itself.
    public let path: String?
    public let line: Int?

    public init(jobID: Int, index: Int, level: Level, title: String? = nil, message: String, path: String? = nil, line: Int? = nil) {
        self.jobID = jobID
        self.index = index
        self.level = level
        self.title = title
        self.message = message
        self.path = path
        self.line = line
    }

    public var id: String { "\(jobID)-\(index)" }
}

/// A file a run uploaded, downloadable as a zip until it expires.
public nonisolated struct CIArtifact: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let sizeInBytes: Int
    public let isExpired: Bool
    let createdDate: Date
    public let expiresDate: Date?
    /// `sha256:…` of the zip; nil for artifacts uploaded before the host recorded one.
    public var digest: String?

    public init(id: Int, name: String, sizeInBytes: Int, isExpired: Bool, createdDate: Date, expiresDate: Date? = nil, digest: String? = nil) {
        self.id = id
        self.name = name
        self.sizeInBytes = sizeInBytes
        self.isExpired = isExpired
        self.createdDate = createdDate
        self.expiresDate = expiresDate
        self.digest = digest
    }
}

/// Which runs to list; nil fields don't filter.
public nonisolated struct CIRunQuery: Hashable, Sendable {
    public var workflowID: Int?
    public var branch: String?
    public var status: CIRunStatus?
    /// How many runs to read; polls ask for fewer than the list shows.
    public var limit = CIRunQuery.pageSize
    /// Which page of `limit` runs, starting at 1.
    public var page = 1

    public init(workflowID: Int? = nil, branch: String? = nil, status: CIRunStatus? = nil, limit: Int = CIRunQuery.pageSize, page: Int = 1) {
        self.workflowID = workflowID
        self.branch = branch
        self.status = status
        self.limit = limit
        self.page = page
    }

    public static let pageSize = 50

    public var isEmpty: Bool { workflowID == nil && branch == nil && status == nil }

    public func limited(to limit: Int) -> CIRunQuery {
        var copy = self
        copy.limit = limit
        return copy
    }

    public func page(_ page: Int) -> CIRunQuery {
        var copy = self
        copy.page = page
        return copy
    }
}

public nonisolated enum CIDuration {
    /// `42s`, `3m 07s`, `1h 12m`.
    public static func text(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", seconds % 3600 / 60))m"
    }
}

/// One input a manually started workflow asks for.
public nonisolated struct CIDispatchInput: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case string, boolean, number, environment
        case choice([String])
    }

    public let name: String
    public var description = ""
    public var isRequired = false
    /// As the host wants it sent: booleans are `"true"` and `"false"`.
    public var defaultValue = ""
    public var kind = Kind.string

    public init(name: String, description: String = "", isRequired: Bool = false, defaultValue: String = "", kind: Kind = Kind.string) {
        self.name = name
        self.description = description
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.kind = kind
    }

    public var id: String { name }
}

/// A request to start a workflow on a branch or tag.
public nonisolated struct CIDispatch: Hashable, Sendable {
    public let workflowID: Int
    public let ref: String
    public var inputs: [String: String] = [:]

    public init(workflowID: Int, ref: String, inputs: [String: String] = [:]) {
        self.workflowID = workflowID
        self.ref = ref
        self.inputs = inputs
    }
}
