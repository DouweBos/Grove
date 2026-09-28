// Views/Stashes/StashesView.swift
// Grove

import SwiftUI

/// The full Stashes view: stash list (left) | stash detail (right).
///
/// Uses `HSplitView` for a resizable two-column layout mirroring the History view.
struct StashesView: View {

    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        HSplitView {
            StashListView()
                .frame(minWidth: 240, maxWidth: 360)

            StashDetailView()
                .frame(minWidth: 300)
                .background(Theme.surface)
        }
    }
}

#Preview {
    let vm = StashesViewModel(repository: MockGitRepository())
    return StashesView()
        .environment(vm)
        .frame(width: 700, height: 450)
}
