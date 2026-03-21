// Views/PullRequests/PullRequestsView.swift
// Grove

import SwiftUI

/// The full Pull Requests view: PR list (left) | PR detail (right).
///
/// Uses `HSplitView` for a resizable two-column layout matching the
/// Stashes and History views.
struct PullRequestsView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        HSplitView {
            PullRequestListView()
                .frame(minWidth: 260, maxWidth: 400)

            PullRequestDetailView()
                .frame(minWidth: 320)
                .background(.background)
        }
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    return PullRequestsView()
        .environment(vm)
        .frame(width: 820, height: 560)
        .task { await vm.refresh() }
}
