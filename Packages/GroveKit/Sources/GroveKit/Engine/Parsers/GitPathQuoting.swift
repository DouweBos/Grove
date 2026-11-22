// Engine/Parsers/GitPathQuoting.swift
// GroveKit
//
// The C-style quoting git uses for paths in its output and in patch headers.

import Foundation

nonisolated enum GitPathQuoting {

    private static let escapes: [(letter: UInt8, byte: UInt8)] = [
        (UInt8(ascii: "a"), 7), (UInt8(ascii: "b"), 8), (UInt8(ascii: "t"), 9), (UInt8(ascii: "n"), 10),
        (UInt8(ascii: "v"), 11), (UInt8(ascii: "f"), 12), (UInt8(ascii: "r"), 13),
        (UInt8(ascii: "\""), UInt8(ascii: "\"")), (UInt8(ascii: "\\"), UInt8(ascii: "\\")),
    ]

    /// The path `field` names; a field that isn't quoted, or isn't UTF-8 once unquoted, comes back as it is.
    static func unquote(_ field: String) -> String {
        guard let token = leadingToken(of: field), token.rest.isEmpty else { return field }
        return token.path
    }

    /// The quoted path `text` starts with, and what follows it.
    static func leadingToken(of text: String) -> (path: String, rest: String)? {
        let source = Array(text.utf8)
        guard source.first == UInt8(ascii: "\"") else { return nil }
        var bytes: [UInt8] = []
        var index = 1
        while index < source.count {
            let byte = source[index]
            index += 1
            if byte == UInt8(ascii: "\"") {
                guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
                return (path, String(decoding: source[index...], as: UTF8.self))
            }
            guard byte == UInt8(ascii: "\\") else {
                bytes.append(byte)
                continue
            }
            guard index < source.count else { return nil }
            if let escape = escapes.first(where: { $0.letter == source[index] }) {
                bytes.append(escape.byte)
                index += 1
            } else {
                guard index + 3 <= source.count,
                      let value = UInt8(String(decoding: source[index..<index + 3], as: UTF8.self), radix: 8) else { return nil }
                bytes.append(value)
                index += 3
            }
        }
        return nil
    }

    /// Quotes spaces too, which leaves no doubt about where a name ends in a patch header.
    static func quote(_ path: String) -> String {
        let needsQuotes = path.utf8.contains { $0 <= 0x20 || $0 >= 0x7F || $0 == UInt8(ascii: "\"") || $0 == UInt8(ascii: "\\") }
        guard needsQuotes else { return path }
        var quoted = "\""
        for byte in path.utf8 {
            if let escape = escapes.first(where: { $0.byte == byte }) {
                quoted += "\\" + String(UnicodeScalar(escape.letter))
            } else if byte < 0x20 || byte >= 0x7F {
                let octal = String(byte, radix: 8)
                quoted += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
            } else {
                quoted += String(UnicodeScalar(byte))
            }
        }
        return quoted + "\""
    }
}
