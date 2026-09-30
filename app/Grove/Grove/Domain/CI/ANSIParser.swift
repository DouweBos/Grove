// Domain/CI/ANSIParser.swift
// Grove
//
// Terminal escape sequences in CI logs.

import Foundation

nonisolated enum ANSIParser {

    /// `text` without its escape sequences.
    static func strip(_ text: String) -> String {
        guard text.utf8.contains(0x1B) else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var rest = text[...]
        while let escape = rest.firstIndex(of: "\u{1B}") {
            result += rest[..<escape]
            rest = rest[sequenceEnd(in: rest, from: escape)...]
        }
        return result + rest
    }

    /// The index after the escape sequence starting at `escape`: `ESC [ … <letter>`, or the lone `ESC`.
    static func sequenceEnd(in text: Substring, from escape: Substring.Index) -> Substring.Index {
        var index = text.index(after: escape)
        guard index < text.endIndex, text[index] == "[" else { return index }
        index = text.index(after: index)
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if character.isLetter { break }
        }
        return index
    }
}
