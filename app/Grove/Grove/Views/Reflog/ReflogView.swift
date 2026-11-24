// Views/Reflog/ReflogView.swift
// Grove

import GroveKit
import GroveUIKit
import SwiftUI

/// GroveUIKit's reflog with Grove's diff settings; New Branch runs as the sidebar's does.
struct ReflogView: View {
    let viewModel: ReflogViewModel
    let sidebar: SidebarViewModel
    private let diffSettings = DiffSettings()

    var body: some View {
        GitReflogView(viewModel: viewModel, dialogs: sidebar.dialogContext, options: diffSettings.options)
            .padding(.bottom, Theme.Spacing.md)
    }
}
