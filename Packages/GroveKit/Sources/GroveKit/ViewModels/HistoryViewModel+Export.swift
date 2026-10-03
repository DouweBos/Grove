// ViewModels/HistoryViewModel+Export.swift
// GroveKit

import Foundation

/// Patches and archives of commits, written where the user chose.
extension HistoryViewModel {

    /// Merges have no patch of their own, so at least one non-merge is needed.
    func canSavePatch(_ commits: [CommitInfo]) -> Bool {
        commits.contains { !$0.isMerge }
    }

    func patchFileName(for commits: [CommitInfo]) -> String {
        guard commits.count == 1, let commit = commits.first else { return "\(commits.count)-commits.patch" }
        return "\(commit.shortSHA)-\(ExportName.slug(commit.summary)).patch"
    }

    /// `commits` as listed, newest first; the patch applies oldest first.
    func savePatch(_ commits: [CommitInfo], to url: URL) async {
        errorMessage = nil
        do {
            let patch = try await repository.formatPatch(commits: commits.filter { !$0.isMerge }.reversed().map(\.id))
            try Data(patch.utf8).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Couldn't save the patch: \(error.localizedDescription)"
        }
    }

    func archiveFileName(for commit: CommitInfo) -> String {
        "\(repository.displayName)-\(commit.shortSHA).zip"
    }

    func exportArchive(of commit: CommitInfo, to url: URL) async {
        errorMessage = nil
        do {
            try await repository.archive(revision: commit.id, to: url)
        } catch {
            errorMessage = "Couldn't export the files: \(error.localizedDescription)"
        }
    }
}
