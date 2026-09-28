// Views/Repositories/CloneJobRow.swift
// Grove

import SwiftUI

/// A background clone in the browser sidebar: progress while it runs, git's error and Retry when it fails.
struct CloneJobRow: View {
    @Environment(WindowViewModel.self) private var viewModel
    let job: CloneQueue.Job

    private var fraction: Double { job.progress?.overallFraction ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: failure == nil ? "arrow.down.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(failure == nil ? Theme.accent : Theme.danger)
                Text(job.name).font(.rowTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
                if failure == nil {
                    Text("\(Int(fraction * 100))%").font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    Button { viewModel.clones.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .help("Cancel Clone")
                        .accessibilityLabel("Cancel Clone")
                }
            }
            if let failure {
                Text(failure).font(.system(size: 11)).foregroundStyle(Theme.danger).lineLimit(3)
                HStack(spacing: Theme.Spacing.sm) {
                    Button("Retry") { viewModel.clones.retry(job.id) }
                    Button("Remove") { viewModel.clones.cancel(job.id) }
                }
                .controlSize(.small)
            } else {
                ProgressView(value: fraction).controlSize(.small).tint(Theme.accent)
                Text(job.progress?.phaseTitle ?? "Connecting").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .help(job.url)
        .contextMenu {
            if failure == nil {
                Button("Cancel Clone", systemImage: "xmark.circle") { viewModel.clones.cancel(job.id) }
            } else {
                Button("Retry", systemImage: "arrow.clockwise") { viewModel.clones.retry(job.id) }
                Button("Remove", systemImage: "trash") { viewModel.clones.cancel(job.id) }
            }
            Button("Copy URL", systemImage: "doc.on.doc") { GroveClipboard.copy(job.url) }
        }
    }

    private var failure: String? {
        if case .failed(let message) = job.state { return message }
        return nil
    }
}

/// The toolbar's small sign that clones are running; clicking goes to the local repository list.
struct CloneActivityIndicator: View {
    @Environment(WindowViewModel.self) private var viewModel

    var body: some View {
        let running = viewModel.clones.runningCount
        // Just the spinner: the sidebar toolbar is narrow, so the count lives in the tooltip.
        Button { viewModel.showLocalRepositories() } label: {
            ProgressView().controlSize(.mini)
        }
        .help(running == 1 ? "Cloning 1 repository" : "Cloning \(running) repositories")
    }
}

#Preview {
    let window = WindowViewModel(manager: MockRepositoryManager())
    return List {
        ForEach(window.clones.jobs) { CloneJobRow(job: $0) }
    }
    .environment(window)
    .frame(width: 260, height: 200)
    .task { window.clones.start(url: "git@github.com:example/app.git", destination: URL(fileURLWithPath: "/tmp/grove-preview-clone")) }
}
