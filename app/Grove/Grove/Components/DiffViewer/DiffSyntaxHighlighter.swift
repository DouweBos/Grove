// Components/DiffViewer/DiffSyntaxHighlighter.swift
// Grove
//
// Colors diff lines by syntax, one hunk at a time as lines come into view, beneath the word highlights.

import SwiftUI

enum DiffSyntax {

    /// Spans per line ID. Old and new sides are lexed separately so a comment opened in a
    /// deleted line doesn't swallow the added lines after it.
    static func spans(for hunk: HunkData, language: SyntaxLanguage) -> [String: [SyntaxSpan]] {
        let tokenizer = SyntaxTokenizer(language: language)
        var oldState = SyntaxTokenizer.State.normal
        var newState = SyntaxTokenizer.State.normal
        var result: [String: [SyntaxSpan]] = [:]
        result.reserveCapacity(hunk.lines.count)
        for line in hunk.lines {
            switch line.type {
            case .deletion:
                result[line.id] = tokenizer.tokenize(line.content, state: &oldState)
            case .addition:
                result[line.id] = tokenizer.tokenize(line.content, state: &newState)
            case .context:
                var old = oldState
                _ = tokenizer.tokenize(line.content, state: &old)
                oldState = old
                result[line.id] = tokenizer.tokenize(line.content, state: &newState)
            }
        }
        return result
    }

    /// Foreground colors over `base` (the word-highlighted line) or over the plain content.
    static func attributed(_ content: String, spans: [SyntaxSpan], base: AttributedString?) -> AttributedString {
        var text = base ?? AttributedString(content)
        var cursor = text.startIndex
        var offset = 0
        for span in spans where !span.range.isEmpty {
            guard let start = text.characters.index(cursor, offsetBy: span.range.lowerBound - offset, limitedBy: text.endIndex),
                  let end = text.characters.index(start, offsetBy: span.range.count, limitedBy: text.endIndex) else { break }
            text[start..<end].foregroundColor = color(span.kind)
            cursor = end
            offset = span.range.upperBound
        }
        return text
    }

    static func color(_ kind: SyntaxKind) -> Color {
        switch kind {
        case .keyword: Theme.syntaxKeyword
        case .string: Theme.syntaxString
        case .comment: Theme.syntaxComment
        case .number: Theme.syntaxNumber
        case .type: Theme.syntaxType
        }
    }
}

/// Per-DiffView cache: a hunk is lexed the first time one of its lines renders, then reused.
@MainActor
final class DiffSyntaxCache {

    /// Hunk IDs come from the header alone, so the content is part of the key.
    struct HunkKey: Hashable {
        let path: String
        let header: String
        let fingerprint: Int
    }

    /// Hunks past this size stay plain; a generated file shouldn't cost a long pause.
    static let maxHunkLines = 20_000

    /// Shared across diff views so going back to a file doesn't lex it again.
    private static var shared = LRUCache<HunkKey, [String: [SyntaxSpan]]>(capacity: 300)

    private var hunkSpans: [HunkKey: [String: [SyntaxSpan]]] = [:]
    private var lines: [LineKey: AttributedString] = [:]

    private struct LineKey: Hashable {
        let hunk: HunkKey
        let line: String
        let hasWordHighlight: Bool
    }

    /// `nil` for languages Grove doesn't color and for hunks too large to lex.
    static func key(for hunk: HunkData, path: String) -> HunkKey? {
        guard SyntaxLanguage.forPath(path) != nil, hunk.lines.count <= maxHunkLines else { return nil }
        var hasher = Hasher()
        hasher.combine(hunk.lines)
        return HunkKey(path: path, header: hunk.header, fingerprint: hasher.finalize())
    }

    /// `nil` when there's nothing to color beyond the word highlight.
    func attributed(for line: DiffLine, in hunk: HunkData, key: HunkKey?, wordHighlight: AttributedString?) -> AttributedString? {
        guard let key, let language = SyntaxLanguage.forPath(key.path) else { return wordHighlight }
        let lineKey = LineKey(hunk: key, line: line.id, hasWordHighlight: wordHighlight != nil)
        if let cached = lines[lineKey] { return cached }
        let spans = spans(for: hunk, key: key, language: language)[line.id] ?? []
        guard !spans.isEmpty || wordHighlight != nil else { return nil }
        let text = DiffSyntax.attributed(line.content, spans: spans, base: wordHighlight)
        lines[lineKey] = text
        return text
    }

    private func spans(for hunk: HunkData, key: HunkKey, language: SyntaxLanguage) -> [String: [SyntaxSpan]] {
        if let spans = hunkSpans[key] { return spans }
        let spans = Self.shared.value(for: key) ?? DiffSyntax.spans(for: hunk, language: language)
        Self.shared.insert(spans, for: key)
        hunkSpans[key] = spans
        return spans
    }
}
