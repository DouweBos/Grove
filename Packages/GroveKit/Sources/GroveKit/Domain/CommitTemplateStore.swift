// Domain/CommitTemplateStore.swift
// GroveKit
//
// Commit message templates used by the commit composer; the app persists them.

import Foundation
import Observation

public struct CommitTemplate: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var summary: String
    public var body: String = ""
}

@MainActor
@Observable
public final class CommitTemplateStore {

    public private(set) var templates: [CommitTemplate]
    @ObservationIgnored private let persist: ([CommitTemplate]) -> Void

    /// The app decides where templates live; without `load`/`save` they're kept in memory only.
    public init(load: () -> [CommitTemplate]? = { nil }, save: @escaping ([CommitTemplate]) -> Void = { _ in }) {
        templates = load() ?? Self.defaults
        persist = save
    }

    @discardableResult
    public func add() -> CommitTemplate {
        let template = CommitTemplate(name: "New Template", summary: "")
        templates.append(template)
        persist(templates)
        return template
    }

    public func update(_ template: CommitTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }), templates[index] != template else { return }
        templates[index] = template
        persist(templates)
    }

    public func delete(_ id: CommitTemplate.ID) {
        templates.removeAll { $0.id == id }
        persist(templates)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { templates[$0] }
        for index in source.reversed() { templates.remove(at: index) }
        templates.insert(contentsOf: moving, at: destination - source.count(in: 0..<destination))
        persist(templates)
    }

    public func resetToDefaults() {
        templates = Self.defaults
        persist(templates)
    }

    /// Conventional Commits prefixes, so the `/` autocomplete has something before any are added.
    static let defaults: [CommitTemplate] = [
        ("feat", "New Feature"), ("fix", "Bug Fix"), ("docs", "Documentation"), ("style", "Formatting"),
        ("refactor", "Refactoring"), ("test", "Tests"), ("chore", "Maintenance"), ("perf", "Performance"), ("ci", "CI/CD")
    ].map { CommitTemplate(name: "\($0.0): \($0.1)", summary: "\($0.0): ") }
}

extension CommitTemplate {
    /// A git `commit.template` file: `#` lines dropped, first line as summary, the rest after it as description.
    init?(gitTemplate text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.hasPrefix("#") }
        let trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(id: Self.gitTemplateID, name: "Git Template (commit.template)", summary: String(parts[0]),
                  body: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
    }

    public static let gitTemplateID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
}
