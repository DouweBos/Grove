// GitKit/GitRepository+Export.swift
// Grove
//
// Patches and archives written to files the user picked.

import Foundation
import os

extension GitRepository {

    /// One mbox of `commits` (oldest first) that `git am` applies in order; merges have no patch and are skipped.
    func formatPatch(commits: [String]) async throws -> String {
        Logger.gitRepository.info(
            "Formatting \(commits.count, privacy: .public) patches in \(self.displayName, privacy: .public)"
        )
        var patches = ""
        for commit in commits {
            let result = try await shell.run(["format-patch", "-1", "--stdout", commit])
            patches += result.stdout
        }
        return patches
    }

    /// Writes `revision`'s tree as an archive; git picks zip or tar from the file extension.
    func archive(revision: String, to url: URL) async throws {
        Logger.gitRepository.info(
            "Archiving \(revision, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["archive", "--output=\(url.path)", revision])
    }
}
