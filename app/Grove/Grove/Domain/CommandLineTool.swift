// Domain/CommandLineTool.swift
// Grove
//
// Installs the `grove` command as a link to the script inside Grove.app, so it follows Grove through updates,
// and tells Grove's own links and old copies apart from a `grove` that belongs to someone else.

import AppKit
import Foundation

enum CommandLineTool {

    static let name = "grove"
    static let systemDirectory = URL(fileURLWithPath: "/usr/local/bin")
    static var userDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin") }
    static var directories: [URL] { [systemDirectory, userDirectory] }

    /// The script in this copy of Grove that installed links point at.
    static var bundledScript: URL? { Bundle.main.url(forResource: name, withExtension: nil) }

    /// A line every script Grove wrote before it installed links; nothing else carries it.
    static let legacyMarker = "# Opens a folder in Grove: grove [path]"

    /// What's at an install location.
    enum Installation: Equatable {
        case missing
        /// A link to this copy of Grove.
        case current
        /// A link to Grove's script somewhere else: a moved or renamed Grove when that's gone, else another copy.
        case otherGrove(target: String, exists: Bool)
        /// A script Grove copied there before it installed links; it never updates.
        case outdatedCopy
        /// A link someone made to something that isn't Grove.
        case userLink(target: String)
        /// Another program's file.
        case foreign

        /// Grove put it there, so updating or repairing it replaces nothing of anyone else's.
        var isGroves: Bool {
            switch self {
            case .current, .otherGrove, .outdatedCopy: true
            case .missing, .userLink, .foreign: false
            }
        }
    }

    static func installation(at url: URL, script: URL? = bundledScript) -> Installation {
        let fileManager = FileManager.default
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            let target = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            if let script, target.resolvingSymlinksInPath().path == script.resolvingSymlinksInPath().path { return .current }
            if target.path.hasSuffix(".app/Contents/Resources/\(name)") {
                return .otherGrove(target: target.path, exists: fileManager.fileExists(atPath: target.path))
            }
            return .userLink(target: target.path)
        }
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return contents.contains(legacyMarker) ? .outdatedCopy : .foreign
    }

    enum InstallError: LocalizedError, Equatable {
        case cancelled
        case missingScript
        /// Something Grove didn't put there; replacing it takes the user's say-so.
        case occupied(URL, Installation)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Installation was cancelled."
            case .missingScript: "This copy of Grove doesn't include the command line tool."
            case .occupied(let url, _): "\(url.path) already exists."
            case .failed(let detail): detail
            }
        }
    }

    /// Links `<directory>/grove` to the bundled script; replaces only Grove's own unless `replacing` is set.
    @discardableResult
    static func install(in directory: URL, script: URL? = bundledScript, replacing: Bool = false) throws -> URL {
        guard let script else { throw InstallError.missingScript }
        let destination = directory.appendingPathComponent(name)
        let existing = installation(at: destination, script: script)
        if !existing.isGroves, existing != .missing, !replacing { throw InstallError.occupied(destination, existing) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if existing != .missing { try fileManager.removeItem(at: destination) }
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: script)
        return destination
    }

    /// `/usr/local/bin` needs an administrator, so the link is made through a privileged shell.
    @MainActor
    @discardableResult
    static func installSystemWide(replacing: Bool = false) throws -> URL {
        guard let script = bundledScript else { throw InstallError.missingScript }
        let destination = systemDirectory.appendingPathComponent(name)
        let existing = installation(at: destination, script: script)
        if !existing.isGroves, existing != .missing, !replacing { throw InstallError.occupied(destination, existing) }
        if existing == .current { return destination }
        let command = "mkdir -p \(quoted(systemDirectory.path)) && rm -f \(quoted(destination.path)) "
            + "&& ln -s \(quoted(script.path)) \(quoted(destination.path))"
        let source = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -128 is the user cancelling the password prompt.
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw InstallError.cancelled }
            throw InstallError.failed(error[NSAppleScript.errorMessage] as? String ?? "The command couldn't be installed.")
        }
        guard installation(at: destination, script: script) == .current else {
            throw InstallError.failed("The command couldn't be installed at \(destination.path).")
        }
        return destination
    }

    /// Installs into `directory`, asking for an administrator where the user can't write.
    @MainActor
    @discardableResult
    static func install(into directory: URL, replacing: Bool = false) throws -> URL {
        directory == systemDirectory ? try installSystemWide(replacing: replacing) : try install(in: directory, replacing: replacing)
    }

    /// The first install location holding anything, for Settings to describe; nil when there's none.
    static func existingInstallation() -> (url: URL, installation: Installation)? {
        for directory in directories {
            let url = directory.appendingPathComponent(name)
            let found = installation(at: url)
            if found != .missing { return (url, found) }
        }
        return nil
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
