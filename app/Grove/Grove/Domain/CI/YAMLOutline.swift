// Domain/CI/YAMLOutline.swift
// Grove
//
// The block-style YAML subset GitHub workflow files are written in, as indented lines. A full YAML parser would be
// a dependency for a few keys, so readers built on this say when a file goes beyond it.

import Foundation

nonisolated enum YAMLOutline {

    struct Line {
        let indent: Int
        let text: Substring
    }

    /// Lines with content, comments removed, with their indentation.
    static func significantLines(_ yaml: String) -> [Line] {
        yaml.split(omittingEmptySubsequences: true) { $0 == "\n" || $0 == "\r\n" }.compactMap { raw in
            let content = withoutComment(raw)
            let text = content.drop { $0 == " " }
            guard !text.allSatisfy(\.isWhitespace), text != "---" else { return nil }
            return Line(indent: content.count - text.count, text: text[...].trimmingSuffix(while: \.isWhitespace))
        }
    }

    /// Cuts a `#` comment that isn't inside quotes; YAML wants whitespace before it.
    static func withoutComment(_ line: Substring) -> Substring {
        var quote: Character?
        var previous: Character = " "
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open, !(open == "\"" && previous == "\\") { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous == " " || previous == "\t" {
                return line[..<index]
            }
            previous = character
        }
        return line
    }

    /// Indices of the lines directly under `parent`: the deeper lines that follow it, at their shallowest indent.
    /// A sequence may sit at its key's own indent, which `includingSequenceItems` allows for.
    static func children(of parent: Int, in lines: [Line], includingSequenceItems: Bool = false) -> [Int] {
        let base = lines[parent].indent
        var block: [Int] = []
        for index in (parent + 1)..<lines.count {
            let line = lines[index]
            guard line.indent > base || (includingSequenceItems && line.indent == base && line.text.hasPrefix("-")) else { break }
            block.append(index)
        }
        guard let shallowest = block.map({ lines[$0].indent }).min() else { return [] }
        return block.filter { lines[$0].indent == shallowest }
    }

    static func entry(_ name: String, among indices: [Int], in lines: [Line]) -> (index: Int, value: Substring)? {
        for index in indices {
            if let (key, value) = key(of: lines[index].text), key == name { return (index, value) }
        }
        return nil
    }

    /// `name: value` → the unquoted name and the trimmed value; nil when the line isn't a mapping entry.
    static func key(of text: Substring) -> (name: String, value: Substring)? {
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let after = text.index(after: index)
                guard after == text.endIndex || text[after] == " " else { continue }
                return (scalar(text[..<index]), text[after...].drop { $0 == " " })
            }
        }
        return nil
    }

    /// `[a, "b c", d]` → its items.
    static func flowSequence(_ value: Substring) -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [scalar(value)] }
        return value.dropFirst().dropLast().split(separator: ",").map { scalar($0) }.filter { !$0.isEmpty }
    }

    /// A plain or quoted scalar's text.
    static func scalar(_ value: Substring) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let quote = trimmed.first, quote == trimmed.last, quote == "\"" || quote == "'" else { return trimmed }
        let inner = String(trimmed.dropFirst().dropLast())
        if quote == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// The index of a top-level key, e.g. `jobs`.
    static func topLevel(_ name: String, in lines: [Line]) -> Int? {
        lines.firstIndex { $0.indent == 0 && key(of: $0.text)?.name == name }
    }

    /// A key's list value: `[a, b]` (also spread over the following lines), a block sequence under it, or a single scalar.
    static func list(_ value: Substring, at index: Int, in lines: [Line]) -> [String] {
        let deeper = lines[(index + 1)...].prefix { $0.indent > lines[index].indent }
        if value.hasPrefix("[") || (value.isEmpty && deeper.first?.text.hasPrefix("[") == true) {
            var flow = String(value)
            for line in deeper where !flow.hasSuffix("]") { flow += " " + line.text }
            return flowSequence(Substring(flow.trimmingCharacters(in: .whitespaces)))
        }
        if !value.isEmpty { return [scalar(value)] }
        return children(of: index, in: lines, includingSequenceItems: true)
            .filter { lines[$0].text.hasPrefix("-") }
            .map { scalar(lines[$0].text.dropFirst()) }
    }
}

private extension Substring {
    nonisolated func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return self[..<end]
    }
}
