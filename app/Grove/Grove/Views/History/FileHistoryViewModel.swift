// Views/History/FileHistoryViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - FileHistoryViewModel

/// ViewModel for the File History view.
///
/// Loads the per-file commit history using `git log --follow -- <path>`
/// and the diff for the selected file at any given commit.
@Observable
@MainActor
final class FileHistoryViewModel {

    // MARK: - State

    /// All commits that touched ``filePath``, in reverse-chronological order.
    var commits: [CommitInfo] = []
    /// The commit currently selected in the list panel.
    var selectedCommit: CommitInfo?
    /// The file diff at the selected commit revision.
    var fileDiff: DiffResult?
    var isLoading = false
    var isLoadingDiff = false
    var errorMessage: String?

    // MARK: - Configuration

    private let maxCount = 500

    // MARK: - Dependencies

    /// The repository this history belongs to.
    let repository: any GitRepositoryProtocol
    /// Repository-relative path of the file whose history is shown.
    let filePath: String

    // MARK: - Init

    init(repository: any GitRepositoryProtocol, filePath: String) {
        self.repository = repository
        self.filePath = filePath
    }

    // MARK: - Actions

    /// Load the full file-level commit history.
    ///
    /// Uses `git log --follow -- <filePath>` via ``GitRepositoryProtocol/fileLog(path:maxCount:)``.
    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            commits = try await repository.fileLog(path: filePath, maxCount: maxCount)
            // Auto-select the first (most recent) commit.
            if let first = commits.first, selectedCommit == nil {
                await selectCommit(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Select a commit and load the file diff at that revision.
    ///
    /// Calls ``GitRepositoryProtocol/diffForCommit(_:)`` and filters for the
    /// entry whose path matches ``filePath``.
    func selectCommit(_ commit: CommitInfo) async {
        selectedCommit = commit
        fileDiff = nil
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            let allDiffs = try await repository.diffForCommit(commit.id)
            // Match on current path or the pre-rename original path.
            fileDiff = allDiffs.first(where: {
                $0.path == filePath || $0.diff?.oldPath == filePath
            })?.diff ?? allDiffs.first?.diff
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Export the file at the selected commit to a user-chosen disk location.
    ///
    /// Runs `git show <sha>:<path>` as a subprocess in the repository's working
    /// directory, then writes the result to `destinationURL`.
    ///
    /// - Parameter destinationURL: The URL returned by an `NSSavePanel`.
    func exportFile(to destinationURL: URL) async {
        guard let commit = selectedCommit else { return }
        errorMessage = nil
        do {
            let spec = "\(commit.id):\(filePath)"
            let gitURL = try await resolveGitExecutable()
            let content = try await runProcess(
                executable: gitURL,
                arguments: ["show", spec],
                workingDirectory: repository.path
            )
            try content.write(to: destinationURL, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    /// Resolve the `git` executable path, checking common macOS installation locations.
    nonisolated private func resolveGitExecutable() async throws -> URL {
        let candidates = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    /// Run a subprocess and return its standard-output as `Data`.
    nonisolated private func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: NSError(
                        domain: "FileHistoryViewModel",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: stderr.trimmingCharacters(in: .whitespacesAndNewlines)]
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
