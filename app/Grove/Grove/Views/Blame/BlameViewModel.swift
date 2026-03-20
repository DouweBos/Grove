// Views/Blame/BlameViewModel.swift
// Grove

import Foundation
import Observation

// MARK: - BlameViewModel

/// ViewModel for ``BlameView``.
///
/// Owns the blame annotation data and the file's raw source lines.
/// Navigation between revisions updates ``revision`` and re-fetches both
/// the blame output and the file content for that revision.
@Observable
final class BlameViewModel {

    // MARK: - Inputs

    /// Path to the file being blamed, relative to the repository root.
    let filePath: String

    // MARK: - State

    /// The revision currently displayed. `nil` means HEAD.
    var revision: String?

    /// Blame annotation blocks loaded from the repository.
    var blameEntries: [BlameEntry] = []

    /// Raw source lines of the file at the current revision.
    var sourceLines: [String] = []

    /// Revision history used to navigate backwards.
    ///
    /// Each time ``navigateToPreviousRevision()`` is called the current
    /// revision is pushed here so ``navigateToCurrentRevision()`` can
    /// pop back to HEAD.
    private var revisionHistory: [String] = []

    /// Whether a load is in progress.
    var isLoading = false

    /// Non-nil when the last load produced an error.
    var errorMessage: String?

    // MARK: - Dependencies

    private let repository: any GitRepositoryProtocol

    // MARK: - Init

    /// - Parameters:
    ///   - filePath: Repository-relative path to the file being blamed.
    ///   - revision: Starting revision. Pass `nil` to start at HEAD.
    ///   - repository: The backing Git repository.
    init(
        filePath: String,
        revision: String? = nil,
        repository: any GitRepositoryProtocol
    ) {
        self.filePath = filePath
        self.revision = revision
        self.repository = repository
    }

    // MARK: - Loading

    /// Fetches blame annotations and source lines for the current ``revision``.
    func loadBlame() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Blame entries give us the annotation blocks.
            let entries = try await repository.blame(
                file: filePath,
                revision: revision
            )
            blameEntries = entries

            // Derive source lines from the blame entry summaries so the view
            // can show real content without a separate file-read API.
            // WS5/GitKit will supply actual file content; for now we
            // reconstruct lines from the blame block metadata.
            sourceLines = Self.buildSourceLines(from: entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Revision Navigation

    /// Steps back to the parent commit of the commit that introduced the first
    /// change block, allowing the user to walk the file's history.
    func navigateToPreviousRevision() async {
        // If there are blame entries, use the SHA of the oldest visible block
        // as the next revision anchor (the real engine will resolve its parent).
        guard let anchor = blameEntries.last?.commitSHA else { return }
        if let current = revision {
            revisionHistory.append(current)
        }
        revision = anchor
        await loadBlame()
    }

    /// Returns to HEAD (the most recent revision of the file).
    func navigateToCurrentRevision() async {
        revisionHistory.removeAll()
        revision = nil
        await loadBlame()
    }

    // MARK: - Helpers

    /// Total number of source lines in the file.
    var lineCount: Int { sourceLines.count }

    /// Returns the ``BlameEntry`` that covers `lineNumber` (1-based).
    func entry(for lineNumber: Int) -> BlameEntry? {
        blameEntries.first { entry in
            lineNumber >= entry.lineStart &&
            lineNumber < entry.lineStart + entry.lineCount
        }
    }

    /// True when navigating back from HEAD is possible.
    var canNavigateToPrevious: Bool { !blameEntries.isEmpty }

    /// True when there is a revision history to return from.
    var canNavigateToCurrent: Bool { revision != nil }

    // MARK: - Private Helpers

    /// Reconstructs a flat array of source-line strings from blame blocks.
    ///
    /// Each blame entry covers `lineCount` lines.  We fill them with
    /// `entry.summary` as placeholder text; the real engine will replace
    /// this with the actual file content.
    private static func buildSourceLines(from entries: [BlameEntry]) -> [String] {
        guard !entries.isEmpty else { return [] }
        let totalLines = entries.map { $0.lineStart + $0.lineCount - 1 }.max() ?? 0
        var lines = Array(repeating: "", count: totalLines)
        for entry in entries {
            for offset in 0..<entry.lineCount {
                let lineIndex = entry.lineStart + offset - 1   // convert to 0-based
                guard lineIndex < lines.count else { continue }
                // Use summary as stand-in; real content provided by GitKit.
                lines[lineIndex] = offset == 0 ? entry.summary : "    // \(entry.summary)"
            }
        }
        return lines
    }
}
