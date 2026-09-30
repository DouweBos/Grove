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

    /// The files of `entries` Git LFS can start tracking.
    func lfsCandidates(_ entries: [StatusEntry]) -> [StatusEntry] {
        entries.filter { !isLFS($0) && $0.workdirStatus != .deleted }
    }

    /// The one `*.ext` pattern every file shares, if any.
    static func lfsExtensionPattern(for entries: [StatusEntry]) -> String? {
        let patterns = Set(entries.map { lfsExtensionPattern(for: $0.path) })
        return patterns.count == 1 ? patterns.first ?? nil : nil
    }

    /// Tracks the files, or every file with their shared extension, with Git LFS.
    func trackWithLFS(_ entries: [StatusEntry], byExtension: Bool) async {
        let patterns = byExtension ? [Self.lfsExtensionPattern(for: entries)].compactMap { $0 } : entries.map(\.path)
        guard !patterns.isEmpty else { return }
        await mutate {
            for pattern in patterns {
                try await self.repository.trackWithLFS(pattern: pattern, literal: !byExtension)
            }
        }
    }
}
