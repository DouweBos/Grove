// Views/History/CommitListView.swift
// Grove

import SwiftUI

/// Scrollable commit list with a search/filter bar at the top.
///
/// Displays commits grouped by date and handles infinite-scroll pagination.
struct CommitListView: View {

    @Environment(HistoryViewModel.self) private var viewModel

    // Branches and tags for label decoration — injected from parent.
    var branches: [BranchInfo] = []
    var tags: [TagInfo] = []

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // MARK: Filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter commits…", text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // MARK: Commit list
            List(selection: $vm.selectedCommit) {
                ForEach(groupedCommits, id: \.key) { group in
                    Section {
                        ForEach(group.commits) { commit in
                            CommitRow(
                                commit: commit,
                                branches: branchesFor(commit),
                                tags: tagsFor(commit),
                                graphNode: viewModel.graphNodes[commit.id],
                                maxGraphColumns: viewModel.maxGraphColumns
                            )
                            .tag(commit)
                            // Drag source: the full 40-char SHA is the transfer payload.
                            // Dropping onto Working Copy triggers cherry-pick.
                            .draggable(commit.id)
                            .contextMenu { contextMenu(for: commit) }
                            .onAppear {
                                // Trigger pagination when the last item appears
                                if commit.id == viewModel.filteredCommits.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }
                    } header: {
                        DateGroupHeader(date: group.date)
                    }
                }

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    // MARK: - Grouping

    private struct CommitGroup {
        let key: String
        let date: Date
        var commits: [CommitInfo]
    }

    private var groupedCommits: [CommitGroup] {
        var groups: [String: CommitGroup] = [:]
        var order: [String] = []

        for commit in viewModel.filteredCommits {
            let key = dayKey(for: commit.authorDate)
            if groups[key] == nil {
                groups[key] = CommitGroup(key: key, date: commit.authorDate, commits: [])
                order.append(key)
            }
            groups[key]!.commits.append(commit)
        }

        return order.compactMap { groups[$0] }
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }

    // MARK: - Helpers

    private func branchesFor(_ commit: CommitInfo) -> [BranchInfo] {
        branches.filter { $0.targetSHA == commit.id }
    }

    private func tagsFor(_ commit: CommitInfo) -> [TagInfo] {
        tags.filter { $0.targetSHA == commit.id }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for commit: CommitInfo) -> some View {
        Button("Copy Commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
        Button("Copy Short SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        }
        Divider()
        Button("Create Branch from \"\(commit.shortSHA)\"…") {
            Task { await viewModel.createBranch(from: commit) }
        }
        Button("Create Tag at \"\(commit.shortSHA)\"…") {
            Task { await viewModel.createTag(at: commit) }
        }
        Divider()
        Button("Cherry-Pick \"\(commit.shortSHA)\"…") {
            Task { await viewModel.cherryPick(commit) }
        }
        Button("Revert \"\(commit.shortSHA)\"…") { }
        Divider()
        Button("Reset HEAD to \"\(commit.shortSHA)\"…") { }
        Divider()
        Button("Edit Commit Message of \"\(commit.shortSHA)\"…") { }
        Button("Squash with Parent Revision…") { }
        Button("Delete \"\(commit.shortSHA)\"…", role: .destructive) { }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitListView(
        branches: MockData.branches,
        tags: MockData.tags
    )
    .environment(vm)
    .frame(width: 400, height: 500)
    .task { await vm.loadInitial() }
}
