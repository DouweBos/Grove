// Domain/RepositoryURLRouter.swift
// Grove
//
// grove://open?path=<folder> URLs, sent by the `grove` command, open that repository in a new tab;
// `view=history|blame|stack` with `branch` or `file` then opens that view once the repository is up.

import AppKit
import Foundation
import GroveKit

/// A view of a repository the `grove` command asks for.
enum RepositoryIntent: Equatable, Sendable {
    case history(branch: String?)
    /// An absolute path in the URL; repository-relative once routed.
    case blame(file: String)
    case stack(branch: String?)
}

@MainActor
enum RepositoryURLRouter {

    /// Opens a repository path in a new tab; set by the first window, since only views can reach `openWindow`.
    static var openHandler: ((String) -> Void)? {
        didSet { flushPending() }
    }

    /// URLs that arrive while launching, before any window can open them.
    private static var pending: [String] = []
    /// Each open session's intent handler, by resolved repository path; false once its session is gone.
    private static var intentHandlers: [String: (RepositoryIntent) -> Bool] = [:]
    /// Intents for repositories whose session isn't up yet.
    private static var pendingIntents: [String: RepositoryIntent] = [:]

    // MARK: - URLs

    nonisolated static func url(opening path: String, intent: RepositoryIntent?) -> URL {
        var components = URLComponents()
        components.scheme = "grove"
        components.host = "open"
        var items = [URLQueryItem(name: "path", value: path)]
        switch intent {
        case .history(let branch):
            items.append(URLQueryItem(name: "view", value: "history"))
            if let branch { items.append(URLQueryItem(name: "branch", value: branch)) }
        case .stack(let branch):
            items.append(URLQueryItem(name: "view", value: "stack"))
            if let branch { items.append(URLQueryItem(name: "branch", value: branch)) }
        case .blame(let file):
            items += [URLQueryItem(name: "view", value: "blame"), URLQueryItem(name: "file", value: file)]
        case nil:
            break
        }
        components.queryItems = items
        return components.url!
    }

    /// The folder in a `grove://open?path=` URL, or nil for anything else.
    nonisolated static func path(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "grove", url.host?.lowercased() == "open",
              let path = query(url, "path"), path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// The view a URL asks for; nil when it names none or one Grove doesn't know.
    nonisolated static func intent(from url: URL) -> RepositoryIntent? {
        switch query(url, "view") {
        case "history": .history(branch: query(url, "branch"))
        case "stack": .stack(branch: query(url, "branch"))
        case "blame": query(url, "file").flatMap { $0.hasPrefix("/") ? .blame(file: $0) : nil }
        default: nil
        }
    }

    private nonisolated static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    /// `file` relative to `root`, comparing resolved paths; nil when it lies outside.
    nonisolated static func relativePath(of file: String, in root: String) -> String? {
        let file = URL(fileURLWithPath: file).resolvingSymlinksInPath().path
        let root = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        guard file.hasPrefix(root + "/") else { return nil }
        return String(file.dropFirst(root.count + 1))
    }

    // MARK: - Handling

    static func handle(_ url: URL) {
        guard let path = path(from: url) else { return }
        let intent = intent(from: url)
        Task {
            // `grove .` in a subfolder opens the repository it belongs to.
            let root = await repositoryRoot(containing: path) ?? path
            if let openHandler { openHandler(root) } else { pending.append(root) }
            switch intent {
            case .blame(let file):
                if let relative = relativePath(of: file, in: root) { deliver(.blame(file: relative), to: root) }
            case let intent?:
                deliver(intent, to: root)
            case nil:
                break
            }
        }
    }

    /// Called by each session as it starts; runs an intent that arrived before it.
    static func setIntentHandler(for repositoryPath: String, _ handler: @escaping (RepositoryIntent) -> Bool) {
        let key = resolved(repositoryPath)
        intentHandlers[key] = handler
        if let intent = pendingIntents.removeValue(forKey: key), !handler(intent) { pendingIntents[key] = intent }
    }

    private static func deliver(_ intent: RepositoryIntent, to root: String) {
        let key = resolved(root)
        if intentHandlers[key]?(intent) != true { pendingIntents[key] = intent }
    }

    private nonisolated static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
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
