// Domain/ExternalToolLauncher.swift
// Grove
//
// Launches external diff, merge, and editor tools configured in preferences.
// Defaults to opendiff (FileMerge) for diff/merge when no tool is configured.
//
// UserDefaults keys match those written by EditorPreferencesTab.

import AppKit
import Foundation
import os

// MARK: - ExternalToolLauncherError

/// Errors thrown by ``ExternalToolLauncher``.
enum ExternalToolLauncherError: LocalizedError {
    case toolNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let path):
            return "External tool not found at '\(path)'."
        case .launchFailed(let detail):
            return "Failed to launch external tool: \(detail)"
        }
    }
}

// MARK: - ExternalToolLauncher

/// Launches the user-configured external diff, merge, and editor tools.
///
/// All methods fall back to sensible defaults when no path is configured:
/// - Diff/merge: `opendiff` (macOS FileMerge)
/// - Editor: `open` with the default app for the file type
///
/// Tool paths and argument templates are read from ``AppToolPreferences``.
@MainActor
final class ExternalToolLauncher {

    // MARK: - Diff Tool

    /// Launch the configured external diff tool for two files.
    ///
    /// - Parameters:
    ///   - oldFile: URL of the left/old version.
    ///   - newFile: URL of the right/new version.
    ///   - toolPath: Absolute path to the diff tool. `nil` uses `opendiff`.
    static func launchDiffTool(oldFile: URL, newFile: URL, toolPath: String?) throws {
        let path = resolvedToolPath(toolPath, defaultPath: "/usr/bin/opendiff")
        Logger.ui.info("Launching diff tool '\(path, privacy: .public)' for \(newFile.lastPathComponent, privacy: .public)")

        let args = AppToolPreferences.diffArguments
            .replacingTokens(["$LOCAL": oldFile.path, "$REMOTE": newFile.path])

        try launch(executablePath: path, arguments: args)
    }

    // MARK: - Merge Tool

    /// Launch the configured external merge tool for a conflict.
    ///
    /// - Parameters:
    ///   - base: URL of the common ancestor (base) version.
    ///   - ours: URL of the local HEAD (ours) version.
    ///   - theirs: URL of the incoming (theirs) version.
    ///   - merged: URL of the output file where the merge result is written.
    ///   - toolPath: Absolute path to the merge tool. `nil` uses `opendiff`.
    static func launchMergeTool(
        base: URL,
        ours: URL,
        theirs: URL,
        merged: URL,
        toolPath: String?
    ) throws {
        let path = resolvedToolPath(toolPath, defaultPath: "/usr/bin/opendiff")
        Logger.ui.info("Launching merge tool '\(path, privacy: .public)' for \(merged.lastPathComponent, privacy: .public)")

        let args = AppToolPreferences.mergeArguments
            .replacingTokens([
                "$LOCAL": ours.path,
                "$REMOTE": theirs.path,
                "$BASE": base.path,
                "$MERGED": merged.path
            ])

        try launch(executablePath: path, arguments: args)
    }

    // MARK: - Editor

    /// Launch the configured external editor for a file.
    ///
    /// - Parameters:
    ///   - file: URL of the file to open.
    ///   - editorPath: Absolute path to the editor executable. `nil` uses
    ///     `NSWorkspace` to open with the default app.
    static func launchEditor(file: URL, editorPath: String?) throws {
        if let editorPath, !editorPath.isEmpty {
            Logger.ui.info("Launching editor '\(editorPath, privacy: .public)' for \(file.lastPathComponent, privacy: .public)")
            try launch(executablePath: editorPath, arguments: [file.path])
        } else {
            // Fall back to the system default app.
            Logger.ui.info("Opening \(file.lastPathComponent, privacy: .public) with default app")
            NSWorkspace.shared.open(file)
        }
    }

    // MARK: - Private Helpers

    /// Resolve the effective tool path, falling back to `defaultPath` when
    /// `configured` is `nil` or empty.
    private static func resolvedToolPath(
        _ configured: String?,
        defaultPath: String
    ) -> String {
        guard let configured, !configured.isEmpty else { return defaultPath }
        return configured
    }

    /// Split an argument string into individual arguments and launch the process.
    ///
    /// The argument string is split on whitespace (quotes not supported — the
    /// paths are passed through token substitution and contain no spaces in
    /// the template slots).
    private static func launch(executablePath: String, arguments: [String]) throws {
        guard FileManager.default.fileExists(atPath: executablePath) ||
              executablePath == "/usr/bin/opendiff" else {
            throw ExternalToolLauncherError.toolNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["LANG"]   = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env

        do {
            try process.run()
            // opendiff and similar GUI tools detach immediately; no need to wait.
        } catch {
            Logger.ui.error("Failed to launch '\(executablePath, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw ExternalToolLauncherError.launchFailed(error.localizedDescription)
        }
    }
}

// MARK: - AppToolPreferences

/// Reads tool paths and argument templates from `UserDefaults`.
///
/// `EditorPreferencesTab` writes these keys when the user changes preferences.
enum AppToolPreferences {

    // MARK: UserDefaults Keys

    private static let diffToolPathKey       = "externalDiffToolPath"
    private static let diffToolArgsKey       = "externalDiffToolArguments"
    private static let mergeToolPathKey      = "externalMergeToolPath"
    private static let mergeToolArgsKey      = "externalMergeToolArguments"
    private static let editorPathKey         = "externalEditorPath"

    // MARK: Accessors

    /// Path to the configured external diff tool, or `nil` when unset.
    static var diffToolPath: String? {
        let path = UserDefaults.standard.string(forKey: diffToolPathKey) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Argument template for the diff tool.
    ///
    /// Tokens: `$LOCAL` (old file), `$REMOTE` (new file).
    static var diffArguments: String {
        UserDefaults.standard.string(forKey: diffToolArgsKey) ?? "$LOCAL $REMOTE"
    }

    /// Path to the configured external merge tool, or `nil` when unset.
    static var mergeToolPath: String? {
        let path = UserDefaults.standard.string(forKey: mergeToolPathKey) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Argument template for the merge tool.
    ///
    /// Tokens: `$LOCAL`, `$REMOTE`, `$BASE`, `$MERGED`.
    static var mergeArguments: String {
        UserDefaults.standard.string(forKey: mergeToolArgsKey)
            ?? "$LOCAL $REMOTE $BASE $MERGED"
    }

    /// Path to the configured external editor, or `nil` when unset.
    static var editorPath: String? {
        let path = UserDefaults.standard.string(forKey: editorPathKey) ?? ""
        return path.isEmpty ? nil : path
    }
}

// MARK: - String+replacingTokens

private extension String {

    /// Split on whitespace and substitute token placeholders in each component.
    func replacingTokens(_ tokens: [String: String]) -> [String] {
        components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { component in
                tokens.reduce(component) { acc, pair in
                    acc.replacingOccurrences(of: pair.key, with: pair.value)
                }
            }
    }
}
