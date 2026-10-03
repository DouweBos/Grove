// Views/CI/CIArtifactsView.swift
// Grove

import GroveKit
import SwiftUI

/// Files the run uploaded, in a table under its graph like GitHub's summary; each downloads as a zip until it expires.
struct CIArtifactsView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CISummaryHeader(title: "Artifacts", subtitle: "Produced during runtime")
                .padding([.horizontal, .top], Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)
            if let error = viewModel.artifactsError, viewModel.artifacts.isEmpty {
                Banner(symbol: "exclamationmark.triangle", message: "Couldn\u{2019}t load the artifacts: \(error)", actionTitle: "Try Again") {
                    Task { await viewModel.reload() }
                }
                .padding([.horizontal, .bottom], Theme.Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    CIArtifactColumns {
                        Text("Name")
                    } size: {
                        Text("Size")
                    } digest: {
                        Text("Digest")
                    } action: {
                        Color.clear.frame(height: 1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, Theme.Spacing.sm)
                    ForEach(viewModel.artifacts) { artifact in
                        Rectangle().fill(Theme.border).frame(height: 1)
                        CIArtifactRow(artifact: artifact, download: viewModel.downloads[artifact.id],
                                      onDownload: { Task { await viewModel.downloadArtifact(artifact) } },
                                      onReveal: { viewModel.revealDownload(of: artifact) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .summarySection()
    }
}

/// One row of the artifacts grid: name, size, digest, and the download or its outcome.
private struct CIArtifactRow: View {
    let artifact: CIArtifact
    var download: CIRunDetailViewModel.Download?
    let onDownload: () -> Void
    let onReveal: () -> Void

    var body: some View {
        CIArtifactColumns {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.name)
                        .font(.rowTitle)
                        .foregroundStyle(artifact.isExpired ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if case .failed(let message) = download {
                        Text("Download failed: \(message)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                            .lineLimit(2)
                    }
                }
            }
        } size: {
            Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeInBytes), countStyle: .file))
                .font(.monoCaption)
                .foregroundStyle(Theme.textPrimary)
        } digest: {
            digest
        } action: {
            action
        }
        .padding(.vertical, Theme.Spacing.md)
        .help(expiry)
    }

    @ViewBuilder private var digest: some View {
        if let digest = artifact.digest {
            HStack(spacing: Theme.Spacing.xs) {
                Text(digest)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                CopyButton(value: digest, help: "Copy Digest", confirmation: "Copied digest")
            }
        } else {
            Text("\u{2014}").font(.monoCaption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var expiry: String {
        if artifact.isExpired { return "Expired" }
        return artifact.expiresDate.map { "Expires \($0.formatted(.relative(presentation: .named)))" } ?? ""
    }

    @ViewBuilder private var action: some View {
        if artifact.isExpired {
            StatusBadge(title: "Expired", symbol: "clock.badge.xmark", tone: .neutral).fixedSize()
        } else {
            switch download {
            case .running:
                ProgressView().controlSize(.small)
            case .saved:
                Button { onReveal() } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            case .failed, nil:
                Button { onDownload() } label: { Image(systemName: "arrow.down.to.line") }
                    .buttonStyle(.borderless)
                    .help("Download \(artifact.name)")
            }
        }
    }
}

/// The table's columns, shared by its header and rows so they line up: the name takes what the others leave.
private struct CIArtifactColumns<Name: View, Size: View, Digest: View, Action: View>: View {
    @ViewBuilder let name: () -> Name
    @ViewBuilder let size: () -> Size
    @ViewBuilder let digest: () -> Digest
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            name().frame(maxWidth: .infinity, alignment: .leading)
            size().frame(width: 80, alignment: .leading)
            digest().frame(width: 280, alignment: .leading)
            action().frame(width: 88, alignment: .trailing)
        }
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIArtifactsView()
        .environment(vm)
        .frame(width: 760)
        .padding()
        .background(Theme.surface)
        .task { await vm.show(MockData.ciRuns[2]) }
}
