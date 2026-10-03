// ViewModels/BlameViewModel.swift
// GroveKit

import Foundation
import Observation

/// One rendered line of a blamed file.
struct BlameLine: Identifiable, Hashable {
    let number: Int
    let text: String
    let entry: BlameEntry?
    /// First line of a run attributed to the same commit; carries the annotation.
    let startsBlock: Bool
    var id: Int { number }
}

/// Owns the tracked-file picker and the blame of the chosen file.
/// Session-owned so Quick Actions can open a file directly.
@MainActor
@Observable
final class BlameViewModel {

    // MARK: - File Picker

    private(set) var trackedFiles: [String] = []
    private(set) var isLoadingFiles = false
    private(set) var filterText = ""

    var filteredFiles: [String] {
        let query = filterText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return trackedFiles }
        return trackedFiles.filter { $0.lowercased().contains(query) }
    }

    // MARK: - Blame

    private(set) var selectedFile: String?
    /// Revision being blamed; nil blames the working tree.
    private(set) var revision: String?
    /// Newer revisions visited before stepping back, most recent last.
    private var revisionStack: [String?] = []
    private(set) var lines: [BlameLine] = []
    private(set) var isLoadingBlame = false
    private(set) var errorMessage: String?

    var canGoForward: Bool { !revisionStack.isEmpty }
    var isAtWorkingTree: Bool { revision == nil }
    var commitCount: Int { Set(lines.compactMap { $0.entry?.commitSHA }).count }

    let repository: any GitRepositoryProtocol
    // Revisions are immutable; working-tree entries (nil revision) are shown at once but always re-read.
    @ObservationIgnored private var blameCache = LRUCache<BlameKey, [BlameLine]>(capacity: 30)

    private struct BlameKey: Hashable {
        let file: String
        let revision: String?
    }

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Files

    func loadFilesIfNeeded() async {
        guard trackedFiles.isEmpty else { return }
        await reloadFiles()
    }

    func reloadFiles() async {
        isLoadingFiles = true
        defer { isLoadingFiles = false }
        trackedFiles = ((try? await repository.listTrackedFiles()) ?? []).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func setFilter(_ text: String) {
        filterText = text
    }

    // MARK: - Blame

    func open(file: String) async {
        selectedFile = file
        revision = nil
        revisionStack = []
        await loadBlame()
    }

    /// Re-blames at the parent of `sha`, i.e. how these lines looked before that commit.
    func blameBefore(_ sha: String) async {
        revisionStack.append(revision)
        revision = "\(sha)^"
        await loadBlame()
    }

    /// Steps back through the file's history from the newest commit shown.
    func goToPreviousRevision() async {
        guard let newest = lines.compactMap(\.entry).max(by: { $0.authorDate < $1.authorDate }) else { return }
        await blameBefore(newest.commitSHA)
    }

    func goForward() async {
        guard let newer = revisionStack.popLast() else { return }
        revision = newer
        await loadBlame()
    }

    func goToWorkingTree() async {
        revisionStack = []
        revision = nil
        await loadBlame()
    }

    func reload() async {
        await loadBlame()
    }

    private func loadBlame() async {
        guard let file = selectedFile else { return }
        let requested = revision
        let key = BlameKey(file: file, revision: requested)
        errorMessage = nil
        // Never leave another file's or revision's lines on screen while this one loads.
        if let cached = blameCache.value(for: key) {
            lines = cached
            if requested != nil {
                isLoadingBlame = false
                return
            }
        } else {
            lines = []
        }
        isLoadingBlame = true
        defer { if selectedFile == file, revision == requested { isLoadingBlame = false } }
        do {
            async let entries = repository.blame(file: file, revision: requested)
            async let contents = repository.fileContents(path: file, revision: requested)
            let (blame, text) = try await (entries, contents)
            let built = Self.buildLines(text: text, entries: blame)
            blameCache.insert(built, for: key)
            guard selectedFile == file, revision == requested else { return }
            lines = built
        } catch {
            guard selectedFile == file, revision == requested else { return }
            lines = []
            errorMessage = requested == nil
                ? error.localizedDescription
                : "This file has no earlier revision (it may have been added or renamed in that commit)."
        }
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
