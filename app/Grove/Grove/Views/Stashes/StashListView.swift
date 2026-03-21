// Views/Stashes/StashListView.swift
// Grove

import SwiftUI

/// The left panel of the Stashes view — scrollable list of stash entries.
struct StashListView: View {

    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Stashes")
                    .font(.headline)
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(8)
            .background(.bar)

            Divider()

            if viewModel.isLoading && viewModel.stashes.isEmpty {
                Spacer()
                ProgressView("Loading stashes…")
                Spacer()
            } else if viewModel.stashes.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray.2")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No stashes")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: $vm.selectedStash) {
                    ForEach(viewModel.stashes) { stash in
                        StashRow(stash: stash)
                            .tag(stash)
                            // Drag source: "stash@{<index>}" as the transfer payload.
                            // Dropping onto Working Copy applies the stash.
                            .draggable("stash@{\(stash.id)}")
                            .contextMenu {
                                Button("Apply Stash") {
                                    Task { await viewModel.apply(stash: stash) }
                                }
                                Button("Pop Stash (Apply and Drop)") {
                                    Task { await viewModel.pop(stash: stash) }
                                }
                                Divider()
                                Button("Drop Stash", role: .destructive) {
                                    Task { await viewModel.drop(stash: stash) }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onChange(of: viewModel.selectedStash) { _, stash in
            if let stash {
                Task { await viewModel.selectStash(stash) }
            }
        }
    }
}

#Preview {
    let vm = StashesViewModel(repository: MockGitRepository())
    return StashListView()
        .environment(vm)
        .frame(width: 280, height: 300)
        .task { await vm.refresh() }
}
