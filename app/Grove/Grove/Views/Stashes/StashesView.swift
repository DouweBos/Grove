// Views/Stashes/StashesView.swift
// Grove

import GroveKit
import SwiftUI

/// Stash list panel on the left, selected stash's changes on the right.
struct StashesView: View {

    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            StashListPanel()
                .frame(width: 320)
            StashDetailPanel()
        }
        .padding(.bottom, Theme.Spacing.md)
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { viewModel.pendingOperation != nil },
                set: { if !$0 { viewModel.cancelPendingOperation() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingOperation
        ) { pending in
            Button(pending.operation.title, role: pending.operation == .drop ? .destructive : nil) {
                Task { await viewModel.confirm(pending) }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPendingOperation() }
        } message: { pending in
            Text(dialogMessage(pending))
        }
        .alert("Stash Operation Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var dialogTitle: String {
        guard let pending = viewModel.pendingOperation else { return "" }
        return "\(pending.operation.title) stash@{\(pending.stash.id)}?"
    }

    private func dialogMessage(_ pending: StashesViewModel.PendingOperation) -> String {
        switch pending.operation {
        case .apply: "Applies \u{201C}\(pending.stash.displayMessage)\u{201D} to your working copy and keeps the stash."
        case .pop: "Applies \u{201C}\(pending.stash.displayMessage)\u{201D} to your working copy and removes the stash."
        case .drop: "Permanently deletes \u{201C}\(pending.stash.displayMessage)\u{201D}. This can't be undone."
        }
    }
}

// MARK: - List Panel

private struct StashListPanel: View {
    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Stashes", detail: "\(viewModel.stashes.count)") {
                if viewModel.isLoading && !viewModel.stashes.isEmpty { ProgressView().controlSize(.small) }
                Menu {
                    Button("Stash Changes\u{2026}") { GroveAction.stash.post() }
                    Button("Save Snapshot\u{2026}") { GroveAction.saveSnapshot.post() }
                } label: {
                    Image(systemName: "plus")
                } primaryAction: {
                    GroveAction.stash.post()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Stash Changes\u{2026}")
            }
            if viewModel.isLoading && viewModel.stashes.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.stashes.isEmpty {
                EmptyStateView(systemImage: "tray.2", title: "No Stashes",
                               subtitle: "Stash your changes to set work aside without committing.",
                               actionTitle: "Stash Changes\u{2026}") { GroveAction.stash.post() }
            } else {
                SelectableList(items: viewModel.stashes, selection: viewModel.selectedStash?.id,
                               onSelect: { stash in Task { await viewModel.select(stash) } }) { stash in
                    StashRow(stash: stash)
                        .draggable("stash@{\(stash.id)}")
                        .contextMenu {
                            Button("Apply Stash", systemImage: "arrow.down.doc") { viewModel.request(.apply, on: stash) }
                            Button("Pop Stash", systemImage: "arrow.up.bin") { viewModel.request(.pop, on: stash) }
                            Button("Reveal Base Commit in History", systemImage: "clock.arrow.circlepath") {
                                Task { await viewModel.revealBaseInHistory(stash) }
                            }
                            Divider()
                            Button("Drop Stash\u{2026}", systemImage: "trash", role: .destructive) { viewModel.request(.drop, on: stash) }
                        }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
        .task {
            if viewModel.selectedStash == nil, let first = viewModel.stashes.first { await viewModel.select(first) }
        }
        .onChange(of: viewModel.stashes.first?.sha) { _, _ in
            if viewModel.selectedStash == nil, let first = viewModel.stashes.first {
                Task { await viewModel.select(first) }
            }
        }
    }
}

struct StashRow: View {
    let stash: StashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stash.displayMessage)
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            HStack(spacing: Theme.Spacing.sm) {
                Text("stash@{\(stash.id)}")
                if let branch = stash.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(stash.date, format: .relative(presentation: .named))
            }
            .font(.monoCaption)
            .foregroundStyle(Theme.textSecondary)
            .labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - Detail Panel

private struct StashDetailPanel: View {
    @Environment(StashesViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let stash = viewModel.selectedStash {
                VStack(spacing: 0) {
                    header(stash)
                    Rectangle().fill(Theme.border).frame(height: 0.5)
                    // TODO: Untracked files live in the stash's third parent, so their image diff is missing a side.
                    ChangesetBrowser(files: viewModel.stashDiffs, selectedPath: viewModel.selectedFilePath,
                                     isLoading: viewModel.isLoadingDiff, emptyTitle: "Empty Stash",
                                     imageSource: .commit(stash.sha, in: viewModel.repository)) {
                        viewModel.selectFile($0)
                    }
                }
            } else {
                EmptyStateView(systemImage: "tray.2", title: "No Stash Selected",
                               subtitle: "Select a stash to see the changes it holds.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    private func header(_ stash: StashEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(stash.displayMessage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.md) {
                    Text("stash@{\(stash.id)}")
                    Text(String(stash.sha.prefix(7))).textSelection(.enabled)
                    Button { Task { await viewModel.revealBaseInHistory(stash) } } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal the commit this stash was made on in History")
                    .accessibilityLabel("Reveal base commit in History")
                    if let branch = stash.branchName { Label(branch, systemImage: "arrow.triangle.branch") }
                    Text(stash.date.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            HStack(spacing: Theme.Spacing.sm) {
                Button("Drop\u{2026}", role: .destructive) { viewModel.request(.drop, on: stash) }
                Button("Pop") { viewModel.request(.pop, on: stash) }
                Button("Apply") { viewModel.request(.apply, on: stash) }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(viewModel.isPerforming)
        }
        .padding(Theme.Spacing.lg)
    }
}

extension StashEntry {
    /// Message without the "On main: " / "WIP on main: " prefix; the branch is shown separately.
    var displayMessage: String {
        guard message.hasPrefix("On ") || message.hasPrefix("WIP on "),
              let range = message.range(of: ": ") else { return message }
        return String(message[range.upperBound...])
    }
}

#Preview {
    let vm = StashesViewModel(repository: MockGitRepository())
    return StashesView()
        .environment(vm)
        .frame(width: 960, height: 560)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
