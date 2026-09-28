// Views/Reflog/ReflogView.swift
// Grove

import SwiftUI

// MARK: - ReflogView

/// The full Reflog view: reflog entry list (left) | entry detail panel (right).
///
/// Uses `HSplitView` for a resizable two-column layout matching the Stashes
/// and History views. The shared ``ReflogViewModel`` is injected from the
/// parent ``RepositoryContentRouter`` via `@Environment`.
struct ReflogView: View {

    @Environment(ReflogViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        HSplitView {
            ReflogListView()
                .frame(minWidth: 260, maxWidth: 400)

            ReflogDetailPanel()
                .frame(minWidth: 300)
                .background(Theme.surface)
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = ReflogViewModel(repository: MockGitRepository())
    return ReflogView()
        .environment(vm)
        .frame(width: 750, height: 480)
}
