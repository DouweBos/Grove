// Views/CI/CIJobsView.swift
// Grove

import GroveKit
import SwiftUI

/// A run's jobs on the left; on the right, the run's summary or the selected job's steps and log.
struct CIJobsView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingJobs {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.jobsError, viewModel.jobs.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't Load Jobs", subtitle: error,
                           actionTitle: "Try Again") { Task { await viewModel.reload() } }
        } else if viewModel.jobs.isEmpty {
            EmptyStateView(systemImage: "square.stack.3d.up.slash", title: "No Jobs",
                           subtitle: "This run hasn't started any jobs.")
        } else {
            HStack(spacing: 0) {
                SelectableList(items: entries, selection: viewModel.selectedJobID.map(Entry.ID.job) ?? .summary,
                               onSelect: select) { entry in
                    switch entry {
                    case .summary: CISummaryRow()
                    case .job(let job): CIJobRow(job: job)
                    }
                }
                .frame(width: 220)
                Rectangle().fill(Theme.border).frame(width: 0.5)
                if viewModel.selectedJob == nil {
                    CIRunSummaryView()
                } else {
                    CILogView { Task { await viewModel.showSummary() } }
                        .environment(viewModel.log)
                }
            }
        }
    }

    private var entries: [Entry] { [.summary] + viewModel.jobs.map(Entry.job) }

    private func select(_ entry: Entry) {
        Task {
            switch entry {
            case .summary: await viewModel.showSummary()
            case .job(let job): await viewModel.selectJob(job)
            }
        }
    }

    /// The summary sits first in the list, so it can be returned to like any job.
    private enum Entry: Identifiable {
        case summary
        case job(CIJob)

        enum ID: Hashable {
            case summary
            case job(Int)
        }

        var id: ID {
            switch self {
            case .summary: .summary
            case .job(let job): .job(job.id)
            }
        }
    }
}

private struct CISummaryRow: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "house")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            Text("Summary")
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }
}

struct CIJobRow: View {
    let job: CIJob

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CIStatusIcon(status: job.status, size: 12)
                .frame(width: 16)
            Text(job.name)
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: Theme.Spacing.xs)
            // A skipped job "ran" for no time; the status says enough.
            if job.status != .skipped {
                CIElapsedText(start: job.startedDate, end: job.completedDate, isActive: job.status.isActive)
            }
        }
        .help(job.name)
    }
}

struct CIStepRow: View {
    let step: CIStep

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CIStatusIcon(status: step.status, size: 12)
                .frame(width: 16)
            Text(step.name)
                .font(.rowTitle)
                .foregroundStyle(step.status == .skipped || step.status == .queued ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            CIElapsedText(start: step.startedDate, end: step.completedDate, isActive: step.status == .inProgress)
        }
    }
}

/// `1m 12s`; counts up once a second while `isActive`.
struct CIElapsedText: View {
    let start: Date?
    let end: Date?
    var isActive = false

    var body: some View {
        if let start {
            if isActive {
                TimelineView(.periodic(from: start, by: 1)) { context in label(context.date.timeIntervalSince(start)) }
            } else if let end {
                label(end.timeIntervalSince(start))
            }
        }
    }

    private func label(_ interval: TimeInterval) -> some View {
        Text(CIDuration.text(max(0, interval)))
            .font(.monoCaption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIJobsView()
        .environment(vm)
        .frame(width: 640, height: 360)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.show(MockData.ciRuns[3]) }
}
