// Views/Reflog/ReflogView.swift
// Grove

import SwiftUI

/// Reflog entries on the left, the selected entry's commit and restore actions on the right.
struct ReflogView: View {

    @Environment(ReflogViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ReflogListPanel()
                .frame(width: 360)
            ReflogDetailPanel()
        }
        .padding(.bottom, Theme.Spacing.md)
        .confirmationDialog(
            resetTitle,
            isPresented: Binding(get: { viewModel.pendingReset != nil },
                                 set: { if !$0 { viewModel.cancelReset() } }),
            titleVisibility: .visible,
            presenting: viewModel.pendingReset
        ) { pending in
            Button(pending.mode == .hard ? "Discard Changes and Reset" : "Reset",
                   role: pending.mode == .hard ? .destructive : nil) {
                Task { await viewModel.confirmReset(pending) }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelReset() }
        } message: { pending in
            Text(resetMessage(pending))
        }
        .sheet(item: Binding(get: { viewModel.branchSource }, set: { if $0 == nil { viewModel.cancelCreateBranch() } })) { entry in
            ReflogCreateBranchSheet(entry: entry, index: viewModel.index(of: entry)).environment(viewModel)
        }
        .alert("Reflog Action Failed", isPresented: Binding(get: { viewModel.errorMessage != nil },
                                                           set: { if !$0 { viewModel.dismissError() } })) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var resetTitle: String {
        guard let pending = viewModel.pendingReset else { return "" }
        return "Reset HEAD to HEAD@{\(pending.index)}?"
    }

    private func resetMessage(_ pending: ReflogViewModel.PendingReset) -> String {
        let sha = String(pending.entry.newSHA.prefix(7))
        switch pending.mode {
        case .soft: return "Moves HEAD to \(sha). Your index and working tree stay as they are."
        case .mixed: return "Moves HEAD to \(sha) and unstages everything. Working tree files are kept."
        case .hard: return "Moves HEAD to \(sha) and permanently discards all uncommitted changes."
        }
    }
}

// MARK: - List Panel

private struct ReflogListPanel: View {
    @Environment(ReflogViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Reflog", detail: "HEAD \u{00B7} \(viewModel.entries.count)") {
                if viewModel.isLoading && !viewModel.entries.isEmpty { ProgressView().controlSize(.small) }
            }
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No Reflog Entries",
                               subtitle: "HEAD movements such as commits, checkouts and resets appear here.")
            } else {
                SelectableList(items: indexedEntries, selection: viewModel.selectedEntry?.id,
                               onSelect: { item in Task { await viewModel.select(item.entry) } }) { item in
                    ReflogRow(entry: item.entry, index: item.index, action: viewModel.actionType(for: item.entry))
                        .contextMenu { contextMenu(item.entry) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private var indexedEntries: [IndexedEntry] {
        viewModel.entries.enumerated().map { IndexedEntry(index: $0.offset, entry: $0.element) }
    }

    @ViewBuilder
    private func contextMenu(_ entry: ReflogEntry) -> some View {
        Button("Create Branch Here\u{2026}", systemImage: "arrow.triangle.branch") { viewModel.beginCreateBranch(from: entry) }
        Divider()
        Button("Soft Reset to Here\u{2026}") { viewModel.requestReset(to: entry, mode: .soft) }
        Button("Mixed Reset to Here\u{2026}") { viewModel.requestReset(to: entry, mode: .mixed) }
        Button("Hard Reset to Here\u{2026}", role: .destructive) { viewModel.requestReset(to: entry, mode: .hard) }
        Divider()
        Button("Copy SHA", systemImage: "doc.on.doc") { GroveClipboard.copy(entry.newSHA) }
    }
}

private struct IndexedEntry: Identifiable {
    let index: Int
    let entry: ReflogEntry
    var id: String { entry.id }
}

private struct ReflogRow: View {
    let entry: ReflogEntry
    let index: Int
    let action: ReflogActionType

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(action.color)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(ReflogEntryText.detail(of: entry.message))
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.sm) {
                    Text("HEAD@{\(index)}")
                    Text(String(entry.newSHA.prefix(7)))
                    Spacer(minLength: 0)
                    Text(entry.date, format: .relative(presentation: .named))
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

enum ReflogEntryText {
    /// Message without its "commit: " style prefix, which the icon already conveys.
    static func detail(of message: String) -> String {
        guard let range = message.range(of: ": ") else { return message }
        return String(message[range.upperBound...])
    }
}

enum GroveClipboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension ReflogActionType {
    var color: Color {
        switch self {
        case .commit: Theme.success
        case .commitAmend, .checkout: Theme.info
        case .rebase: Theme.warning
        case .merge: Theme.renamed
        case .pull, .push: Theme.accent
        case .reset: Theme.danger
        case .cherryPick: Theme.laneColor(5)
        case .other: Theme.textSecondary
        }
    }
}

#Preview {
    let vm = ReflogViewModel(repository: MockGitRepository())
    return ReflogView()
        .environment(vm)
        .frame(width: 980, height: 560)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
