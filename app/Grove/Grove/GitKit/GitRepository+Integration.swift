// GitKit/GitRepository+Integration.swift
// Grove
//
// Merge, rebase, cherry-pick, revert, bisect and history rewriting.

import Foundation
import os

extension GitRepository {

    // MARK: - Merge / Rebase

    func merge(branch: String) async throws {
        Logger.gitRepository.info(
            "Merging \(branch, privacy: .public) into \(self.currentBranch?.name ?? "HEAD", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["merge", branch])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let mergeStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != mergeStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after merge: \(mergeStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortMerge() async throws {
        Logger.gitRepository.info("Aborting merge in \(self.displayName, privacy: .public)")
        try await shell.run(["merge", "--abort"])
        let mergeStateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(mergeStateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func rebase(onto: String) async throws {
        Logger.gitRepository.info(
            "Rebasing onto \(onto, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["rebase", onto])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let rebaseStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != rebaseStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after rebase: \(rebaseStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortRebase() async throws {
        Logger.gitRepository.info("Aborting rebase in \(self.displayName, privacy: .public)")
        try await shell.run(["rebase", "--abort"])
        let rebaseStateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(rebaseStateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func continueRebase() async throws {
        Logger.gitRepository.info("Continuing rebase in \(self.displayName, privacy: .public)")
        try await shell.run(
            ["rebase", "--continue"],
            environment: ["GIT_EDITOR": "true"]  // Accept default commit message.
        )
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let continueStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != continueStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after continue-rebase: \(continueStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func conflicts() async throws -> [StatusEntry] {
        let all = try await status()
        return all.filter {
            $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted
        }
    }

    // MARK: - Cherry-pick

    func cherryPick(commit: String) async throws {
        Logger.gitRepository.info(
            "Cherry-picking \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["cherry-pick", commit])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != stateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after cherry-pick: \(stateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortCherryPick() async throws {
        Logger.gitRepository.info("Aborting cherry-pick in \(self.displayName, privacy: .public)")
        try await shell.run(["cherry-pick", "--abort"])
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    // MARK: - Revert

    func revert(commit: String) async throws {
        Logger.gitRepository.info(
            "Reverting \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        // --no-edit prevents git from opening an editor for the revert message.
        try await shell.run(["revert", "--no-edit", commit])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != stateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after revert: \(stateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortRevert() async throws {
        Logger.gitRepository.info("Aborting revert in \(self.displayName, privacy: .public)")
        try await shell.run(["revert", "--abort"])
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    // MARK: - Bisect

    func bisectStart() async throws {
        Logger.gitRepository.info("Starting bisect in \(self.displayName, privacy: .public)")
        try await shell.run(["bisect", "start"])
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func bisectBad(commit: String?) async throws {
        var args = ["bisect", "bad"]
        if let commit { args.append(commit) }
        Logger.gitRepository.info(
            "Bisect bad\(commit.map { " \($0)" } ?? "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(args)
    }

    func bisectGood(commit: String?) async throws {
        var args = ["bisect", "good"]
        if let commit { args.append(commit) }
        Logger.gitRepository.info(
            "Bisect good\(commit.map { " \($0)" } ?? "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(args)
    }

    func bisectReset() async throws {
        Logger.gitRepository.info("Resetting bisect in \(self.displayName, privacy: .public)")
        try await shell.run(["bisect", "reset"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func bisectLog() async throws -> [String] {
        let result = try await shell.run(["bisect", "log"])
        return result.stdout
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    // MARK: - Interactive Rebase

    /// Runs `steps` (oldest first) on top of `base`. A conflict leaves the rebase stopped for the conflict
    /// banner to resolve and throws ``GitRepositoryError/rebaseStopped``.
    func rebaseInteractive(onto base: String, steps: [RebaseStep]) async throws {
        Logger.gitRepository.info(
            "Interactive rebase of \(steps.count, privacy: .public) commits onto \(base, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var scratch: [URL] = []
        defer { scratch.forEach { try? FileManager.default.removeItem(at: $0) } }
        var messageFiles: [String: String] = [:]
        for step in steps where step.action == .reword {
            guard let message = step.message else { continue }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grove-msg-\(UUID().uuidString)")
            try message.write(to: url, atomically: true, encoding: .utf8)
            scratch.append(url)
            messageFiles[step.sha] = shellEscape(url.path)
        }
        let todoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grove-todo-\(UUID().uuidString)")
        try RebasePlan.todo(steps) { messageFiles[$0] }.write(to: todoURL, atomically: true, encoding: .utf8)
        scratch.append(todoURL)
        // The sequence editor swaps git's proposed todo for ours; squashes keep git's combined message.
        let editor = try writeTemporaryScript("#!/bin/sh\ncat \(shellEscape(todoURL.path)) > \"$1\"\n")
        scratch.append(editor)

        do {
            try await shell.run(["rebase", "-i", base], environment: ["GIT_SEQUENCE_EDITOR": editor.path, "GIT_EDITOR": "true"])
        } catch {
            repositoryState = await Self.loadRepositoryState(path: path)
            currentBranch = try? await Self.loadCurrentBranch(shell: shell)
            if repositoryState != .normal { throw GitRepositoryError.rebaseStopped }
            throw error
        }
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func squashCommits(_ commits: [String], message: String) async throws {
        guard commits.count >= 2 else { return }
        Logger.gitRepository.info(
            "Squashing \(commits.count, privacy: .public) commits in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commits[0], action: "squash", targets: Array(commits.dropFirst()), message: message)
        Logger.gitRepository.info("Squash complete in \(self.displayName, privacy: .public)")
    }

    func rewordCommit(_ commit: String, newMessage: String) async throws {
        Logger.gitRepository.info(
            "Rewording \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commit, action: "reword", targets: [commit], message: newMessage)
        Logger.gitRepository.info("Reword complete in \(self.displayName, privacy: .public)")
    }

    func dropCommit(_ commit: String) async throws {
        Logger.gitRepository.info(
            "Dropping \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commit, action: "drop", targets: [commit], message: nil)
        Logger.gitRepository.info("Drop complete in \(self.displayName, privacy: .public)")
    }

    /// Scripted `rebase -i` from `oldest`'s parent that applies `action` to each target's pick line.
    func rewriteHistory(from oldest: String, action: String, targets: [String], message: String?) async throws {
        // Todo lines carry abbreviated SHAs, so match them as prefixes of the full target SHAs.
        let todoScript = """
            #!/bin/sh
            TODO="$1"
            TMP="$TODO.grove"
            : > "$TMP"
            while IFS= read -r line || [ -n "$line" ]; do
                cmd=${line%% *}
                rest=${line#* }
                sha=${rest%% *}
                if [ "$cmd" = pick ] && [ -n "$sha" ]; then
                    for target in \(targets.joined(separator: " ")); do
                        case "$target" in
                            "$sha"*)
                                if [ "\(action)" = drop ]; then continue 2; fi
                                line="\(action) $rest" ;;
                        esac
                    done
                fi
                printf '%s\\n' "$line" >> "$TMP"
            done < "$TODO"
            mv "$TMP" "$TODO"
            """
        let todoURL = try writeTemporaryScript(todoScript)
        defer { try? FileManager.default.removeItem(at: todoURL) }

        var environment = ["GIT_SEQUENCE_EDITOR": todoURL.path, "GIT_EDITOR": "true"]
        var editorURL: URL?
        if let message {
            let url = try writeTemporaryScript("#!/bin/sh\nprintf '%s\\n' \(shellEscape(message)) > \"$1\"\n")
            environment["GIT_EDITOR"] = url.path
            editorURL = url
        }
        defer { if let editorURL { try? FileManager.default.removeItem(at: editorURL) } }

        let parentResult = try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "\(oldest)^"])
        let base = parentResult.isSuccess
            ? [parentResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
            : ["--root"]

        do {
            try await shell.run(["rebase", "-i", "--rebase-merges"] + base, environment: environment)
        } catch {
            // A conflict leaves a half-done rebase; undo it so the branch is exactly as before.
            let stopped = await Self.loadRepositoryState(path: path) != .normal
            if stopped { _ = try? await shell.runAllowingFailure(["rebase", "--abort"]) }
            repositoryState = await Self.loadRepositoryState(path: path)
            currentBranch = try? await Self.loadCurrentBranch(shell: shell)
            throw stopped ? GitRepositoryError.historyRewriteConflict : error
        }
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }
}
