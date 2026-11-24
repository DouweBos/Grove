// ViewModels/BlameViewModel.swift
// GroveKit

import Foundation
import Observation

/// One rendered line of a blamed file.
public struct BlameLine: Identifiable, Hashable, Sendable {
    public let number: Int
    public let text: String
    public let entry: BlameEntry?
    /// First line of a run attributed to the same commit; carries the annotation.
    public let startsBlock: Bool
    public var id: Int { number }
}

/// Owns the tracked-file picker and the blame of the chosen file.
/// Session-owned so Quick Actions can open a file directly.
@MainActor
@Observable
public final class BlameViewModel {

    // MARK: - File Picker

    public private(set) var trackedFiles: [String] = []
    public private(set) var isLoadingFiles = false
    public private(set) var filterText = ""

    public var filteredFiles: [String] {
        let query = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return trackedFiles }
        return trackedFiles.filter { $0.lowercased().contains(query) }
    }

    // MARK: - Blame

    public private(set) var selectedFile: String?
    /// Revision being blamed; nil blames the working tree.
    public private(set) var revision: String?
    /// Newer revisions visited before stepping back, most recent last.
    private var revisionStack: [String?] = []
    public private(set) var lines: [BlameLine] = []
    public private(set) var isLoadingBlame = false
    public private(set) var errorMessage: String?

    public var canGoForward: Bool { !revisionStack.isEmpty }
    public var isAtWorkingTree: Bool { revision == nil }
    /// Commits the shown lines come from.
    public private(set) var commitCount = 0

    public let repository: any GitRepositoryProtocol
    // Revisions are immutable; working-tree entries (nil revision) are shown at once but always re-read.
    @ObservationIgnored private var blameCache = LRUCache<BlameKey, BlamedFile>(capacity: 30)

    private struct BlamedFile: Sendable {
        var lines: [BlameLine] = []
        var commitCount = 0
    }

    private struct BlameKey: Hashable {
        let file: String
        let revision: String?
    }

    public init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Files

    public func loadFilesIfNeeded() async {
        guard trackedFiles.isEmpty else { return }
        await reloadFiles()
    }

    public func reloadFiles() async {
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        trackedFiles = ((try? await repository.listTrackedFiles()) ?? []).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public func setFilter(_ text: String) {
        filterText = text
    }

    // MARK: - Blame

    /// Blames `file` at `revision` (any ref or SHA git accepts), or in the working tree when nil.
    public func open(file: String, revision: String? = nil) async {
        selectedFile = file
        self.revision = revision
        revisionStack = []
        await loadBlame()
    }

    /// Re-blames at the parent of `sha`, i.e. how these lines looked before that commit.
    public func blameBefore(_ sha: String) async {
        revisionStack.append(revision)
        revision = "\(sha)^"
        await loadBlame()
    }

    /// Steps back through the file's history from the newest commit shown.
    public func goToPreviousRevision() async {
        guard let newest = lines.compactMap(\.entry).max(by: { $0.authorDate < $1.authorDate }) else { return }
        await blameBefore(newest.commitSHA)
    }

    public func goForward() async {
        guard let newer = revisionStack.popLast() else { return }
        revision = newer
        await loadBlame()
    }

    public func goToWorkingTree() async {
        revisionStack = []
        revision = nil
        await loadBlame()
    }

    /// Closes the file that couldn't be blamed, back to picking one.
    public func dismissError() {
        guard errorMessage != nil else { return }
        close()
    }

    /// Back to picking a file, e.g. when the app's route names none.
    public func close() {
        errorMessage = nil
        selectedFile = nil
        revision = nil
        revisionStack = []
        show(BlamedFile())
        isLoadingBlame = false
    }

    public func reload() async {
        await loadBlame()
    }

    private func loadBlame() async {
        guard let file = selectedFile else { return }
        let requested = revision
        let key = BlameKey(file: file, revision: requested)
        errorMessage = nil
        // Never leave another file's or revision's lines on screen while this one loads.
        if let cached = blameCache.value(for: key) {
            show(cached)
            if requested != nil {
                isLoadingBlame = false
                return
            }
        } else {
            show(BlamedFile())
        }
        isLoadingBlame = true
        defer { if selectedFile == file, revision == requested { isLoadingBlame = false } }
        do {
            async let entries = repository.blame(file: file, revision: requested)
            async let contents = repository.fileContents(path: file, revision: requested)
            let (blame, text) = try await (entries, contents)
            // A 100k-line file takes tens of milliseconds to lay out, so not on the main thread.
            let built = await Task.detached(priority: .userInitiated) {
                let lines = Self.buildLines(text: text, entries: blame)
                return BlamedFile(lines: lines, commitCount: Set(lines.lazy.compactMap { $0.entry?.commitSHA }).count)
            }.value
            blameCache.insert(built, for: key)
            guard selectedFile == file, revision == requested else { return }
            show(built)
        } catch {
            guard selectedFile == file, revision == requested else { return }
            show(BlamedFile())
            // Only stepping back (`sha^`) can land before the file existed; other failures are git's own.
            errorMessage = requested?.hasSuffix("^") == true
                ? "This file has no earlier revision (it may have been added or renamed in that commit)."
                : error.localizedDescription
        }
    }

    private func show(_ file: BlamedFile) {
        lines = file.lines
        commitCount = file.commitCount
    }

    nonisolated static func buildLines(text: String, entries: [BlameEntry]) -> [BlameLine] {
        var source = text.components(separatedBy: "\n")
        if source.last == "" { source.removeLast() }
        var owner = [BlameEntry?](repeating: nil, count: source.count)
        for entry in entries {
            for offset in 0..<entry.lineCount {
                let index = entry.lineStart - 1 + offset
                if owner.indices.contains(index) { owner[index] = entry }
            }
        }
        return source.enumerated().map { index, line in
            let entry = owner[index]
            let previous = index > 0 ? owner[index - 1] : nil
            return BlameLine(number: index + 1, text: line, entry: entry,
                             startsBlock: entry?.commitSHA != previous?.commitSHA || index == 0)
        }
    }
}
