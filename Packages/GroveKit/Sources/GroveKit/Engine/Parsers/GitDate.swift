// Engine/Parsers/GitDate.swift
// GroveKit

import Foundation

/// ISO 8601 dates as git (`%aI`, `iso-strict`) and GitHub print them.
public nonisolated enum GitDate {
    // Format styles are Sendable and parse ~100x faster than ISO8601DateFormatter, which matters for thousands of tags.
    private static let plain = Date.ISO8601FormatStyle()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (try? plain.parse(trimmed)) ?? (try? fractional.parse(trimmed))
    }
}
