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
        alert.informativeText = "Opens folders in Grove from Terminal, e.g. \u{201C}grove .\u{201D} or \u{201C}grove ~/Projects/app\u{201D}.\n\n"
            + "/usr/local/bin is on every shell's PATH and needs an administrator password. "
            + "~/.local/bin needs no password but has to be on your PATH."
        alert.addButton(withTitle: "Install in /usr/local/bin")
        alert.addButton(withTitle: "Install in ~/.local/bin")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        do {
            let installed: URL
            switch response {
            case .alertFirstButtonReturn: installed = try CommandLineTool.installSystemWide()
            case .alertSecondButtonReturn: installed = try CommandLineTool.install(in: CommandLineTool.userDirectory)
            default: return
            }
            let pathHint = response == .alertSecondButtonReturn ? " If the shell can't find it, add ~/.local/bin to your PATH." : ""
            report(title: "Command Line Tool Installed",
                   message: "\u{201C}grove\u{201D} is at \(abbreviatingHome(installed.path)). "
                       + "Run \u{201C}grove .\u{201D} in a repository to open it in a new tab." + pathHint)
        } catch CommandLineTool.InstallError.cancelled {
            return
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
