// Views/WorkingCopy/WorkingCopyViewModel+LFS.swift
// Grove
//
// Git LFS in the Changes tab: which changed files LFS stores, and tracking more with it.

import Foundation

/// The repository's LFS state and which changed files go through LFS.
struct WorkingCopyLFS: Equatable {
    var status = LFSStatus()
    var paths: Set<String> = []

    static func load(_ repository: any GitRepositoryProtocol, paths: [String]) async -> WorkingCopyLFS {
        let status = await repository.lfsStatus()
        guard status.usesLFS else { return WorkingCopyLFS(status: status) }
        return WorkingCopyLFS(status: status, paths: await repository.lfsTrackedPaths(among: paths))
    }
}

extension WorkingCopyViewModel {

    func isLFS(_ entry: StatusEntry) -> Bool { lfs.paths.contains(entry.path) }

    /// `*.psd` for `art/cover.psd`; nil for files without an extension.
    static func lfsExtensionPattern(for path: String) -> String? {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? nil : "*.\(ext)"
    }

    /// Tracks the file, or every file with its extension, with Git LFS.
    func trackWithLFS(_ entry: StatusEntry, byExtension: Bool) async {
        let pattern = byExtension ? Self.lfsExtensionPattern(for: entry.path) : entry.path
        guard let pattern else { return }
        await mutate {
            try await self.repository.trackWithLFS(pattern: pattern, literal: !byExtension)
        }
    }
}
