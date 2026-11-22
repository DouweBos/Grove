// Environment/GitUIHost.swift
// GroveUIKit
//
// What only the app around the kit can do.

#if os(macOS)
import AppKit
import SwiftUI

public nonisolated struct GitUIHost: Sendable {
    public var copy: @MainActor @Sendable (String) -> Void
    /// Says a copy or the like happened.
    public var toast: @MainActor @Sendable (String) -> Void
    /// Opens a file at a 1-based line of its current version; nil offers no way to.
    public var openFile: (@MainActor @Sendable (_ path: String, _ line: Int?) -> Void)?

    public init(copy: @escaping @MainActor @Sendable (String) -> Void = GitUIHost.copyToPasteboard,
                toast: @escaping @MainActor @Sendable (String) -> Void = { _ in },
                openFile: (@MainActor @Sendable (_ path: String, _ line: Int?) -> Void)? = nil) {
        self.copy = copy
        self.toast = toast
        self.openFile = openFile
    }

    /// Plain copy and nothing else, for previews and an app that hasn't set a host.
    public static let system = GitUIHost()

    @MainActor public static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension View {
    /// What the kit's copy, toast and open actions do, for every kit view below.
    public func gitUIHost(_ host: GitUIHost) -> some View {
        environment(\.gitHost, host)
    }
}
#endif
