// Views/PullRequests/PullRequestListView.swift
// Grove

import SwiftUI

/// The left panel of the Pull Requests view — filter tabs and scrollable PR list.
struct PullRequestListView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Pull Requests")
                    .font(.headline)
                    .padding(.leading, 8)
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Filter tabs
            filterBar(selection: $vm.filterState)

            Divider()

            // List body
            if viewModel.isLoading && viewModel.pullRequests.isEmpty {
                Spacer()
                ProgressView("Loading pull requests\u{2026}")
                Spacer()
            } else if viewModel.filteredPullRequests.isEmpty {
                emptyState
            } else {
                List(selection: $vm.selectedPR) {
                    ForEach(viewModel.filteredPullRequests) { pr in
                        PullRequestRow(pr: pr)
                            .tag(pr)
                            .contextMenu {
                                Button("Check Out") {
                                    Task { await viewModel.checkout(pr: pr) }
                                }
                                Divider()
                                if pr.state == .open {
                                    Button("Merge") {
                                        Task { await viewModel.merge(pr: pr) }
                                    }
                                    Button("Close", role: .destructive) {
                                        Task { await viewModel.close(pr: pr) }
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: viewModel.selectedPR) { _, pr in
            if let pr {
                Task { await viewModel.selectPR(pr) }
            }
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private func filterBar(selection: Binding<PRFilterState>) -> some View {
        HStack(spacing: 0) {
            ForEach(PRFilterState.allCases, id: \.self) { tab in
                Button {
                    selection.wrappedValue = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selection.wrappedValue == tab
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .foregroundStyle(
                            selection.wrappedValue == tab
                                ? Color.accentColor
                                : Color.secondary
                        )
                }
                .buttonStyle(.plain)

                if tab != PRFilterState.allCases.last {
                    Divider()
                        .frame(height: 16)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No pull requests")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    return PullRequestListView()
        .environment(vm)
        .frame(width: 300, height: 400)
        .task { await vm.refresh() }
}
