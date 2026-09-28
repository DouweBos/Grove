// Domain/Gitmoji.swift
// Grove
//
// The gitmoji.dev list, bundled as Resources/Gitmojis.json so the composer works offline.

import Foundation

struct Gitmoji: Decodable, Hashable, Identifiable, Sendable {
    let emoji: String
    /// `:sparkles:`, what the `:` autocomplete matches.
    let code: String
    let description: String

    var id: String { code }

    static let all: [Gitmoji] = {
        guard let url = Bundle.main.url(forResource: "Gitmojis", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Gitmoji].self, from: data)) ?? []
    }()

    /// Code matches first, then description matches; `query` is what follows the `:`.
    static func search(_ query: String, in list: [Gitmoji] = all) -> [Gitmoji] {
        let query = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !query.isEmpty else { return list }
        let byCode = list.filter { $0.code.contains(query) }
        let byDescription = list.filter { !$0.code.contains(query) && $0.description.lowercased().contains(query) }
        return byCode + byDescription
    }

    /// Puts `gitmoji` at the start of a summary, replacing a gitmoji already there.
    static func prefixing(_ summary: String, with gitmoji: Gitmoji, in list: [Gitmoji] = all) -> String {
        var rest = Substring(summary)
        if let existing = list.first(where: { rest.hasPrefix($0.emoji) }) {
            rest = rest.dropFirst(existing.emoji.count)
        }
        let trimmed = rest.drop { $0 == " " }
        return gitmoji.emoji + " " + trimmed
    }
}
