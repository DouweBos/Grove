// Commands/CommandLineToolCommands.swift
// Grove

import AppKit
import SwiftUI

/// Grove > Install Command Line Tool…, under About.
struct CommandLineToolCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Install Command Line Tool\u{2026}") { CommandLineToolInstaller.run() }
        }
    }
}

/// Asks where to install `grove`, installs it, and reports how it went.
@MainActor
enum CommandLineToolInstaller {

    static func run() {
        let alert = NSAlert()
        alert.messageText = "Install the \u{201C}grove\u{201D} Command"
        alert.informativeText = "Opens repositories in Grove from Terminal and prints their stacks, branches and pull requests. "
            + "Run \u{201C}grove help\u{201D} for everything it does. It's installed as a link to Grove, so it stays up to date.\n\n"
            + "/usr/local/bin is on every shell's PATH and needs an administrator password. "
            + "~/.local/bin needs no password but has to be on your PATH."
        alert.addButton(withTitle: "Install in /usr/local/bin")
        alert.addButton(withTitle: "Install in ~/.local/bin")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(into: CommandLineTool.systemDirectory)
        case .alertSecondButtonReturn: install(into: CommandLineTool.userDirectory)
        default: return
        }
    }

    /// Installs, updates or repairs; a `grove` Grove didn't put there is left alone or replaced only on request.
    static func install(into directory: URL, replacing: Bool = false) {
        do {
            let installed = try CommandLineTool.install(into: directory, replacing: replacing)
            let pathHint = directory == CommandLineTool.userDirectory ? " If the shell can't find it, add ~/.local/bin to your PATH." : ""
            report(title: "Command Line Tool Installed",
                   message: "\u{201C}grove\u{201D} is at \(abbreviatingHome(installed.path)). "
                       + "Run \u{201C}grove .\u{201D} in a repository to open it, or \u{201C}grove help\u{201D} for more." + pathHint)
        } catch CommandLineTool.InstallError.cancelled {
            return
        } catch CommandLineTool.InstallError.occupied(let url, .userLink(let target)) {
            let alert = NSAlert()
            alert.messageText = "Replace Your Link?"
            alert.informativeText = "\(abbreviatingHome(url.path)) is a link to \(abbreviatingHome(target)), which isn't Grove. "
                + "Replace it with Grove's command?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { install(into: directory, replacing: true) }
        } catch CommandLineTool.InstallError.occupied(let url, _) {
            let other = directory == CommandLineTool.systemDirectory ? "~/.local/bin" : "/usr/local/bin"
            report(title: "Another \u{201C}grove\u{201D} Command Is Installed",
                   message: "\(abbreviatingHome(url.path)) belongs to another program, so Grove left it in place. "
                       + "Install Grove's command in \(other) instead, or remove that file first.",
                   style: .warning)
        } catch {
            report(title: "Couldn't Install the Command Line Tool", message: error.localizedDescription, style: .warning)
        }
    }

    private static func report(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
