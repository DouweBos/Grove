// Domain/RepositoryURLRouter.swift
// Grove
//
// grove://open?path=<folder> URLs, sent by the `grove` command, open that repository in a new tab.

import AppKit
import Foundation

@MainActor
enum RepositoryURLRouter {

    /// Opens a repository path in a new tab; set by the first window, since only views can reach `openWindow`.
    static var openHandler: ((String) -> Void)? {
        didSet { flushPending() }
    }

    /// URLs that arrive while launching, before any window can open them.
    private static var pending: [String] = []

    /// The folder in a `grove://open?path=` URL, or nil for anything else.
    nonisolated static func path(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "grove", url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value, path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func handle(_ url: URL) {
        guard let path = path(from: url) else { return }
        Task {
            // `grove .` in a subfolder opens the repository it belongs to.
            let root = await repositoryRoot(containing: path) ?? path
            if let openHandler { openHandler(root) } else { pending.append(root) }
        }
    }

    nonisolated static func repositoryRoot(containing path: String) async -> String? {
        let shell = GitShell(workingDirectory: URL(fileURLWithPath: path))
        guard let result = try? await shell.runAllowingFailure(["rev-parse", "--show-toplevel"]), result.isSuccess else { return nil }
        let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    private static func flushPending() {
        guard let openHandler, !pending.isEmpty else { return }
        let paths = pending
        pending = []
        paths.forEach(openHandler)
    }
}

extension GroveAppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(RepositoryURLRouter.handle)
    }
}
