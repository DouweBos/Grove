// Components/SavePanel.swift
// Grove

import AppKit
import UniformTypeIdentifiers

/// Asks where to save an export; nil when cancelled.
@MainActor
enum SavePanel {
    static func choose(name: String, message: String, prompt: String = "Save", type: UTType? = nil) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.message = message
        panel.prompt = prompt
        panel.canCreateDirectories = true
        if let type { panel.allowedContentTypes = [type] }
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    /// A file-name-safe version of a commit subject or ref name.
    static func slug(_ text: String, limit: Int = 50) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let words = text.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return String(words.joined(separator: "-").prefix(limit))
    }
}
