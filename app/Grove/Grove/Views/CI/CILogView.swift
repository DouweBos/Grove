// Views/CI/CILogView.swift
// Grove

import SwiftUI

/// The selected job's steps, each opening to its log lines.
struct CILogView: View {

    @Environment(CILogViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 0.5)
            content
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let count = viewModel.document?.lineCount, count > 0 {
                Text("\(count) lines").font(.monoCaption).foregroundStyle(Theme.textSecondary).fixedSize()
            }
            Spacer(minLength: Theme.Spacing.sm)
            if viewModel.isLoading { ProgressView().controlSize(.small) }
            search
            WrapLinesToggle()
            CopyButton(value: viewModel.plainText, help: "Copy Log", confirmation: "Copied Log")
        }
        .buttonStyle(.borderless)
        .disabled(viewModel.document == nil)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 40)
    }

    @ViewBuilder
    private var search: some View {
        PanelSearchField(placeholder: "Search log", text: viewModel.searchText) { text in Task { await viewModel.setSearchText(text) } }
            .frame(minWidth: 110, maxWidth: 200)
            .onSubmit { viewModel.nextMatch() }
        if !viewModel.searchText.isEmpty {
            Text(viewModel.currentMatchIndex.map { "\($0 + 1)/\(viewModel.matches.count)" } ?? "0/0")
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            Button { viewModel.previousMatch() } label: { Image(systemName: "chevron.up") }
                .help("Previous Match")
            Button { viewModel.nextMatch() } label: { Image(systemName: "chevron.down") }
                .help("Next Match")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage, viewModel.document?.lineCount ?? 0 == 0 {
            VStack(spacing: 0) {
                Banner(symbol: "exclamationmark.triangle", message: "Couldn't load the log: \(error)", actionTitle: "Try Again",
                       action: { Task { await viewModel.reload() } })
                    .padding(Theme.Spacing.sm)
                rows
            }
        } else if viewModel.rows.isEmpty {
            if viewModel.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(systemImage: "text.alignleft",
                               title: viewModel.isWaitingForJob ? "Waiting for a Runner" : "No Log",
                               subtitle: viewModel.isWaitingForJob ? nil : "This job didn't produce any output.")
            }
        } else {
            VStack(spacing: 0) {
                if viewModel.isWaitingForJob {
                    Banner(symbol: "clock", message: "The log appears when the job finishes.")
                        .padding(Theme.Spacing.sm)
                }
                rows
            }
        }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            DiffScrollView {
                CILogRows(rows: viewModel.rows, longestLine: viewModel.document?.longestLine ?? 0)
            }
            .onChange(of: viewModel.currentMatch) { _, match in
                // Leading, so a long line's start stays in view when lines don't wrap.
                if let match { proxy.scrollTo(match, anchor: UnitPoint(x: 0, y: 0.5)) }
            }
        }
    }
}

/// Lazy rows sized like a diff: as wide as the longest line, or the viewport when that's wider or lines wrap.
private struct CILogRows: View {
    @Environment(CILogViewModel.self) private var viewModel
    @Environment(\.diffViewportWidth) private var viewportWidth
    let rows: [CILogRow]
    let longestLine: Int

    /// Advance of one character of `Font.monoBody`.
    private static let characterWidth: CGFloat = 7.3

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .step(let section):
                    CILogStepHeader(section: section, isExpanded: viewModel.isExpanded(section)) { viewModel.toggleStep(section) }
                case .line(let line):
                    CILogRowView(line: line, isGroupExpanded: viewModel.expandedGroups.contains(line.id),
                                 searchText: viewModel.searchText, isCurrentMatch: viewModel.currentMatch == line.id) {
                        viewModel.toggleGroup(line)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .frame(width: viewportWidth.map { max($0, CILogRowView.gutterWidth + CGFloat(longestLine) * Self.characterWidth + 40) },
               alignment: .leading)
    }
}

#Preview {
    let vm = CILogViewModel(repository: MockGitRepository())
    return CILogView()
        .environment(vm)
        .frame(width: 640, height: 420)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.show(MockData.ciJobs(for: MockData.ciRuns[3])[1]) }
}
