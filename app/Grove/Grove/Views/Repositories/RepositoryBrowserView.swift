// Views/Repositories/RepositoryBrowserView.swift
// Grove
//
// Root view for the repository browser tab.

import SwiftUI

// MARK: - RepositoryBrowserView

/// The full repository browser: sidebar with groups + content area.
struct RepositoryBrowserView: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var vm = viewModel
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RepositoryGroupsSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            RepositoryBrowserContent()
        }
        .navigationTitle("Repositories")
        .toolbar(removing: .sidebarToggle)
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
