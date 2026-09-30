// Mocks/MockData+CI.swift
// Grove
//
// Fake workflows and runs.

import Foundation

extension MockData {

    static let ciWorkflows: [CIWorkflow] = [
        CIWorkflow(id: 1, name: "CI", path: ".github/workflows/ci.yml", isEnabled: true),
        CIWorkflow(id: 2, name: "Release", path: ".github/workflows/release.yml", isEnabled: true),
        CIWorkflow(id: 3, name: "Nightly", path: ".github/workflows/nightly.yml", isEnabled: false)
    ]

    static let ciRuns: [CIRun] = {
        let now = Date()
        func run(_ id: Int, _ title: String, workflow: Int, event: String = "push", branch: String?, sha: Int, _ status: CIRunStatus,
                 minutesAgo: Double, length: Double?, attempt: Int = 1, actor: String = authorJane.name) -> CIRun {
            let started = now.addingTimeInterval(-minutesAgo * 60)
            return CIRun(id: id, number: id - 100, attempt: attempt, title: title, workflowID: workflow,
                         workflowName: ciWorkflows.first { $0.id == workflow }?.name ?? "", event: event, branch: branch,
                         headSHA: commits[sha].id, status: status, actor: actor, createdDate: started.addingTimeInterval(-20),
                         updatedDate: started.addingTimeInterval((length ?? 1) * 60), startedDate: length == nil ? nil : started,
                         webURL: "https://github.com/example/app/actions/runs/\(id)")
        }
        return [
            run(148, "feat: add pull request list and detail views", workflow: 1, branch: "feature/auth", sha: 0, .inProgress,
                minutesAgo: 2, length: 2),
            run(147, "Release 1.4.0", workflow: 2, event: "workflow_dispatch", branch: "main", sha: 1, .queued, minutesAgo: 3, length: nil),
            run(146, "fix: keep the selection when a list reloads", workflow: 1, branch: "main", sha: 1, .success, minutesAgo: 42,
                length: 6.4),
            run(145, "refactor: share the diff cache", workflow: 1, event: "pull_request", branch: "feature/ui-overhaul", sha: 2, .failure,
                minutesAgo: 95, length: 4.1, attempt: 2, actor: authorBob.name),
            run(144, "Nightly", workflow: 3, event: "schedule", branch: "main", sha: 3, .cancelled, minutesAgo: 600, length: 1.2),
            run(143, "docs: describe the release lane", workflow: 1, branch: "main", sha: 4, .skipped, minutesAgo: 1500, length: 0.1,
                actor: authorAlice.name)
        ]
    }()
}
