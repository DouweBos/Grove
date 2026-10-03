// Views/Merge/ConflictWizardView.swift
// Grove
//
// Conflict resolver shown in the diff panel for a conflicted file: both versions
// side by side, keep one, or open the file to merge the markers by hand.

import AppKit
import GroveKit
import SwiftUI

struct ConflictWizardView: View {
    /// `nil` while loading.
    let versions: ConflictVersions?
    let oursLabel: String
    let theirsLabel: String
    let fileURL: URL
    var onResolve: (ConflictSide) -> Void
    /// `nil` hides the button, e.g. when no merge tool is configured.
    var onOpenMergeTool: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.conflicted)
                Text("Both sides changed this file. Keep one version, or edit the file and stage it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.sm)
                Button("Open File") { NSWorkspace.shared.open(fileURL) }
                    .help("Edit the conflict markers in your default editor")
                if let onOpenMergeTool {
                    Button("Open in Merge Tool", action: onOpenMergeTool)
                        .help("Resolve in the merge tool set in Editor settings, then stage the result")
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                ConflictVersionPanel(side: .ours, branchName: oursLabel, content: versions.map(\.ours)) {
                    onResolve(.ours)
                }
                ConflictVersionPanel(side: .theirs, branchName: theirsLabel, content: versions.map(\.theirs)) {
                    onResolve(.theirs)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConflictWizardView(
        versions: ConflictVersions(ours: "let token = oauth()\n", theirs: "let token = legacy()\n"),
        oursLabel: "main",
        theirsLabel: "feature/auth",
        fileURL: URL(fileURLWithPath: "/tmp/App.swift"),
        onResolve: { _ in }
    )
    .frame(width: 720, height: 480)
    .panel()
    .padding()
    .background(Theme.background)
}
