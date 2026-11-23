// History/List/CommitListPanel.swift
// GroveUIKit
//
// History's left panel: title and count with the filter and layout picker, then the commit table.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitListPanel: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.historyHost) private var host
    let viewModel: HistoryViewModel
    let actions: CommitActions

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: title, detail: countLabel) {
                if viewModel.isLoading { ProgressView().controlSize(.mini) }
                HistoryFilterField(text: viewModel.searchText) { viewModel.setSearchText($0) }
                    .frame(maxWidth: 190 * style.fontScale)
                layoutPicker
            }
            if let error = viewModel.errorMessage, viewModel.pendingAction == nil {
                GitBanner(symbol: "exclamationmark.triangle", message: error, tone: .negative,
                          onDismiss: { viewModel.dismissError() })
                    .padding(GitMetrics.Spacing.sm)
            }
            content
        }
        .gitPanel()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.filteredCommits.isEmpty && !viewModel.isLoading {
            if viewModel.isFiltering {
                GitEmptyState(systemImage: "magnifyingglass", title: "No Matching Commits",
                              subtitle: "Nothing in the loaded history matches \u{201C}\(viewModel.searchText)\u{201D}.")
            } else {
                GitEmptyState(systemImage: "clock", title: "No Commits Yet", subtitle: "Commits you make will show up here.")
            }
        } else {
            if viewModel.layout == .table { CommitTableHeader() }
            CommitTable(viewModel: viewModel, actions: actions)
        }
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: Binding(get: { viewModel.layout }, set: { viewModel.setLayout($0) })) {
            ForEach(HistoryLayout.allCases) { layout in
                Image(systemName: layout.symbol).help(layout.title).accessibilityLabel(layout.title).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .gitClickable()
    }

    private var title: String {
        if let title = host.title { return title }
        let branch = viewModel.filterBranch ?? viewModel.headBranchName ?? "HEAD"
        return viewModel.upstreamName.map { "\(branch) \u{203A} \($0)" } ?? branch
    }

    private var countLabel: String {
        let count = viewModel.isFiltering ? viewModel.filteredCommits.count : viewModel.commits.count
        let suffix = viewModel.hasMore ? "+" : ""
        return "\(count)\(suffix) commit\(count == 1 && suffix.isEmpty ? "" : "s")"
    }
}

/// Column titles above the table layout.
struct CommitTableHeader: View {
    @Environment(\.gitStyle) private var style

    var body: some View {
        let s = style.fontScale
        HStack(spacing: GitMetrics.Spacing.sm * s) {
            Text("Subject").frame(maxWidth: .infinity, alignment: .leading)
            Text("Author").frame(width: CommitListMetrics.Column.author * s, alignment: .leading)
            Text("Date").frame(width: CommitListMetrics.Column.date * s, alignment: .leading)
            Text("SHA").frame(width: CommitListMetrics.Column.sha * s, alignment: .leading)
        }
        .font(style.sectionLabel)
        .foregroundStyle(style.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, GitMetrics.Spacing.md * s)
        .frame(height: 26 * s)
        .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }
    }
}

/// Compact search field in the list's header.
struct HistoryFilterField: View {
    @Environment(\.gitStyle) private var style
    let text: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(style.textSecondary)
            TextField("Filter", text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.plain)
                .font(style.font(12))
            if !text.isEmpty {
                Button { onChange("") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .gitClickable()
                    .foregroundStyle(style.textSecondary)
                    .accessibilityLabel("Clear filter")
            }
        }
        .font(style.font(11))
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.vertical, 4)
        .background(style.subtleFill, in: Capsule())
        .help("Filter by message, author or SHA")
    }
}
#endif
