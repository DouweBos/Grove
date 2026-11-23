// WorkingCopy/FilesPanelMenu.swift
// GroveUIKit
//
// The Files panel's actions: staging everything, patches, stashing and snapshots.

#if os(macOS)
import GroveKit
import SwiftUI

struct FilesPanelMenu: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host

    var body: some View {
        Menu {
            Button("Stage All") { viewModel.act { await viewModel.stageAll() } }
                .disabled(viewModel.unstagedFiles.isEmpty)
            Button("Unstage All") { viewModel.act { await viewModel.unstageAll() } }
                .disabled(viewModel.stagedFiles.isEmpty)
            Divider()
            Button("Apply Patch") { viewModel.requestPatchFile() }
                .requires(.applyPatch)
            if let selection = viewModel.selectionForPatch {
                Button(selection.entries.count > 1 ? "Create Patch from \(selection.entries.count) Files" : "Create Patch") {
                    Task { await createPatch(selection.entries, side: selection.side, viewModel: viewModel, host: host) }
                }
                .requires(.export)
            } else {
                Button("Create Patch") {}.disabled(true)
            }
            if let present = host.present {
                Divider()
                Button("Stash Changes") { present(.stash()) }
                    .disabled(viewModel.statusEntries.isEmpty)
                Button("Save Snapshot") { present(.snapshot) }
                    .disabled(viewModel.statusEntries.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(style.font(13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(style.textSecondary)
        .gitClickable()
        .help("More Actions")
        .accessibilityLabel("More Actions")
    }
}
#endif
