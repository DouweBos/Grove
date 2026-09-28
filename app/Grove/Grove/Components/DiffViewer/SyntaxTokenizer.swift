// Components/DiffViewer/SyntaxTokenizer.swift
// Grove
//
// A single-pass lexer that finds keyword, string, comment, number and type spans in one line of code.

import Foundation

enum SyntaxKind: Hashable, Sendable {
    case keyword, string, comment, number, type
}

/// `range` counts Characters, so it lines up with the diff line's AttributedString.
struct SyntaxSpan: Hashable, Sendable {
    let range: Range<Int>
    let kind: SyntaxKind
}

struct SyntaxTokenizer {

    /// What an unfinished construct carries into the next line.
    enum State: Hashable, Sendable {
        case normal
        case blockComment
        case multilineString(String)
    }

    let language: SyntaxLanguage
    /// Longer lines (minified code, data) stay plain so one line can't stall the diff.
    static let maxLineLength = 2_000

    // swiftlint:disable:next cyclomatic_complexity
    func tokenize(_ line: String, state: inout State) -> [SyntaxSpan] {
        let chars = Array(line)
        guard chars.count <= Self.maxLineLength else { return [] }
        var spans: [SyntaxSpan] = []
        var index = 0

        switch state {
        case .normal: break
        case .blockComment:
            guard let close = language.blockComment?.close else { state = .normal; break }
            index = scanClose(close, in: chars, from: 0, state: &state, closedState: .normal)
            spans.append(SyntaxSpan(range: 0..<index, kind: .comment))
        case .multilineString(let delimiter):
            index = scanClose(delimiter, in: chars, from: 0, state: &state, closedState: .normal)
            spans.append(SyntaxSpan(range: 0..<index, kind: .string))
        }

        while index < chars.count, state == .normal {
            if language.lineComments.contains(where: { matches($0, chars, at: index) }) {
                spans.append(SyntaxSpan(range: index..<chars.count, kind: .comment))
                break
            }
            if let block = language.blockComment, matches(block.open, chars, at: index) {
                state = .blockComment
                let end = scanClose(block.close, in: chars, from: index + block.open.count, state: &state, closedState: .normal)
                spans.append(SyntaxSpan(range: index..<end, kind: .comment))
                index = end
                continue
            }
            if let delimiter = language.multilineQuotes.first(where: { matches($0, chars, at: index) }) {
                state = .multilineString(delimiter)
                let end = scanClose(delimiter, in: chars, from: index + delimiter.count, state: &state, closedState: .normal)
                spans.append(SyntaxSpan(range: index..<end, kind: .string))
                index = end
                continue
            }
            let char = chars[index]
            if language.quotes.contains(char) {
                let end = scanString(quote: char, in: chars, from: index + 1)
                spans.append(SyntaxSpan(range: index..<end, kind: .string))
                index = end
            } else if char.isNumber, index == 0 || !isIdentifier(chars[index - 1]) {
                var end = index + 1
                while end < chars.count, isIdentifier(chars[end]) || chars[end] == "." && end + 1 < chars.count && chars[end + 1].isNumber {
                    end += 1
                }
                spans.append(SyntaxSpan(range: index..<end, kind: .number))
                index = end
            } else if isIdentifierStart(char, next: index + 1 < chars.count ? chars[index + 1] : nil) {
                var end = index + 1
                while end < chars.count, isIdentifier(chars[end]) { end += 1 }
                let word = String(chars[index..<end])
                if isKeyword(word) {
                    spans.append(SyntaxSpan(range: index..<end, kind: .keyword))
                } else if language.capitalizedTypes, let first = word.first(where: { $0 != "@" }), first.isUppercase {
                    spans.append(SyntaxSpan(range: index..<end, kind: .type))
                }
                index = end
            } else {
                index += 1
            }
        }
        return spans
    }

    // MARK: Scanning

    /// Index just past `close`, or the line's end with `state` left open.
    private func scanClose(_ close: String, in chars: [Character], from start: Int, state: inout State, closedState: State) -> Int {
        var index = start
        while index < chars.count {
            if chars[index] == "\\", case .multilineString = state {
                index += 2
                continue
            }
            if matches(close, chars, at: index) {
                state = closedState
                return index + close.count
            }
            index += 1
        }
        return chars.count
    }

    /// Single-line strings end at the matching quote or, unterminated, at the end of the line.
    private func scanString(quote: Character, in chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count {
            if chars[index] == "\\" {
                index += 2
                continue
            }
            if chars[index] == quote { return index + 1 }
            index += 1
        }
        return chars.count
    }

    private func matches(_ token: String, _ chars: [Character], at index: Int) -> Bool {
        var offset = index
        for char in token {
            guard offset < chars.count, chars[offset] == char else { return false }
            offset += 1
        }
        return true
    }

    private func isKeyword(_ word: String) -> Bool {
        language.keywords.contains(word) || (language.caseInsensitiveKeywords && language.keywords.contains(word.lowercased()))
    }

    private func isIdentifierStart(_ char: Character, next: Character?) -> Bool {
        if char.isLetter || char == "_" || char == "$" { return true }
        return char == "@" && next?.isLetter == true
    }

    private func isIdentifier(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "$"
    }
}
