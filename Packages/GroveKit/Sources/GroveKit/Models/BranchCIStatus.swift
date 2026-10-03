// Models/BranchCIStatus.swift
// GroveKit

import Foundation

/// How CI went for a branch's newest commit, as far as branch rows need to know.
nonisolated struct BranchCIStatus: Hashable, Sendable {
    let branch: String
    /// The worst status among the commit's runs: one failed workflow makes the branch failing.
    let status: CIRunStatus
    let headSHA: String
    /// Names of the workflows that ran, the ones in `status` first.
    let workflows: [String]
    /// The run that decided `status`, to open in the browser.
    let url: String

    /// The newest commit's runs per branch; `runs` are newest first, as hosts list them.
    static func index(_ runs: [CIRun]) -> [String: BranchCIStatus] {
        var newestSHA: [String: String] = [:]
        var grouped: [String: [CIRun]] = [:]
        for run in runs {
            guard let branch = run.branch, !branch.isEmpty else { continue }
            let sha = newestSHA[branch] ?? run.headSHA
            newestSHA[branch] = sha
            // Only a workflow's latest run on the commit counts, so a re-run that passed clears an earlier failure.
            if run.headSHA == sha, !(grouped[branch] ?? []).contains(where: { $0.workflowID == run.workflowID }) {
                grouped[branch, default: []].append(run)
            }
        }
        return grouped.reduce(into: [:]) { result, entry in
            let ranked = entry.value.sorted { severity($0.status) > severity($1.status) }
            guard let worst = ranked.first else { return }
            result[entry.key] = BranchCIStatus(branch: entry.key, status: worst.status, headSHA: worst.headSHA,
                                               workflows: ranked.map(\.workflowName), url: worst.webURL)
        }
    }

    private static func severity(_ status: CIRunStatus) -> Int {
        switch status {
        case .failure: 6
        case .inProgress: 5
        case .queued: 4
        case .cancelled: 3
        case .success: 2
        case .skipped: 1
        case .neutral: 0
        }
    }

    /// CI ran on one commit; it says nothing about a branch that has moved on since.
    func applies(toTip sha: String) -> Bool {
        !headSHA.isEmpty && sha == headSHA
    }

    var tooltip: String {
        let names = workflows.isEmpty ? "" : ": " + workflows.joined(separator: ", ")
        switch status {
        case .success: return "CI passed\(names)"
        case .failure: return "CI failed\(names)"
        case .inProgress: return "CI is running\(names)"
        case .queued: return "CI is queued\(names)"
        case .cancelled: return "CI was cancelled\(names)"
        case .skipped, .neutral: return "CI didn't run\(names)"
        }
    }
}
