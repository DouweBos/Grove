// Views/Settings/GrovePreferences.swift
// Grove
//
// UserDefaults keys and typed accessors for every app preference.

import AppKit
import Foundation

enum GrovePreferences {

    enum Key {
        static let defaultCloneDirectory = "defaultCloneDirectory"
        static let terminalApp = "terminalApp"
        static let autoFetchMinutes = "autoFetchMinutes"
        static let warnOnHunkDiscard = "warnOnHunkDiscard"
        static let staleBranchDays = "staleBranchDays"
        static let appearance = "appearance"
        static let externalEditor = "externalEditorName"
        static let externalEditorPath = "externalEditorPath"
        static let diffToolPath = "externalDiffToolPath"
        static let diffToolArguments = "externalDiffToolArguments"
        static let mergeToolPath = "externalMergeToolPath"
        static let mergeToolArguments = "externalMergeToolArguments"

        static let all = [defaultCloneDirectory, terminalApp, autoFetchMinutes, warnOnHunkDiscard, staleBranchDays,
                          appearance, externalEditor, externalEditorPath, diffToolPath, diffToolArguments,
                          mergeToolPath, mergeToolArguments]
    }

    enum Default {
        static let terminalApp = TerminalApp.terminal.rawValue
        static let autoFetchMinutes = 0
        static let warnOnHunkDiscard = true
        static let staleBranchDays = 90
        static let appearance = AppAppearance.system.rawValue
        static let externalEditor = ExternalEditor.systemDefault.rawValue
    }

    private static var defaults: UserDefaults { .standard }

    /// Minutes between background fetches; 0 means off.
    static var autoFetchMinutes: Int {
        defaults.object(forKey: Key.autoFetchMinutes) as? Int ?? Default.autoFetchMinutes
    }

    /// Whether discarding a hunk or lines asks for confirmation first.
    static var warnOnHunkDiscard: Bool {
        get { defaults.object(forKey: Key.warnOnHunkDiscard) as? Bool ?? Default.warnOnHunkDiscard }
        set { defaults.set(newValue, forKey: Key.warnOnHunkDiscard) }
    }

    /// Days without commits before Branches Review calls a branch stale.
    static var staleBranchDays: Int {
        max(1, defaults.object(forKey: Key.staleBranchDays) as? Int ?? Default.staleBranchDays)
    }

    static var terminalApp: TerminalApp {
        TerminalApp(rawValue: defaults.string(forKey: Key.terminalApp) ?? "") ?? .terminal
    }

    static var externalEditor: ExternalEditor {
        ExternalEditor(rawValue: defaults.string(forKey: Key.externalEditor) ?? "") ?? .systemDefault
    }

    static var externalEditorPath: String? {
        let path = defaults.string(forKey: Key.externalEditorPath) ?? ""
        return path.isEmpty ? nil : path
    }

    @MainActor
    static func resetAll() {
        Key.all.forEach(defaults.removeObject(forKey:))
        AppAppearance.applyStored()
    }
}

// MARK: - Terminal

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iTerm = "iTerm"
    case warp = "Warp"
    case ghostty = "Ghostty"

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

// MARK: - Editor

enum ExternalEditor: String, CaseIterable, Identifiable {
    case systemDefault = "System Default"
    case vscode = "VS Code"
    case cursor = "Cursor"
    case zed = "Zed"
    case sublime = "Sublime Text"
    case xcode = "Xcode"
    case bbedit = "BBEdit"
    case nova = "Nova"
    case custom = "Custom Application"

    var id: String { rawValue }

    var bundleIdentifier: String? {
        switch self {
        case .vscode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .zed: "dev.zed.Zed"
        case .sublime: "com.sublimetext.4"
        case .xcode: "com.apple.dt.Xcode"
        case .bbedit: "com.barebones.bbedit"
        case .nova: "com.panic.Nova"
        case .systemDefault, .custom: nil
        }
    }

    var isInstalled: Bool {
        guard let bundleIdentifier else { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    static func applyStored() {
        // `-GroveAppearance dark|light` wins so both modes can be checked without changing the preference.
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: "GroveAppearance") ?? defaults.string(forKey: GrovePreferences.Key.appearance) ?? ""
        (AppAppearance(rawValue: raw) ?? .system).apply()
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
