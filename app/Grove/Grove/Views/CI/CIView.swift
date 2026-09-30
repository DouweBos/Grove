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
            }
        }
        .padding(.bottom, Theme.Spacing.md)
        .alert("Action Failed", isPresented: Binding(get: { viewModel.actionError != nil },
                                                    set: { if !$0 { viewModel.clearActionError() } })) {
            Button("OK") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }
}

// MARK: - List Panel

private struct CIRunListPanel: View {
    @Environment(CIViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Workflow Runs", detail: "\(viewModel.runs.count)") {
                if viewModel.isLoading { ProgressView().controlSize(.small) }
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
            SelectableList(items: viewModel.runs, selection: viewModel.selectedRunID, onSelect: viewModel.select) { run in
                CIRunRow(run: run)
                    .contextMenu {
                        Button("Open on \(viewModel.serviceName)", systemImage: "safari") { viewModel.openInBrowser(run) }
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
