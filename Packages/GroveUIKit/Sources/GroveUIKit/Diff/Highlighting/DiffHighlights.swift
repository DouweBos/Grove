// Diff/Highlighting/DiffHighlights.swift
// GroveUIKit
//
// One table's highlights, worked out as lines come into view. They hold kinds and ranges, never colors,
// so a theme change only redraws.

#if os(macOS)
import Foundation
import GroveKit

final class DiffHighlights {

    /// Hunks past this stay plain; their spans alone would be tens of megabytes.
    static let maxHunkLines = 100_000
    /// Up to this many lines lex as they're shown; longer hunks lex off the main thread.
    static let immediateLines = 200
    /// Hunks past this aren't kept for coming back to the file.
    static let maxCachedLines = 20_000

    private struct Key: Hashable {
        let hunk: String
        let language: String
    }

    private struct Lexed {
        let hunk: HunkData
        let spans: [[SyntaxSpan]]
    }

    private struct Position: Hashable {
        let hunk: Int
        let line: Int
    }

    /// Colors for these hunks arrived after their lines drew.
    var onChange: ((Set<Int>) -> Void)?

    private var hunks: [HunkData] = []
    private var language: SyntaxLanguage?
    private var shown: [Int: Lexed] = [:]
    /// Survives switching files, so going back to one doesn't lex it again.
    private var recent = LRUCache<Key, Lexed>(capacity: 300)
    private var pending: [Key: (hunk: HunkData, task: Task<Void, Never>)] = [:]
    private var partners: [Int: [Int]] = [:]
    private var words: [Position: [Range<Int>]] = [:]

    func reset(hunks: [HunkData], path: String) {
        let language = SyntaxLanguage.forPath(path)
        let kept = language?.name == self.language?.name ? shown.values.map { $0 } : []
        self.hunks = hunks
        self.language = language
        shown = [:]
        partners = [:]
        words = [:]
        let indices = Dictionary(hunks.indices.map { (hunks[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        for lexed in kept {
            if let index = indices[lexed.hunk.id], hunks[index] == lexed.hunk { shown[index] = lexed }
        }
        for (key, work) in pending where key.language != language?.name || indices[key.hunk] == nil {
            work.task.cancel()
            pending[key] = nil
        }
    }

    func cancel() {
        pending.values.forEach { $0.task.cancel() }
        pending = [:]
    }

    // MARK: Syntax

    func syntax(hunk index: Int, line: Int) -> [SyntaxSpan] {
        guard let language, hunks.indices.contains(index) else { return [] }
        if let lexed = shown[index] { return lexed.spans.indices.contains(line) ? lexed.spans[line] : [] }
        let hunk = hunks[index]
        guard hunk.lines.count <= Self.maxHunkLines else { return [] }
        let key = Key(hunk: hunk.id, language: language.name)
        if let lexed = recent.value(for: key), lexed.hunk == hunk {
            shown[index] = lexed
            return lexed.spans.indices.contains(line) ? lexed.spans[line] : []
        }
        if hunk.lines.count <= Self.immediateLines {
            guard let spans = DiffSyntax.spans(for: hunk.lines, language: language) else { return [] }
            let lexed = Lexed(hunk: hunk, spans: spans)
            shown[index] = lexed
            recent.insert(lexed, for: key)
            return spans.indices.contains(line) ? spans[line] : []
        }
        lex(hunk, key: key, language: language)
        return []
    }

    private func lex(_ hunk: HunkData, key: Key, language: SyntaxLanguage) {
        if let work = pending[key] {
            // The same id with other lines can only come from a diff the app built itself.
            guard work.hunk.lines.count != hunk.lines.count else { return }
            work.task.cancel()
        }
        let lines = hunk.lines
        let task = Task { [weak self] in
            let lexing = Task.detached(priority: .userInitiated) { DiffSyntax.spans(for: lines, language: language) }
            let spans = await withTaskCancellationHandler {
                await lexing.value
            } onCancel: {
                lexing.cancel()
            }
            guard !Task.isCancelled, let spans else { return }
            self?.finish(Lexed(hunk: hunk, spans: spans), key: key)
        }
        pending[key] = (hunk, task)
    }

    private func finish(_ lexed: Lexed, key: Key) {
        pending[key] = nil
        guard key.language == language?.name else { return }
        if lexed.hunk.lines.count <= Self.maxCachedLines { recent.insert(lexed, for: key) }
        var changed: Set<Int> = []
        for index in hunks.indices where hunks[index].id == key.hunk && hunks[index] == lexed.hunk {
            shown[index] = lexed
            changed.insert(index)
        }
        if !changed.isEmpty { onChange?(changed) }
    }

    // MARK: Words

    /// The changed words of a line that has one to compare with, across from it in a side-by-side diff.
    func changedWords(hunk index: Int, line: Int) -> [Range<Int>] {
        guard hunks.indices.contains(index), hunks[index].lines.indices.contains(line) else { return [] }
        let lines = hunks[index].lines
        guard lines[line].type != .context else { return [] }
        let position = Position(hunk: index, line: line)
        if let known = words[position] { return known }
        if partners[index] == nil { partners[index] = DiffRowBuilder.partners(lines) }
        guard let other = partners[index]?[line], other >= 0 else { return [] }
        let removed = min(line, other)
        let added = max(line, other)
        let changes = DiffWordHighlighter.changes(deletion: lines[removed].content, addition: lines[added].content)
        words[Position(hunk: index, line: removed)] = changes.deletion
        words[Position(hunk: index, line: added)] = changes.addition
        return words[position] ?? []
    }
}
#endif
