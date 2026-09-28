// Views/WorkingCopy/FilesPanelMenu.swift
// Grove
//
// The Files panel's actions menu: patches, snapshots and stashing.

import SwiftUI

struct FilesPanelMenu: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel

    var body: some View {
        Menu {
            Button("Apply Patch\u{2026}") { viewModel.requestPatchFile() }
            if let selection = viewModel.selectionForPatch {
                Button(selection.entries.count > 1 ? "Create Patch from \(selection.entries.count) Files\u{2026}" : "Create Patch\u{2026}") {
                    Task { await savePatch(selection.entries, side: selection.side, viewModel: viewModel) }
                }
            } else {
                Button("Create Patch\u{2026}") {}.disabled(true)
            }
            Divider()
            Button("Stash Changes\u{2026}") { GroveAction.stash.post() }
                .disabled(viewModel.statusEntries.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.textSecondary)
        .help("More Actions")
    }
}

#Preview {
    FilesPanelMenu()
        .environment(WorkingCopyViewModel(repository: MockGitRepository()))
        .padding()
        .background(Theme.surface)
}
