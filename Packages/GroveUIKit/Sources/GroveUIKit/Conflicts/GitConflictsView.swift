// Conflicts/GitConflictsView.swift
// GroveUIKit
//
// Only the operation's conflicts: the banner and the conflicted files beside the resolver.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitConflictsView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: WorkingCopyViewModel
    private let host: GitWorkingCopyHost
    private let onDone: (() -> Void)?

    /// - Parameter onDone: Offered once nothing is in progress, e.g. to go back to the working copy.
    public init(viewModel: WorkingCopyViewModel, host: GitWorkingCopyHost = GitWorkingCopyHost(), onDone: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.host = host
        self.onDone = onDone
    }

    public var body: some View {
        content
            .environment(viewModel)
            .environment(\.workingCopyHost, host)
            .task(id: viewModel.conflictedFiles.map(\.path)) {
                if viewModel.selectedEntry?.isConflicted != true { await viewModel.resolveNextConflict() }
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { host.showsErrors && viewModel.errorMessage != nil },
                                                                set: { if !$0 { viewModel.clearError() } })) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        let conflicts = viewModel.conflictedFiles
        if conflicts.isEmpty {
            VStack(spacing: GitMetrics.Spacing.md) {
                if viewModel.isInOperation { GitOperationBanner(showsOnlyConflicts: false).frame(maxWidth: 420) }
                GitEmptyState(
                    systemImage: "checkmark.circle", title: viewModel.isInOperation ? "All Conflicts Resolved" : "No Conflicts",
                    subtitle: viewModel.isInOperation ? "Continue to finish, or abort to go back." : "Nothing is waiting to be resolved.",
                    actionTitle: viewModel.isInOperation ? nil : onDone.map { _ in "Back to Changes" }, action: onDone)
            }
            .padding(.bottom, GitMetrics.Spacing.lg)
        } else {
            // A GeometryReader, as the working copy has: the resolver's split view asks for more height than the window has.
            GeometryReader { geo in
                HStack(spacing: GitMetrics.Spacing.md) {
                    VStack(spacing: GitMetrics.Spacing.md) {
                        if viewModel.isInOperation { GitOperationBanner(showsOnlyConflicts: false) }
                        list(conflicts)
                    }
                    .frame(width: 300 * style.fontScale)
                    Group {
                        if let entry = viewModel.selectedEntry, entry.isConflicted {
                            GitConflictResolver(entry: entry).id(entry.path)
                        } else {
                            GitEmptyState(systemImage: "exclamationmark.triangle", title: "Select a Conflicted File")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gitPanel()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(.bottom, GitMetrics.Spacing.lg)
        }
    }

    private func list(_ conflicts: [StatusEntry]) -> some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Conflicts", detail: "\(conflicts.count) left")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(conflicts) { entry in
                        FileStatusRow(entry: entry, status: .conflicted, isStaged: false,
                                      isSelected: viewModel.selectedEntry?.path == entry.path)
                            .onTapGesture { Task { await viewModel.select(entry) } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(entry.path)
                    }
                }
                .padding(GitMetrics.Spacing.sm)
            }
        }
        .gitPanel()
    }
}
#endif
