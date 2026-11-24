// Views/Stashes/StashesView.swift
// Grove

import GroveKit
import GroveUIKit
import SwiftUI

/// GroveUIKit's stashes with Grove's diff settings; Stash, Snapshot and New Branch from Stash run as the sidebar's dialogs do.
struct StashesView: View {
    let viewModel: StashesViewModel
    let sidebar: SidebarViewModel
    private let diffSettings = DiffSettings()

    var body: some View {
        GitStashesView(viewModel: viewModel, dialogs: sidebar.dialogContext, options: diffSettings.options)
            .padding(.bottom, Theme.Spacing.md)
    }
}
