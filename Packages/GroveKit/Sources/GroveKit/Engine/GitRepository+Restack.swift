// Engine/GitRepository+Restack.swift
// GroveKit
//
// Runs a restack plan layer by layer; the plan lives in `<git-dir>/<state directory>/restack.json` while it runs, so a conflict
// can stop the cascade and Continue or Abort pick it up, even after a relaunch.

import Foundation
import os

/// Why a restack didn't finish.
public enum RestackError: LocalizedError, Equatable {
    /// A layer's rebase hit a conflict; resolve it in Changes, then continue.
    case stopped(String)
    case dirtyWorktree
    case alreadyRunning
    case notFastForward(branch: String, target: String)

    public var errorDescription: String? {
        switch self {
        case .stopped(let title): "\(title) stopped on a conflict. Resolve it in Changes, then continue."
        case .dirtyWorktree: "Commit or stash your changes before restacking."
        case .alreadyRunning: "A restack is already in progress. Continue or abort it first."
        case .notFastForward(let branch, let target): "\(branch) can't move forward to \(target) without a restack first."
        }
    }
}

extension GitRepository {

    private func planURL() async -> URL? {
        await absoluteGitDir()?.appendingPathComponent("\(naming.stateDirectory)/restack.json")
    }

    public func pendingRestack() async -> RestackPlan? {
        guard let url = await planURL(), let data = try? await shell.runner.readFile(at: url) else { return nil }
        return try? JSONDecoder().decode(RestackPlan.self, from: data)
    }

    private func save(_ plan: RestackPlan?) async throws {
        guard let url = await planURL() else { return }
        guard let plan else {
            try? await shell.runner.removeItem(at: url)
            return
        }
        try await shell.runner.writeFile(JSONEncoder().encode(plan), to: url, executable: false)
    }

    public func restack(_ plan: RestackPlan) async throws {
        guard !plan.isEmpty else { return }
        guard await pendingRestack() == nil, repositoryState == .normal else { throw RestackError.alreadyRunning }
        guard try await isClean(shell) else { throw RestackError.dirtyWorktree }
        Logger.gitRepository.info("Restacking \(plan.steps.count, privacy: .public) layers of \(plan.stackName, privacy: .public)")
        var plan = plan
        for index in plan.steps.indices where plan.steps[index].oldBase.isEmpty {
            let step = plan.steps[index]
            plan.steps[index].oldBase = await forkPoint(parent: step.onto, branch: step.branch) ?? ""
        }
        try await save(plan)
        try await run(plan)
    }

    public func continueRestack() async throws {
        guard var plan = await pendingRestack() else { return try await continueOperation() }
        if repositoryState != .normal {
            let result = try await shell.runAllowingFailure(["rebase", "--continue"], environment: ["GIT_EDITOR": "true"])
            await reloadState()
            if !result.isSuccess || repositoryState != .normal { throw RestackError.stopped(plan.progressTitle) }
        }
        plan.next += 1
        try await save(plan)
        try await run(plan)
    }

    /// Stops the rebase in progress and puts every layer the cascade already moved back where it was.
    public func abortRestack() async throws {
        guard let plan = await pendingRestack() else { return try await abortRebase() }
        Logger.gitRepository.info("Aborting restack of \(plan.stackName, privacy: .public)")
        if repositoryState != .normal { _ = try await shell.runAllowingFailure(["rebase", "--abort"]) }
        for step in plan.steps.prefix(plan.next).reversed() where !plan.skipped.contains(step.branch) {
            if let path = step.worktreePath {
                _ = try await shell.at(URL(fileURLWithPath: path)).run(["reset", "--keep", step.originalTip])
            } else {
                try await shell.run(["update-ref", "refs/heads/\(step.branch)", step.originalTip])
            }
        }
        if let original = plan.originalBranch { _ = try await shell.runAllowingFailure(["checkout", original]) }
        try await save(nil)
        await reloadState()
    }

    private func run(_ plan: RestackPlan) async throws {
        var plan = plan
        while let step = plan.current {
            plan = try await runStep(step, in: plan)
            plan.next += 1
            try await save(plan)
        }
        if let original = plan.originalBranch, plan.steps.contains(where: { $0.worktreePath == nil }) {
            _ = try await shell.runAllowingFailure(["checkout", original])
        }
        try await save(nil)
        await reloadState()
        Logger.gitRepository.info("Restack of \(plan.stackName, privacy: .public) finished")
    }

    /// One `rebase --onto`; a layer checked out in another worktree is rebased there, or skipped when that can't be done cleanly.
    private func runStep(_ step: RestackPlan.Step, in plan: RestackPlan) async throws -> RestackPlan {
        var plan = plan
        let target = try await shell.run(["rev-parse", "--verify", "\(step.onto)^{commit}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["rebase", "--onto", target]
        // No old base means the whole branch goes onto the target; git drops commits already there by patch.
        args += step.oldBase.isEmpty ? [target] : [step.oldBase]
        if let path = step.worktreePath {
            let worktree = shell.at(URL(fileURLWithPath: path))
            guard try await isClean(worktree) else {
                plan.skipped.append(step.branch)
                return plan
            }
            if try await !worktree.runAllowingFailure(args + [step.branch]).isSuccess {
                _ = try await worktree.runAllowingFailure(["rebase", "--abort"])
                plan.skipped.append(step.branch)
            }
            return plan
        }
        let result = try await shell.runAllowingFailure(args + [step.branch])
        await reloadState()
        if !result.isSuccess || repositoryState != .normal {
            Logger.gitRepository.notice("Restack stopped at \(step.branch, privacy: .public)")
            throw RestackError.stopped(plan.progressTitle)
        }
        return plan
    }

    // MARK: - Pushing and folding

    public func pushStack(_ layers: [StackPush], to remote: String) async throws {
        guard !layers.isEmpty else { return }
        Logger.gitRepository.info("Pushing \(layers.count, privacy: .public) stack layers to \(remote, privacy: .public)")
        try await shell.run(["push", "--atomic", "-u"] + layers.map(\.leaseArgument) + [remote] + layers.map(\.refspec))
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    public func fastForward(branch: String, to revision: String, worktreePath: String?) async throws {
        let target = try await shell.run(["rev-parse", "--verify", "\(revision)^{commit}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let worktreePath {
            try await shell.at(URL(fileURLWithPath: worktreePath)).run(["merge", "--ff-only", target])
        } else if currentBranch?.name == branch {
            try await shell.run(["merge", "--ff-only", target])
        } else {
            guard await isAncestor("refs/heads/\(branch)", of: target) else {
                throw RestackError.notFastForward(branch: branch, target: revision)
            }
            try await shell.run(["update-ref", "refs/heads/\(branch)", target])
        }
        await reloadState()
    }

    private func isClean(_ shell: GitShell) async throws -> Bool {
        try await shell.run(["status", "--porcelain", "--untracked-files=no"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reloadState() async {
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }
}
