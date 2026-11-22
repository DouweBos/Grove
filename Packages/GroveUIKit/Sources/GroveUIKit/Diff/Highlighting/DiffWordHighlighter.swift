// Diff/Highlighting/DiffWordHighlighter.swift
// GroveUIKit
//
// The words a changed line pair doesn't share, as Character ranges.

#if os(macOS)
import Foundation

nonisolated enum DiffWordHighlighter {

    /// Past this many tokens a side counts as changed throughout, so one line's cost stays bounded.
    static let maxTokens = 300

    static func changes(deletion: String, addition: String) -> (deletion: [Range<Int>], addition: [Range<Int>]) {
        guard let removed = tokens(deletion), let added = tokens(addition), !removed.isEmpty, !added.isEmpty else {
            return (whole(deletion), whole(addition))
        }
        let kept = unchanged(removed.map(\.text), added.map(\.text))
        return (changed(removed, kept: kept.removed), changed(added, kept: kept.added))
    }

    private static func whole(_ text: String) -> [Range<Int>] {
        text.isEmpty ? [] : [0..<text.count]
    }

    private struct Token {
        let text: Substring
        let range: Range<Int>
    }

    /// Words and single other Characters; nil past `maxTokens`.
    private static func tokens(_ string: String) -> [Token]? {
        var tokens: [Token] = []
        var start = string.startIndex
        var position = 0
        while start < string.endIndex {
            guard tokens.count < maxTokens else { return nil }
            let from = position
            var end = start
            while end < string.endIndex, isWord(string[end]) {
                end = string.index(after: end)
                position += 1
            }
            if end == start {
                end = string.index(after: end)
                position += 1
            }
            tokens.append(Token(text: string[start..<end], range: from..<position))
            start = end
        }
        return tokens
    }

    private static func isWord(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }

    /// Which tokens are in the longest common subsequence.
    private static func unchanged(_ a: [Substring], _ b: [Substring]) -> (removed: [Bool], added: [Bool]) {
        var removed = Array(repeating: false, count: a.count)
        var added = Array(repeating: false, count: b.count)
        // Compared as numbers: the table below compares each token with each of the other side's.
        var numbers: [Substring: Int32] = [:]
        func number(_ token: Substring) -> Int32 {
            if let known = numbers[token] { return known }
            let next = Int32(numbers.count)
            numbers[token] = next
            return next
        }
        let left = a.map(number)
        let right = b.map(number)
        let width = right.count + 1
        var table = [Int32](repeating: 0, count: (left.count + 1) * width)
        table.withUnsafeMutableBufferPointer { cells in
            var i = 1
            while i <= left.count {
                let token = left[i - 1]
                let row = i * width
                var j = 1
                while j < width {
                    if token == right[j - 1] {
                        cells[row + j] = cells[row - width + j - 1] + 1
                    } else {
                        let above = cells[row - width + j]
                        let before = cells[row + j - 1]
                        cells[row + j] = above > before ? above : before
                    }
                    j += 1
                }
                i += 1
            }
        }
        var i = left.count
        var j = right.count
        while i > 0, j > 0 {
            if left[i - 1] == right[j - 1] {
                removed[i - 1] = true
                added[j - 1] = true
                i -= 1
                j -= 1
            } else if table[(i - 1) * width + j] > table[i * width + j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return (removed, added)
    }

    private static func changed(_ tokens: [Token], kept: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for (index, token) in tokens.enumerated() where !kept[index] {
            if let last = ranges.last, last.upperBound == token.range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound..<token.range.upperBound
            } else {
                ranges.append(token.range)
            }
        }
        return ranges
    }
}
#endif
