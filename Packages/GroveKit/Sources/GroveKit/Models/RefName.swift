// Models/RefName.swift
// GroveKit

import Foundation

/// Names for branches, tags and remotes, as git accepts them.
public nonisolated enum RefName {

    /// Mirrors the common `git check-ref-format` rules closely enough for inline validation.
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
              !name.hasSuffix("."), !name.hasSuffix(".lock"), !name.contains(".."), !name.contains("@{"),
              !name.contains("//") else { return false }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\").union(.controlCharacters)
        return name.unicodeScalars.allSatisfy { !forbidden.contains($0) }
    }
}
