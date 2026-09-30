// Views/CI/CIArtifactsView.swift
// Grove

import SwiftUI

/// Files the run uploaded, each downloadable as a zip until it expires.
struct CIArtifactsView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingArtifacts {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.artifactsError, viewModel.artifacts.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't Load Artifacts", subtitle: error,
                           actionTitle: "Try Again") { Task { await viewModel.reload() } }
        } else if viewModel.artifacts.isEmpty {
            EmptyStateView(systemImage: "shippingbox", title: "No Artifacts",
                           subtitle: viewModel.run?.status.isActive == true ? "This run hasn't uploaded anything yet."
                               : "This run didn't upload any files.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.artifacts) { artifact in
                        CIArtifactRow(artifact: artifact, download: viewModel.downloads[artifact.id],
                                      onDownload: { Task { await viewModel.downloadArtifact(artifact) } },
                                      onReveal: { viewModel.revealDownload(of: artifact) })
                            .selectableRow(isSelected: false)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
    }
}

struct CIArtifactRow: View {
    let artifact: CIArtifact
    var download: CIRunDetailViewModel.Download?
    let onDownload: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.name)
                    .font(.rowTitle)
                    .foregroundStyle(artifact.isExpired ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.monoCaption)
                    .foregroundStyle(isFailed ? Theme.danger : Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.sm)
            action
        }
    }

    private var isFailed: Bool {
        if case .failed = download { return true }
        return false
    }

    private var detail: String {
        if case .failed(let message) = download { return "Download failed: \(message)" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeInBytes), countStyle: .file)
        guard !artifact.isExpired, let expires = artifact.expiresDate else { return size }
        return "\(size) \u{00B7} expires \(expires.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private var action: some View {
        if artifact.isExpired {
            StatusBadge(title: "Expired", symbol: "clock.badge.xmark", tone: .neutral)
        } else {
            switch download {
            case .running:
                ProgressView().controlSize(.small)
            case .saved:
                Button("Show in Finder", action: onReveal)
            case .failed, nil:
                Button(action: onDownload) { Label("Download", systemImage: "arrow.down.circle") }
            }
        }
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIArtifactsView()
        .environment(vm)
        .frame(width: 560, height: 240)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.show(MockData.ciRuns[2]) }
}
