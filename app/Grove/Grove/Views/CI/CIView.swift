// Views/CI/CIView.swift
// Grove

import SwiftUI

/// Workflow runs on the left, the selected run on the right. Data comes from the remote's hosting service.
struct CIView: View {

    @Environment(CIViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            CIRunListPanel()
                .frame(width: 360)
            if let failure = viewModel.loadFailure, viewModel.runs.isEmpty {
                HostUnavailableView(failure: failure, feature: .ci, isLoading: viewModel.isLoading) {
                    Task { await viewModel.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panel()
            } else {
                CIRunDetailView()
                    .environment(viewModel.detail)
            }
        }
        .padding(.bottom, Theme.Spacing.md)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { viewModel.pendingOperation != nil },
                                                              set: { if !$0 { viewModel.cancelPendingOperation() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingOperation) { pending in
            Button(confirmTitle(pending.operation), role: pending.operation == .cancel ? .destructive : nil) {
                Task { await viewModel.confirm(pending) }
            }
            Button(pending.operation == .cancel ? "Keep Running" : "Cancel", role: .cancel) { viewModel.cancelPendingOperation() }
        } message: { pending in
            Text(message(pending))
        }
        .alert("Action Failed", isPresented: Binding(get: { viewModel.actionError != nil },
                                                    set: { if !$0 { viewModel.clearActionError() } })) {
            Button("OK") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }
}

extension CIView {
    private var dialogTitle: String {
        guard let pending = viewModel.pendingOperation else { return "" }
        let name = "\(pending.run.workflowName) #\(pending.run.number)"
        return pending.operation == .cancel ? "Cancel \(name)?" : "Re-run \(name)?"
    }

    private func confirmTitle(_ operation: CIViewModel.Operation) -> String {
        switch operation {
        case .rerun: "Re-run All Jobs"
        case .rerunFailed: "Re-run Failed Jobs"
        case .cancel: "Cancel Run"
        }
    }

    private func message(_ pending: CIViewModel.PendingOperation) -> String {
        let target = pending.run.branch.map { "\($0) at \(pending.run.shortSHA)" } ?? pending.run.shortSHA
        switch pending.operation {
        case .rerun: return "Runs every job again on \(target), as attempt \(pending.run.attempt + 1)."
        case .rerunFailed: return "Runs the failed jobs, and the jobs that depend on them, again on \(target)."
        case .cancel: return "Stops the run on \(viewModel.serviceName). Jobs that already finished keep their results."
        }
    }
}

// MARK: - List Panel

private struct CIRunListPanel: View {
    @Environment(CIViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Workflow Runs", detail: "\(viewModel.runs.count)\(viewModel.hasMoreRuns ? "+" : "")") {
                if viewModel.isLoading || viewModel.isLoadingMore { ProgressView().controlSize(.small) }
                Button { viewModel.beginDispatch() } label: { Image(systemName: "play") }
                    .buttonStyle(.borderless)
                    .help("Run Workflow")
                    .disabled(isUnavailable)
                Button { Task { await viewModel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload from \(viewModel.serviceName)")
            }
            CIRunFilterBar()
                .padding([.horizontal, .top], Theme.Spacing.sm)
                .disabled(isUnavailable)
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private var isUnavailable: Bool { viewModel.loadFailure != nil && viewModel.runs.isEmpty }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isUnavailable {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Not Available")
        } else if viewModel.runs.isEmpty {
            if viewModel.query.isEmpty {
                EmptyStateView(systemImage: "play.circle", title: "No Workflow Runs",
                               subtitle: "This repository has no workflow runs on \(viewModel.serviceName).")
            } else {
                EmptyStateView(systemImage: "line.3.horizontal.decrease.circle", title: "No Matching Runs",
                               actionTitle: "Clear Filters") { Task { await viewModel.clearFilters() } }
            }
        } else {
            SelectableList(items: viewModel.runs, selection: viewModel.selectedRunID, onSelect: { run in Task { await viewModel.select(run) } }) { run in
                CIRunRow(run: run, isWatched: viewModel.isWatching(run))
                    .onAppear {
                        // The last row coming into view reads the next page.
                        if run.id == viewModel.runs.last?.id { Task { await viewModel.loadMore() } }
                    }
                    .contextMenu {
                        Button("Open on \(viewModel.serviceName)", systemImage: "safari") { viewModel.openInBrowser(run) }
                        CIRunActions(run: run)
                        Divider()
                        Button("Copy SHA", systemImage: "doc.on.doc") { GroveClipboard.copy(run.headSHA) }
                        if let branch = run.branch {
                            Button("Copy Branch Name", systemImage: "doc.on.doc") { GroveClipboard.copy(branch) }
                        }
                    }
            }
        }
    }
}

#Preview {
    let vm = CIViewModel(repository: MockGitRepository())
    return CIView()
        .environment(vm)
        .frame(width: 1000, height: 620)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
