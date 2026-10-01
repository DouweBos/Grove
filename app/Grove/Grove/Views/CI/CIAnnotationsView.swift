// Views/CI/CIAnnotationsView.swift
// Grove

import SwiftUI

/// The run's annotations under its graph, like GitHub's summary; scrolls once they outgrow the space left.
struct CIAnnotationsView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        let annotations = viewModel.annotations
        ViewThatFits(in: .vertical) {
            content(annotations)
            ScrollView { content(annotations) }
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    private func content(_ annotations: [(job: CIJob, annotation: CIAnnotation)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Annotations")
                    .font(.sectionLabel)
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.summary(annotations.map(\.annotation.level)))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding([.horizontal, .top], Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xs)
            ForEach(Array(annotations.enumerated()), id: \.element.annotation.id) { index, entry in
                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                CIAnnotationRow(job: entry.job, annotation: entry.annotation) { Task { await viewModel.selectJob(entry.job) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `1 error, 2 warnings and 1 notice`.
    static func summary(_ levels: [CIAnnotation.Level]) -> String {
        let parts = [(CIAnnotation.Level.failure, "error"), (.warning, "warning"), (.notice, "notice")].compactMap { level, noun -> String? in
            let count = levels.filter { $0 == level }.count
            return count == 0 ? nil : "\(count) \(noun)\(count == 1 ? "" : "s")"
        }
        return parts.formatted(.list(type: .and))
    }
}

private struct CIAnnotationRow: View {
    let job: CIJob
    let annotation: CIAnnotation
    let onOpenJob: () -> Void

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityLabel(label)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button(action: onOpenJob) {
                    Text(annotation.title.map { "\(job.name): \($0)" } ?? job.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Show \(job.name)\u{2019}s steps and log")
                if let path = annotation.path {
                    Text(annotation.line.map { "\(path):\($0)" } ?? path)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                Text(annotation.message)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(isLong && !isExpanded ? 2 : nil)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if isLong {
                    Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// Rough, since the width isn't known: a few lines' worth gets collapsed to two.
    private var isLong: Bool { annotation.message.count > 300 || annotation.message.split(separator: "\n").count > 3 }

    private var symbol: String {
        switch annotation.level {
        case .failure: "xmark.octagon"
        case .warning: "exclamationmark.triangle"
        case .notice: "info.circle"
        }
    }

    private var tint: Color {
        switch annotation.level {
        case .failure: Theme.danger
        case .warning: Theme.warning
        case .notice: Theme.textSecondary
        }
    }

    private var label: String {
        switch annotation.level {
        case .failure: "Error"
        case .warning: "Warning"
        case .notice: "Notice"
        }
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIAnnotationsView()
        .environment(vm)
        .frame(width: 760)
        .padding()
        .background(Theme.surface)
        .task { await vm.show(MockData.ciRuns[3]) }
}
