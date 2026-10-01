// Views/CI/CIRunSummaryView.swift
// Grove

import SwiftUI

/// A run at a glance like GitHub's summary: the job graph, then annotations and artifacts, scrolling together.
struct CIRunSummaryView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: Theme.Spacing.md) {
                if let error = viewModel.graphError {
                    Banner(symbol: "exclamationmark.triangle",
                           message: "Couldn\u{2019}t read the workflow file, so jobs aren\u{2019}t linked: \(error)")
                }
                CIGraphView()
                if !viewModel.annotations.isEmpty { CIAnnotationsView() }
                if viewModel.artifactsError != nil || !viewModel.artifacts.isEmpty { CIArtifactsView() }
            }
            .padding(Theme.Spacing.md)
        }
    }
}

extension View {
    /// A summary section: inset from the panel like GitHub's darker cards.
    func summarySection() -> some View {
        background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }
}

/// A section's title and its one-line description.
struct CISummaryHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.sectionLabel)
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIRunSummaryView()
        .environment(vm)
        .frame(width: 760, height: 640)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.show(MockData.ciRuns[3]) }
}
