// Stashes/GitStashesView.swift
// GroveUIKit
//
// The stash list beside the selected stash's changes; apply, pop, drop, branch from it, or find the commit it was made on.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitStashesView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: StashesViewModel
    private let dialogs: GitDialogContext
    private let presenter: GitDialogPresenter?
    private let options: GitDiffOptions?
    private let hasChanges: Bool
    @State private var ownPresenter = GitDialogPresenter()

    /// - Parameters:
    ///   - viewModel: Applies, pops and drops through its `commands`; Reveal Base shows when its `onRevealInHistory` is set.
    ///   - dialogs: Stash, Snapshot and New Branch from Stash run against it.
    ///   - presenter: Where those dialogs show; nil shows them on this view.
    ///   - options: The app's diff options; nil keeps them for the view's life.
    ///   - hasChanges: Whether there's anything to stash.
    public init(viewModel: StashesViewModel, dialogs: GitDialogContext, presenter: GitDialogPresenter? = nil,
                options: GitDiffOptions? = nil, hasChanges: Bool = true) {
        self.viewModel = viewModel
        self.dialogs = dialogs
        self.presenter = presenter
        self.options = options
        self.hasChanges = hasChanges
    }

    public var body: some View {
        let present: (GitDialog) -> Void = { (presenter ?? ownPresenter).present($0, context: dialogs) }
        VStack(spacing: GitMetrics.Spacing.md) {
            if let error = viewModel.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: error, tone: .negative) { viewModel.dismissError() }
            }
            GeometryReader { geometry in
                HStack(spacing: GitMetrics.Spacing.md) {
                    StashListPanel(viewModel: viewModel, hasChanges: hasChanges, present: present)
                        .frame(width: min(320 * style.fontScale, geometry.size.width * 0.4))
                    StashDetailPanel(viewModel: viewModel, options: options, present: present)
                }
            }
        }
        .confirmationDialog(title, isPresented: Binding(get: { viewModel.pendingOperation != nil },
                                                        set: { if !$0 { viewModel.cancelPendingOperation() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingOperation) { pending in
            Button(pending.operation.title, role: pending.operation == .drop ? .destructive : nil) {
                Task {
                    viewModel.dismissError()
                    await viewModel.confirm(pending)
                }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPendingOperation() }
        } message: { pending in
            Text(Self.message(pending))
        }
        .modifier(StashDialogs(presenter: presenter == nil ? ownPresenter : nil))
    }

    private var title: String {
        guard let pending = viewModel.pendingOperation else { return "" }
        return "\(pending.operation.title) stash@{\(pending.stash.id)}?"
    }

    private static func message(_ pending: StashesViewModel.PendingOperation) -> String {
        let name = "\u{201C}\(pending.stash.displayMessage)\u{201D}"
        return switch pending.operation {
        case .apply: "Applies \(name) to your working copy and keeps the stash."
        case .pop: "Applies \(name) to your working copy and removes the stash."
        case .drop: "Permanently deletes \(name). This can't be undone."
        }
    }
}

private struct StashDialogs: ViewModifier {
    let presenter: GitDialogPresenter?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let presenter { content.gitDialogs(presenter) } else { content }
    }
}

/// The stashes, newest first, draggable onto the working copy as `stash@{N}`.
private struct StashListPanel: View {
    @Environment(\.gitStyle) private var style
    let viewModel: StashesViewModel
    let hasChanges: Bool
    let present: (GitDialog) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Stashes", detail: "\(viewModel.stashes.count)") {
                if viewModel.isLoading && !viewModel.stashes.isEmpty { ProgressView().controlSize(.small) }
                Menu {
                    Button("Stash Changes") { present(.stash()) }
                    Button("Save Snapshot") { present(.snapshot) }
                } label: {
                    Image(systemName: "plus")
                } primaryAction: {
                    present(.stash())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .gitClickable()
                .disabled(!hasChanges)
                .help("Stash Changes")
                .accessibilityLabel("Stash Changes")
            }
            if viewModel.isLoading && viewModel.stashes.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.stashes.isEmpty {
                GitEmptyState(systemImage: "tray.2", title: "No Stashes",
                              subtitle: "Stash your changes to set work aside without committing.",
                              actionTitle: hasChanges ? "Stash Changes" : nil) { present(.stash()) }
            } else {
                GitSelectableList(items: viewModel.stashes, selection: viewModel.selectedStash?.id,
                                  onSelect: { stash in Task { await viewModel.select(stash) } }) { stash in
                    StashRow(stash: stash)
                        .draggable("stash@{\(stash.id)}")
                        .contextMenu { StashMenu(viewModel: viewModel, stash: stash, present: present) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .gitPanel()
        .task {
            if viewModel.selectedStash == nil, let first = viewModel.stashes.first { await viewModel.select(first) }
        }
        .onChange(of: viewModel.stashes.first?.sha) { _, _ in
            if viewModel.selectedStash == nil, let first = viewModel.stashes.first { Task { await viewModel.select(first) } }
        }
    }
}

struct StashMenu: View {
    @Environment(\.gitHost) private var host
    let viewModel: StashesViewModel
    let stash: StashEntry
    let present: (GitDialog) -> Void

    var body: some View {
        Button("Apply Stash", systemImage: "arrow.down.doc") { viewModel.request(.apply, on: stash) }
        Button("Pop Stash", systemImage: "arrow.up.bin") { viewModel.request(.pop, on: stash) }
        Button("New Branch from Stash", systemImage: "arrow.triangle.branch") { present(.branchFromStash(index: stash.id)) }
        if viewModel.onRevealInHistory != nil {
            Button("Reveal Base Commit in History", systemImage: "clock.arrow.circlepath") {
                Task { await viewModel.revealBaseInHistory(stash) }
            }
        }
        Button("Copy Message", systemImage: "doc.on.doc") { host.copy(stash.message) }
        Divider()
        Button("Drop Stash", systemImage: "trash", role: .destructive) { viewModel.request(.drop, on: stash) }
    }
}

struct StashRow: View {
    @Environment(\.gitStyle) private var style
    let stash: StashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stash.displayMessage)
                .font(style.font(13, .medium))
                .foregroundStyle(style.textPrimary)
                .lineLimit(1)
            HStack(spacing: GitMetrics.Spacing.sm) {
                Text("stash@{\(stash.id)}")
                if let branch = stash.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(stash.date, format: .relative(presentation: .named))
            }
            .font(style.monoCaption)
            .foregroundStyle(style.textSecondary)
            .labelStyle(.titleAndIcon)
        }
    }
}

extension StashEntry {
    /// The message without "On main: " or "WIP on main: "; the branch shows apart.
    var displayMessage: String {
        guard message.hasPrefix("On ") || message.hasPrefix("WIP on "), let range = message.range(of: ": ") else { return message }
        return String(message[range.upperBound...])
    }
}
#endif
