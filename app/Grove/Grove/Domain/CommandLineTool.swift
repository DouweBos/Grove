// Domain/CommandLineTool.swift
// Grove
//
// The `grove` shell command (`grove .`, `grove <path>`), which hands a folder to the app as a grove://open URL.

import AppKit
import Foundation

enum CommandLineTool {

    static let name = "grove"
    static let systemDirectory = URL(fileURLWithPath: "/usr/local/bin")
    static var userDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin") }

    /// Uses `open` from PATH and JavaScript's encodeURIComponent via osascript, both on every Mac.
    static let script = """
    #!/bin/sh
    # Opens a folder in Grove: grove [path], the current folder by default.
    target="${1:-.}"
    if [ ! -d "$target" ]; then
      echo "grove: $target is not a folder" >&2
      exit 1
    fi
    folder=$(cd "$target" && pwd -P)
    encoded=$(/usr/bin/osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "$folder")
    exec open "grove://open?path=$encoded"

    """

    enum InstallError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Installation was cancelled."
            case .failed(let detail): detail
            }
        }
    }

    /// Writes the script into a folder the user can write to, e.g. `~/.local/bin`.
    static func install(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try Data(script.utf8).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    /// `/usr/local/bin` needs an administrator: the script is staged in a temporary file and copied with privileges.
    @MainActor
    static func installSystemWide() throws -> URL {
        let staged = try install(in: FileManager.default.temporaryDirectory.appendingPathComponent("grove-cli-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let destination = systemDirectory.appendingPathComponent(name)
        let command = "mkdir -p \(quoted(systemDirectory.path)) && cp \(quoted(staged.path)) \(quoted(destination.path)) "
            + "&& chmod 755 \(quoted(destination.path))"
        let source = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -128 is the user cancelling the password prompt.
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw InstallError.cancelled }
            throw InstallError.failed(error[NSAppleScript.errorMessage] as? String ?? "The command couldn't be installed.")
        }
        return destination
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
