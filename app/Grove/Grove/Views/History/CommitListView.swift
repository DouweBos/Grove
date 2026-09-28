// Views/History/CommitListView.swift
// Grove

import AppKit
import SwiftUI

/// Left panel of History: header with filter, date-grouped commit rows, infinite scroll.
struct CommitListView: View {
    @Environment(HistoryViewModel.self) private var viewModel
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title, detail: countLabel) {
                HistoryFilterField(text: viewModel.searchText) { viewModel.setSearchText($0) }
                    .frame(maxWidth: 190)
            }
            if let error = viewModel.errorMessage, viewModel.pendingAction == nil {
                Banner(symbol: "exclamationmark.triangle", message: error, tone: .negative,
                       onDismiss: { viewModel.dismissError() })
                    .padding(Theme.Spacing.sm)
            }
            content
        }
        .panel()
    }

    @ViewBuilder
    private var content: some View {
        let visible = viewModel.filteredCommits
        if visible.isEmpty && !viewModel.isLoading {
            if viewModel.isFiltering {
                EmptyStateView(systemImage: "magnifyingglass", title: "No Matching Commits",
                               subtitle: "Nothing in the loaded history matches \u{201C}\(viewModel.searchText)\u{201D}.")
            } else {
                EmptyStateView(systemImage: "clock", title: "No Commits Yet",
                               subtitle: "Commits you make will show up here.")
            }
        } else {
            list(visible)
        }
    }

    private func list(_ visible: [CommitInfo]) -> some View {
        let showsGraph = !viewModel.isFiltering
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Self.groups(visible)) { group in
                        DateGroupHeader(date: group.date,
                                        lanes: viewModel.graphNodes[group.commits[0].id]?.lanesAbove ?? [],
                                        maxGraphColumns: viewModel.maxGraphColumns,
                                        showsGraph: showsGraph)
                        ForEach(group.commits) { commit in
                            row(commit, showsGraph: showsGraph)
                        }
                    }
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small).padding(Theme.Spacing.md)
                    }
                }
                .padding(.bottom, Theme.Spacing.sm)
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            // Arrow keys should move the selection as soon as History opens, without a click first;
            // deferred a turn because the window assigns its first responder after the view appears.
            .defaultFocus($isListFocused, true)
            .task {
                await Task.yield()
                isListFocused = true
            }
            // onKeyPress rather than onMoveCommand: the scroll view swallows move commands itself.
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                viewModel.selectAdjacent(offset: press.key == .upArrow ? -1 : 1, extend: press.modifiers.contains(.shift))
                return .handled
            }
            .onChange(of: viewModel.selectedCommit?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            // A reveal from another tab selects before this list exists.
            .onAppear {
                if let id = viewModel.selectedCommit?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func row(_ commit: CommitInfo, showsGraph: Bool) -> some View {
        CommitRow(
            commit: commit,
            branches: viewModel.branches(at: commit),
            tags: viewModel.tags(at: commit),
            graphNode: showsGraph ? viewModel.graphNodes[commit.id] : nil,
            maxGraphColumns: viewModel.maxGraphColumns,
            isHead: commit.id == viewModel.headSHA,
            syncState: viewModel.syncState(of: commit),
            isSelected: viewModel.isSelected(commit)
        )
        .id(commit.id)
        .onTapGesture {
            isListFocused = true
            let modifiers = NSEvent.modifierFlags
            viewModel.click(commit, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelectedTrait(commit) ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewModel.select(commit) }
        // Dropping the SHA onto Working Copy cherry-picks it.
        .draggable(commit.id)
        .contextMenu { CommitContextMenu(commit: commit) }
        .onAppear { viewModel.rowAppeared(commit) }
    }

    private func isSelectedTrait(_ commit: CommitInfo) -> Bool {
        viewModel.isSelected(commit)
    }

    private var title: String {
        let branch = viewModel.filterBranch ?? viewModel.headBranchName ?? "HEAD"
        return viewModel.upstreamName.map { "\(branch) \u{203A} \($0)" } ?? branch
    }

    private var countLabel: String {
        let count = viewModel.commits.count
        let suffix = viewModel.hasMore ? "+" : ""
        return "\(count)\(suffix) commit\(count == 1 && suffix.isEmpty ? "" : "s")"
    }

    // MARK: - Grouping

    struct DayGroup: Identifiable {
        /// First commit's SHA: in topological order a day can recur, so the day itself isn't unique.
        let id: String
        let day: DateComponents
        let date: Date
        var commits: [CommitInfo]
    }

    /// Consecutive commits from the same calendar day share a header.
    static func groups(_ commits: [CommitInfo]) -> [DayGroup] {
        var result: [DayGroup] = []
        for commit in commits {
            let day = Calendar.current.dateComponents([.year, .month, .day], from: commit.authorDate)
            if result.last?.day == day {
                result[result.count - 1].commits.append(commit)
            } else {
                result.append(DayGroup(id: commit.id, day: day, date: commit.authorDate, commits: [commit]))
            }
        }
        return result
    }
}

/// Compact search field that lives in the list's panel header.
struct HistoryFilterField: View {
    let text: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Filter", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { onChange("") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Clear filter")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Theme.subtleFill, in: Capsule())
        .help("Filter by message, author or SHA")
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitListView()
        .environment(vm)
        .frame(width: 420, height: 560)
        .padding()
        .background(Theme.background)
        .task { await vm.loadInitial() }
}
