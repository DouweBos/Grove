// Views/CI/CIRunDetailView.swift
// Grove

import GroveKit
import SwiftUI

/// Detail card for the selected run: what ran, where, how it went, and its jobs.
struct CIRunDetailView: View {

    @Environment(CIViewModel.self) private var viewModel
    @Environment(CIRunDetailViewModel.self) private var detail

    var body: some View {
        Group {
            if let run = viewModel.selectedRun {
                VStack(spacing: 0) {
                    header(run)
                    Rectangle().fill(Theme.border).frame(height: 0.5)
                    CIJobsView()
                }
            } else {
                EmptyStateView(systemImage: "play.circle", title: "No Run Selected",
                               subtitle: "Select a workflow run to see its jobs.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    // MARK: - Header

    private func header(_ run: CIRun) -> some View {
        summaryRow(run)
            .padding(Theme.Spacing.lg)
    }

    private func summaryRow(_ run: CIRun) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(run.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                HStack(spacing: Theme.Spacing.sm) {
                    StatusBadge(title: run.status.title, symbol: run.status.symbol, tone: run.status.badgeTone).fixedSize()
                    Text(summary(run))
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: Theme.Spacing.xs) {
                    if let branch = run.branch { BranchLabel(name: branch, kind: .remoteBranch) }
                    Text(run.shortSHA).font(.monoCaption).foregroundStyle(Theme.accent)
                    CopyButton(value: run.headSHA, help: "Copy SHA", confirmation: "Copied SHA")
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            HStack(spacing: Theme.Spacing.sm) {
                Button { viewModel.openInBrowser(run) } label: { Image(systemName: "safari") }
                    .help("Open on \(viewModel.serviceName)")
                if run.status.isActive {
                    let isWatching = viewModel.isWatching(run)
                    Button { viewModel.toggleNotification(for: run) } label: { Image(systemName: isWatching ? "bell.fill" : "bell") }
                        .help(isWatching ? "Stop Notifying" : "Notify When Finished")
                    Button("Cancel Run\u{2026}", role: .destructive) { viewModel.request(.cancel, on: run) }
                } else {
                    Menu("Re-run") { CIRunActions(run: run) }
                        .fixedSize()
                }
            }
            .disabled(viewModel.isPerforming)
        }
    }

    /// `CI #12 · attempt 2 · push by jane · 3m 07s`
    private func summary(_ run: CIRun) -> String {
        var parts = ["\(run.workflowName) #\(run.number)"]
        if run.attempt > 1 { parts.append("attempt \(run.attempt)") }
        parts.append(run.actor.isEmpty ? run.event : "\(run.event) by \(run.actor)")
        if let duration = run.duration() { parts.append(CIDuration.text(duration)) }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Re-run and cancel items for a run, shared by the detail header and the list's context menu.
struct CIRunActions: View {
    @Environment(CIViewModel.self) private var viewModel
    let run: CIRun

    var body: some View {
        if run.status.isActive {
            if viewModel.isWatching(run) {
                Button("Stop Notifying", systemImage: "bell.slash") { viewModel.toggleNotification(for: run) }
            } else {
                Button("Notify When Finished", systemImage: "bell") { viewModel.toggleNotification(for: run) }
            }
            Button("Cancel Run\u{2026}", systemImage: "xmark.circle", role: .destructive) { viewModel.request(.cancel, on: run) }
        } else {
            Button("Re-run All Jobs\u{2026}", systemImage: "arrow.clockwise") { viewModel.request(.rerun, on: run) }
            Button("Re-run Failed Jobs\u{2026}", systemImage: "arrow.clockwise.circle") { viewModel.request(.rerunFailed, on: run) }
                .disabled(!viewModel.canRerunFailed(run))
        }
    }
}

#Preview {
    let vm = CIViewModel(repository: MockGitRepository())
    return CIRunDetailView()
        .environment(vm)
        .environment(vm.detail)
        .frame(width: 620, height: 480)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
