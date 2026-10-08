// Views/Settings/CommandLineToolSection.swift
// Grove
//
// Settings' view of the `grove` command: where it is, and a fix when it's an old copy or a link Grove's move broke.

import GroveKit
import SwiftUI

struct CommandLineToolSection: View {

    /// Re-read after each install, since the file system isn't observable.
    @State private var found = CommandLineTool.existingInstallation()

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Image(systemName: symbol).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let found {
                        Text(abbreviatingHome(found.url.path)).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let action {
                    Button(action.title) {
                        action.run()
                        found = CommandLineTool.existingInstallation()
                    }
                }
            }
        } header: {
            Text("Command Line Tool")
        } footer: {
            Text("\u{201C}grove\u{201D} opens repositories, History, Blame and stacks from Terminal, and prints stacks, branches "
                 + "and pull requests for scripts and agents. Run \u{201C}grove help\u{201D} for details.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .onAppear { found = CommandLineTool.existingInstallation() }
    }

    private var title: String {
        switch found?.installation {
        case nil, .missing: "Not installed"
        case .current: "Installed"
        case .outdatedCopy: "An older copy that doesn\u{2019}t update with Grove"
        case .otherGrove(_, exists: false): "Broken: Grove was moved or renamed"
        case .otherGrove(let target, exists: true): "Opens another copy of Grove at \(abbreviatingHome(target))"
        case .userLink, .foreign: "Another program\u{2019}s \u{201C}grove\u{201D} command"
        }
    }

    private var symbol: String {
        switch found?.installation {
        case .current: "checkmark.circle.fill"
        case .outdatedCopy, .otherGrove: "exclamationmark.triangle.fill"
        default: "terminal"
        }
    }

    private var tint: Color {
        switch found?.installation {
        case .current: Theme.success
        case .outdatedCopy, .otherGrove: Theme.warning
        default: Theme.textSecondary
        }
    }

    private var action: (title: String, run: () -> Void)? {
        guard let found else { return ("Install\u{2026}", CommandLineToolInstaller.run) }
        let title: String
        switch found.installation {
        case .outdatedCopy: title = "Update"
        case .otherGrove(_, exists: false): title = "Repair"
        case .otherGrove(_, exists: true): title = "Use This Copy"
        default: return nil
        }
        return (title, { CommandLineToolInstaller.install(into: found.url.deletingLastPathComponent()) })
    }
}

#Preview {
    Form { CommandLineToolSection() }
        .formStyle(.grouped)
        .frame(width: 500, height: 200)
}
