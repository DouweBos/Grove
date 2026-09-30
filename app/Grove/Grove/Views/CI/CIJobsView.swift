// Views/CI/CIJobsView.swift
// Grove

import SwiftUI

/// A run's jobs on the left, the selected job's steps and log on the right.
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
                SelectableList(items: viewModel.jobs, selection: viewModel.selectedJobID,
                               onSelect: { job in Task { await viewModel.selectJob(job) } }) { job in
                    CIJobRow(job: job)
                }
                .frame(width: 220)
                Rectangle().fill(Theme.border).frame(width: 0.5)
                CILogView()
                    .environment(viewModel.log)
            }
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
