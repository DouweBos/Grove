// Views/WorkingCopy/WorkingCopyView.swift
// Grove
//
// Root view for the Working Copy feature area.
// Implements the three-zone HSplitView layout:
//   Left (~35%): WorkingCopyLeftColumn (CommitComposer + FileStatusList)
//   Right (~65%): DiffPanelView
//
// The ViewModel is owned here and propagated via the environment so all
// child views can access shared state without prop-drilling.

import SwiftUI

// MARK: - WorkingCopyView

/// Three-zone Working Copy layout. Entry point for the WS3 view cluster.
///
/// Inject via:
/// ```swift
/// WorkingCopyView(repository: someRepo)
/// ```
struct WorkingCopyView: View {

    // MARK: State

    @State private var viewModel: WorkingCopyViewModel

    // MARK: Init

    init(repository: any GitRepositoryProtocol) {
        _viewModel = State(wrappedValue: WorkingCopyViewModel(repository: repository))
    }

    // MARK: Body

    var body: some View {
        HSplitView {
            WorkingCopyLeftColumn()
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 420)

            DiffPanelView()
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(viewModel)
        .task { await viewModel.refresh() }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
    }

    // MARK: Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

// MARK: - Preview

#Preview("Working Copy") {
    WorkingCopyView(repository: MockGitRepository())
        .frame(width: 900, height: 600)
}
