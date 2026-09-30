// Domain/CI/WorkflowDispatchParser.swift
// Grove
//
// Reads `on.workflow_dispatch.inputs` out of a GitHub workflow file, and says when a file goes beyond the YAML subset it reads.

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

    private typealias Line = YAMLOutline.Line

    private struct Unreadable: Error {}

    static func parse(_ yaml: String) -> WorkflowDispatchForm {
        let lines = YAMLOutline.significantLines(yaml)
        guard let on = lines.firstIndex(where: { $0.indent == 0 && ["on", "true"].contains(YAMLOutline.key(of: $0.text)?.name) }),
              let trigger = YAMLOutline.key(of: lines[on].text) else { return .notDispatchable }
        do {
            if !trigger.value.isEmpty { return try inline(trigger.value) }
            let events = YAMLOutline.children(of: on, in: lines)
            guard let first = events.first else { return .notDispatchable }
            if lines[first].text.hasPrefix("-") {
                let names = events.map { YAMLOutline.scalar(lines[$0].text.dropFirst()) }
                return names.contains("workflow_dispatch") ? .inputs([]) : .notDispatchable
            }
            guard let dispatch = YAMLOutline.entry("workflow_dispatch", among: events, in: lines) else { return .notDispatchable }
            guard try isBlock(dispatch.value) else { return .inputs([]) }
            guard let inputs = YAMLOutline.entry("inputs", among: YAMLOutline.children(of: dispatch.index, in: lines), in: lines),
                  try isBlock(inputs.value) else { return .inputs([]) }
            return .inputs(try YAMLOutline.children(of: inputs.index, in: lines).map { try input(at: $0, in: lines) })
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
        let names = value.hasPrefix("[") ? YAMLOutline.flowSequence(value) : [YAMLOutline.scalar(value)]
        return names.contains("workflow_dispatch") ? .inputs([]) : .notDispatchable
    }

    /// Whether a key's value is on the following, deeper lines; throws for inline forms that would hide inputs.
    private static func isBlock(_ value: Substring) throws -> Bool {
        if value.isEmpty { return true }
        if ["{}", "null", "~"].contains(String(value)) { return false }
        throw Unreadable()
    }

    private static func input(at index: Int, in lines: [Line]) throws -> CIDispatchInput {
        guard let (name, value) = YAMLOutline.key(of: lines[index].text) else { throw Unreadable() }
        var input = CIDispatchInput(name: name)
        guard try isBlock(value) else { return input }
        var type = "string"
        var options: [String] = []
        // A sequence written at its key's indent shows up here too; `options` reads it.
        for property in YAMLOutline.children(of: index, in: lines) where !lines[property].text.hasPrefix("-") {
            guard let (key, value) = YAMLOutline.key(of: lines[property].text) else { throw Unreadable() }
            switch key {
            case "description": input.description = try text(value, at: property, in: lines)
            case "default": input.defaultValue = try text(value, at: property, in: lines)
            case "required": input.isRequired = ["true", "yes", "on"].contains(YAMLOutline.scalar(value).lowercased())
            case "type": type = YAMLOutline.scalar(value)
            case "options":
                options = value.isEmpty
                    ? try YAMLOutline.children(of: property, in: lines, includingSequenceItems: true).map { try sequenceItem(lines[$0].text) }
                    : YAMLOutline.flowSequence(value)
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
            return YAMLOutline.scalar(value)
        }
        let body = lines[(index + 1)...].prefix { $0.indent > lines[index].indent }.map { $0.text.trimmingCharacters(in: .whitespaces) }
        return body.joined(separator: marker == "|" ? "\n" : " ")
    }

    private static func sequenceItem(_ text: Substring) throws -> String {
        guard text.hasPrefix("-") else { throw Unreadable() }
        return YAMLOutline.scalar(text.dropFirst())
    }
}
