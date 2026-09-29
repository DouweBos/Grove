// Utilities/GroveClipboard.swift
// Grove

import AppKit

@MainActor
enum GroveClipboard {
    static func copy(_ string: String, confirmation: String = "Copied") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        ToastCenter.shared.show(confirmation)
    }
}
