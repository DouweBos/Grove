// Views/Repositories/RepositoryBrowserView.swift
// Grove
//
// Root view for the repository browser window.
// Hosts a NavigationSplitView with the groups sidebar and content area.

import SwiftUI

// MARK: - RepositoryBrowserView

/// The full repository browser: sidebar with groups + content area.
///
/// Injected with a ``RepositoryManagerProtocol`` so previews can use
/// ``MockRepositoryManager`` without touching real disk.
struct RepositoryBrowserView: View {

    // MARK: Dependencies

    @Environment(RepositoryBrowserViewModel.self) private var viewModel

    // MARK: State

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: Body

    var body: some View {
        @Bindable var vm = viewModel
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RepositoryGroupsSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            RepositoryBrowserContent()
        }
        .navigationTitle("Repositories")
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $vm.isShowingCloneDialog) {
            CloneDialogView()
                .environment(viewModel)
        }
        .sheet(isPresented: $vm.isShowingAddDialog) {
            AddRepositorySheet()
                .environment(viewModel)
        }
        .sheet(isPresented: $vm.isShowingCreateDialog) {
            CreateRepositorySheet()
                .environment(viewModel)
        }
    }
}

// MARK: - Preview

#Preview {
    RepositoryBrowserView()
        .environment(RepositoryBrowserViewModel(manager: MockRepositoryManager()))
}
