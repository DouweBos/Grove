// Domain/CI/WorkflowDispatchParser.swift
// Grove
//
// Reads `on.workflow_dispatch.inputs` out of a GitHub workflow file. A full YAML parser would be a dependency
// for one block, so this reads the block-style subset workflows are written in and says when a file goes beyond it.

import Foundation

/// What a workflow file says about starting it by hand.
nonisolated enum WorkflowDispatchForm: Hashable, Sendable {
    /// No `workflow_dispatch` trigger.
    case notDispatchable
    case inputs([CIDispatchInput])
    /// The trigger is there, but its inputs are written in YAML this reader doesn't cover.
    case unreadable
}

nonisolated enum WorkflowDispatchParser {

    private struct Line {
        let indent: Int
        let text: Substring
    }

    private struct Unreadable: Error {}

    static func parse(_ yaml: String) -> WorkflowDispatchForm {
        let lines = significantLines(yaml)
        guard let on = lines.firstIndex(where: { $0.indent == 0 && ["on", "true"].contains(key(of: $0.text)?.name) }),
              let trigger = key(of: lines[on].text) else { return .notDispatchable }
        do {
            if !trigger.value.isEmpty { return try inline(trigger.value) }
            let events = children(of: on, in: lines)
            guard let first = events.first else { return .notDispatchable }
            if lines[first].text.hasPrefix("-") {
                let names = events.map { scalar(lines[$0].text.dropFirst()) }
                return names.contains("workflow_dispatch") ? .inputs([]) : .notDispatchable
            }
            guard let dispatch = entry("workflow_dispatch", among: events, in: lines) else { return .notDispatchable }
            guard try isBlock(dispatch.value) else { return .inputs([]) }
            guard let inputs = entry("inputs", among: children(of: dispatch.index, in: lines), in: lines),
                  try isBlock(inputs.value) else { return .inputs([]) }
            return .inputs(try children(of: inputs.index, in: lines).map { try input(at: $0, in: lines) })
        } catch {
            return .unreadable
        }
    }

    // MARK: - Structure

    /// `on: workflow_dispatch`, `on: [push, workflow_dispatch]`; a flow mapping may hold inputs this reader can't see.
    private static func inline(_ value: Substring) throws -> WorkflowDispatchForm {
        if value.hasPrefix("{") {
            guard value.contains("workflow_dispatch") else { return .notDispatchable }
            throw Unreadable()
        }
        let names = value.hasPrefix("[") ? flowSequence(value) : [scalar(value)]
        return names.contains("workflow_dispatch") ? .inputs([]) : .notDispatchable
    }

    /// Whether a key's value is on the following, deeper lines; throws for inline forms that would hide inputs.
    private static func isBlock(_ value: Substring) throws -> Bool {
        if value.isEmpty { return true }
        if ["{}", "null", "~"].contains(String(value)) { return false }
        throw Unreadable()
    }

    private static func input(at index: Int, in lines: [Line]) throws -> CIDispatchInput {
        guard let (name, value) = key(of: lines[index].text) else { throw Unreadable() }
        var input = CIDispatchInput(name: name)
        guard try isBlock(value) else { return input }
        var type = "string"
        var options: [String] = []
        // A sequence written at its key's indent shows up here too; `options` reads it.
        for property in children(of: index, in: lines) where !lines[property].text.hasPrefix("-") {
            guard let (key, value) = key(of: lines[property].text) else { throw Unreadable() }
            switch key {
            case "description": input.description = try text(value, at: property, in: lines)
            case "default": input.defaultValue = try text(value, at: property, in: lines)
            case "required": input.isRequired = ["true", "yes", "on"].contains(scalar(value).lowercased())
            case "type": type = scalar(value)
            case "options":
                options = value.isEmpty
                    ? try children(of: property, in: lines, includingSequenceItems: true).map { try sequenceItem(lines[$0].text) }
                    : flowSequence(value)
            default: break
            }
        }
        switch type {
        case "boolean":
            input.kind = .boolean
            input.defaultValue = input.defaultValue.lowercased() == "true" ? "true" : "false"
        case "number": input.kind = .number
        case "environment": input.kind = .environment
        case "choice":
            input.kind = .choice(options)
            if input.defaultValue.isEmpty { input.defaultValue = options.first ?? "" }
        default: input.kind = .string
        }
        return input
    }

    /// A scalar, or a block scalar (`|`, `>`) read from the deeper lines that follow.
    private static func text(_ value: Substring, at index: Int, in lines: [Line]) throws -> String {
        guard let marker = value.first, marker == "|" || marker == ">" else {
            if value.hasPrefix("*") || value.hasPrefix("&") { throw Unreadable() }
            return scalar(value)
        }
        let body = lines[(index + 1)...].prefix { $0.indent > lines[index].indent }.map { $0.text.trimmingCharacters(in: .whitespaces) }
        return body.joined(separator: marker == "|" ? "\n" : " ")
    }

    private static func sequenceItem(_ text: Substring) throws -> String {
        guard text.hasPrefix("-") else { throw Unreadable() }
        return scalar(text.dropFirst())
    }

    // MARK: - Lines

    /// Lines with content, comments removed, with their indentation.
    private static func significantLines(_ yaml: String) -> [Line] {
        yaml.split(omittingEmptySubsequences: true) { $0 == "\n" || $0 == "\r\n" }.compactMap { raw in
            let content = withoutComment(raw)
            let text = content.drop { $0 == " " }
            guard !text.allSatisfy(\.isWhitespace), text != "---" else { return nil }
            return Line(indent: content.count - text.count, text: text[...].trimmingSuffix(while: \.isWhitespace))
        }
    }

    /// Cuts a `#` comment that isn't inside quotes; YAML wants whitespace before it.
    private static func withoutComment(_ line: Substring) -> Substring {
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
    private static func children(of parent: Int, in lines: [Line], includingSequenceItems: Bool = false) -> [Int] {
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

    private static func entry(_ name: String, among indices: [Int], in lines: [Line]) -> (index: Int, value: Substring)? {
        for index in indices {
            if let (key, value) = key(of: lines[index].text), key == name { return (index, value) }
        }
        return nil
    }

    /// `name: value` → the unquoted name and the trimmed value; nil when the line isn't a mapping entry.
    private static func key(of text: Substring) -> (name: String, value: Substring)? {
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
    private static func flowSequence(_ value: Substring) -> [String] {
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
}

private extension Substring {
    nonisolated func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) { end = index(before: end) }
        return self[..<end]
    }
}
