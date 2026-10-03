// Views/History/HistoryView.swift
// Grove

import GroveKit
import SwiftUI

/// History tab: commit list card on the left, commit detail card on the right.
struct HistoryView: View {
    @Environment(HistoryViewModel.self) private var viewModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Side by side needs ~600pt; narrower (sidebar open in a small window) stacks the cards.
            if width >= 600 {
                HStack(spacing: Theme.Spacing.md) {
                    CommitListView()
                        .frame(width: min(max(280, width * 0.44), width - 320))
                    CommitDetailPanel()
                }
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    CommitListView()
                        .frame(height: geometry.size.height * 0.45)
                    CommitDetailPanel()
                }
            }
        }
        .padding(.bottom, Theme.Spacing.md)
        .task { await viewModel.loadIfNeeded() }
        .sheet(item: Binding(get: { viewModel.pendingAction }, set: { if $0 == nil { viewModel.dismissAction() } })) { action in
            HistoryActionSheet(action: action)
                .environment(viewModel)
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return HistoryView()
        .environment(vm)
        .frame(width: 1000, height: 600)
        .padding()
        .background(Theme.background)
}
