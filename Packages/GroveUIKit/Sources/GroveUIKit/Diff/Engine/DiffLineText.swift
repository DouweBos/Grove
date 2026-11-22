// Diff/Engine/DiffLineText.swift
// GroveUIKit
//
// One line as drawn: tabs expanded, highlights in its UTF-16 offsets, and where it wraps.

#if os(macOS)
import Foundation

nonisolated struct DiffLineText {

    static let tab = "    "

    struct Token: Equatable {
        let range: NSRange
        let kind: SyntaxKind
    }

    let content: String
    let text: NSString
    let tokens: [Token]
    let words: [NSRange]
    /// Where each visual line starts in `text`.
    let starts: [Int]
    let isASCII: Bool

    init(_ content: String, spans: [SyntaxSpan] = [], words: [Range<Int>] = [], columns: Int? = nil) {
        self.content = content
        let display = content.utf8.contains(0x09) ? content.replacingOccurrences(of: "\t", with: Self.tab) : content
        let text = display as NSString
        self.text = text
        isASCII = display.utf8.count == text.length
        starts = columns.map { DiffWrap.starts(content, columns: $0) } ?? [0]
        guard !spans.isEmpty || !words.isEmpty else {
            tokens = []
            self.words = []
            return
        }
        // Highlights count Characters; drawing counts the display text's UTF-16.
        let last = max(spans.last?.range.upperBound ?? 0, words.last?.upperBound ?? 0)
        var offsets = [0]
        offsets.reserveCapacity(last + 1)
        var offset = 0
        for character in content {
            guard offsets.count <= last else { break }
            for unit in character.utf16 { offset += unit == 0x09 ? Self.tab.count : 1 }
            offsets.append(offset)
        }
        func range(_ characters: Range<Int>) -> NSRange {
            let start = offsets[min(characters.lowerBound, offsets.count - 1)]
            let end = offsets[min(characters.upperBound, offsets.count - 1)]
            return NSRange(location: start, length: max(0, end - start))
        }
        tokens = spans.map { Token(range: range($0.range), kind: $0.kind) }
        self.words = words.map(range)
    }

    var lineCount: Int { starts.count }

    func range(ofLine index: Int) -> NSRange {
        let end = index + 1 < starts.count ? starts[index + 1] : text.length
        let start = min(starts[index], end)
        return NSRange(location: start, length: end - start)
    }

    /// The file's own text under a range of the display text, so a copy keeps its tabs.
    func original(_ range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var display = 0
        var start: Int?
        var end = 0
        for (index, unit) in content.utf16.enumerated() {
            let next = display + (unit == 0x09 ? Self.tab.count : 1)
            if next > range.location, display < NSMaxRange(range) {
                if start == nil { start = index }
                end = index + 1
            }
            display = next
        }
        guard let start else { return "" }
        return (content as NSString).substring(with: NSRange(location: start, length: end - start))
    }

    /// The word at a display offset, for a double click.
    func word(at offset: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let at = min(max(offset, 0), text.length - 1)
        func isWord(_ index: Int) -> Bool {
            let unit = text.character(at: index)
            if unit == 0x5F { return true }
            guard let scalar = Unicode.Scalar(unit) else { return true }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        guard isWord(at) else { return text.rangeOfComposedCharacterSequence(at: at) }
        var start = at
        var end = at + 1
        while start > 0, isWord(start - 1) { start -= 1 }
        while end < text.length, isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
#endif
