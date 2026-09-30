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

    /// A lint, build and test job whose states add up to the run's status.
    static func ciJobs(for run: CIRun) -> [CIJob] {
        let start = run.startedDate ?? run.createdDate
        func job(_ offset: Int, _ name: String, _ status: CIRunStatus, steps: [(String, CIRunStatus, Double)]) -> CIJob {
            var clock = start.addingTimeInterval(Double(offset))
            let built = steps.enumerated().map { index, step -> CIStep in
                let (name, status, seconds) = step
                let began = clock
                clock = clock.addingTimeInterval(seconds)
                let ran = status != .queued && status != .skipped
                return CIStep(number: index + 1, name: name, status: status, startedDate: ran ? began : nil,
                              completedDate: ran && status != .inProgress ? clock : nil)
            }
            return CIJob(id: run.id * 10 + offset, runID: run.id, name: name, status: status,
                         startedDate: status == .queued ? nil : start.addingTimeInterval(Double(offset)),
                         completedDate: status.isActive ? nil : clock, steps: built, webURL: "\(run.webURL)/job/\(run.id * 10 + offset)")
        }
        let last = run.status
        let test: CIRunStatus = last == .success || last == .failure || last == .inProgress ? last : .skipped
        return [
            job(1, "lint", last == .queued ? .queued : last == .cancelled ? .cancelled : last == .skipped ? .skipped : .success, steps: [
                ("Set up job", .success, 2), ("Run actions/checkout@v4", .success, 3), ("Run swiftlint", .success, 21),
                ("Complete job", .success, 1)
            ]),
            job(2, "build (macos-15, arm64)", last == .queued ? .queued : test, steps: [
                ("Set up job", .success, 3), ("Run actions/checkout@v4", .success, 4), ("Build", .success, 148),
                ("Test", test, 96), ("Upload test results", test == .failure ? .skipped : test, 5),
                ("Complete job", test == .inProgress ? .queued : .success, 1)
            ])
        ]
    }

    /// A log in GitHub's format whose timestamps line up with the job's steps.
    static func ciLog(for job: CIJob) -> String {
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        var lines: [String] = []
        for step in job.steps {
            guard let start = step.startedDate else { continue }
            var offset = 0.05
            func add(_ text: String) {
                lines.append("\(start.addingTimeInterval(offset).formatted(stamp)) \(text)")
                offset += 0.05
            }
            switch step.name {
            case "Set up job":
                add("Current runner version: '2.328.0'")
                add("##[group]Runner Image")
                add("Image: macos-15-arm64")
                add("Version: 20260922.1")
                add("##[endgroup]")
                add("Complete job name: \(job.name)")
            case "Complete job":
                add("Cleaning up orphan processes")
            default:
                add("##[group]Run \(step.name.replacingOccurrences(of: "Run ", with: ""))")
                add("\u{1B}[36;1mxcodebuild -scheme Grove \(step.name.lowercased())\u{1B}[0m")
                add("shell: /bin/bash -e {0}")
                add("##[endgroup]")
                add("\u{1B}[1mCompiling\u{1B}[0m GroveApp.swift")
                add("\u{1B}[32m✔\u{1B}[0m DiffParserTests passed (0.412 seconds)")
                add("##[warning]Variable 'result' was never mutated; consider changing to 'let'")
                if step.status == .failure {
                    add("\u{1B}[31m✘\u{1B}[0m CIHostTests.runsMapStatus failed: expected 2, got 3")
                    add("##[error]Process completed with exit code 65.")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
