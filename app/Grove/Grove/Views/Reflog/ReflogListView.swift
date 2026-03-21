// Views/Reflog/ReflogListView.swift
// Grove

import SwiftUI

// MARK: - ReflogListView

/// The left panel of the Reflog view — scrollable list of reflog entries.
///
/// Displays entries with colour-coded action badges and handles selection
/// by calling ``ReflogViewModel/selectEntry(_:)`` on the shared ViewModel.
struct ReflogListView: View {

    @Environment(ReflogViewModel.self) private var viewModel

    // MARK: - Body

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Reflog")
                    .font(.headline)
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(8)
            .background(.bar)

            Divider()

            if viewModel.isLoading && viewModel.entries.isEmpty {
                Spacer()
                ProgressView("Loading reflog\u{2026}")
                Spacer()
            } else if viewModel.entries.isEmpty {
                emptyState
            } else {
                List(selection: $vm.selectedEntry) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        let actionType = viewModel.actionType(for: entry)
                        ReflogRow(entry: entry, index: index, actionType: actionType)
                            .tag(entry)
                            .contextMenu {
                                contextMenu(for: entry)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onChange(of: viewModel.selectedEntry) { _, entry in
            if let entry {
                Task { await viewModel.selectEntry(entry) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No reflog entries")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for entry: ReflogEntry) -> some View {
        Button("Reset HEAD Here (Mixed)") {
            Task { await viewModel.resetToEntry(entry, mode: .mixed) }
        }
        Button("Reset HEAD Here (Soft)") {
            Task { await viewModel.resetToEntry(entry, mode: .soft) }
        }
        Button("Reset HEAD Here (Hard)", role: .destructive) {
            Task { await viewModel.resetToEntry(entry, mode: .hard) }
        }
        Divider()
        Button("Copy SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.newSHA, forType: .string)
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = ReflogViewModel(repository: MockGitRepository())
    return ReflogListView()
        .environment(vm)
        .frame(width: 300, height: 400)
        .task { await vm.refresh() }
}
