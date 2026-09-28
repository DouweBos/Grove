// Views/WorkingCopy/WorkingCopyViewModel+ExternalTools.swift
// Grove
//
// Hands a changed or conflicted file to the diff/merge tool configured in Editor preferences.

import Foundation

extension WorkingCopyViewModel {

    /// Compares the file's previous version against the side shown in the diff panel.
    func openInDiffTool(_ entry: StatusEntry, side: DiffSide) async {
        do {
            let dir = try Self.makeScratchDirectory()
            let staged = side == .staged
            let old = try await scratchCopy(entry.path, at: staged ? .commit("HEAD") : .index,
                                            label: staged ? "HEAD" : "index", in: dir)
            let new = staged
                ? try await scratchCopy(entry.path, at: .index, label: "staged", in: dir)
                : repository.path.appendingPathComponent(entry.path)
            try ExternalToolLauncher.launchDiffTool(oldFile: old, newFile: new, toolPath: AppToolPreferences.diffToolPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The tool writes its result into the working-tree file; marking it resolved still happens in Grove.
    func openInMergeTool(_ entry: StatusEntry) async {
        do {
            let dir = try Self.makeScratchDirectory()
            let base = try await scratchCopy(entry.path, at: .conflictStage(1), label: "BASE", in: dir)
            let ours = try await scratchCopy(entry.path, at: .conflictStage(2), label: "LOCAL", in: dir)
            let theirs = try await scratchCopy(entry.path, at: .conflictStage(3), label: "REMOTE", in: dir)
            try ExternalToolLauncher.launchMergeTool(base: base, ours: ours, theirs: theirs,
                                                     merged: repository.path.appendingPathComponent(entry.path),
                                                     toolPath: AppToolPreferences.mergeToolPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A side missing from git (added file, add/add conflict) becomes an empty file so the tool still opens.
    private func scratchCopy(_ path: String, at revision: FileRevision, label: String, in dir: URL) async throws -> URL {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let url = dir.appendingPathComponent(ext.isEmpty ? "\(stem).\(label)" : "\(stem).\(label).\(ext)")
        let data = (try? await repository.fileData(path: path, at: revision)) ?? Data()
        try data.write(to: url)
        return url
    }

    private static func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GroveExternalTools", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
