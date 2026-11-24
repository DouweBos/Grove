// Reflog/GitReflogView.swift
// GroveUIKit
//
// Where HEAD has been: entries on the left, the selected one's commit, changes and restore actions on the right.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitReflogView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: ReflogViewModel
    private let dialogs: GitDialogContext
    private let presenter: GitDialogPresenter?
    private let options: GitDiffOptions?
    @State private var ownPresenter = GitDialogPresenter()

    /// - Parameters:
    ///   - viewModel: Resets through its `commands`.
    ///   - dialogs: New Branch at an entry runs against it, so the branch can track, pin and be undone like any other.
    ///   - presenter: Where that dialog shows; nil shows it on this view.
    ///   - options: The app's diff options; nil keeps them for the view's life.
    public init(viewModel: ReflogViewModel, dialogs: GitDialogContext, presenter: GitDialogPresenter? = nil,
                options: GitDiffOptions? = nil) {
        self.viewModel = viewModel
        self.dialogs = dialogs
        self.presenter = presenter
        self.options = options
    }

    public var body: some View {
        let actions = ReflogActions(viewModel: viewModel) { (presenter ?? ownPresenter).present($0, context: dialogs) }
        VStack(spacing: GitMetrics.Spacing.md) {
            if let error = viewModel.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: error, tone: .negative) { viewModel.dismissError() }
            }
            GeometryReader { geometry in
                HStack(spacing: GitMetrics.Spacing.md) {
                    ReflogListPanel(viewModel: viewModel, actions: actions)
                        .frame(width: min(360 * style.fontScale, geometry.size.width * 0.42))
                    ReflogDetailPanel(viewModel: viewModel, actions: actions, options: options)
                }
            }
        }
        .confirmationDialog(resetTitle, isPresented: Binding(get: { viewModel.pendingReset != nil },
                                                             set: { if !$0 { viewModel.cancelReset() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingReset) { pending in
            Button(pending.mode == .hard ? "Discard Changes and Reset" : "Reset", role: pending.mode == .hard ? .destructive : nil) {
                Task {
                    viewModel.dismissError()
                    await viewModel.confirmReset(pending)
                }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelReset() }
        } message: { pending in
            Text(Self.resetMessage(pending))
        }
        .modifier(ReflogDialogs(presenter: presenter == nil ? ownPresenter : nil))
    }

    private var resetTitle: String {
        guard let pending = viewModel.pendingReset else { return "" }
        return "Reset HEAD to HEAD@{\(pending.index)}?"
    }

    private static func resetMessage(_ pending: ReflogViewModel.PendingReset) -> String {
        let sha = String(pending.entry.newSHA.prefix(7))
        return switch pending.mode {
        case .soft: "Moves HEAD to \(sha). Your index and working tree stay as they are."
        case .mixed: "Moves HEAD to \(sha) and unstages everything. Working tree files are kept."
        case .hard: "Moves HEAD to \(sha) and permanently discards all uncommitted changes."
        }
    }
}

private struct ReflogDialogs: ViewModifier {
    let presenter: GitDialogPresenter?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let presenter { content.gitDialogs(presenter) } else { content }
    }
}

/// What an entry offers, from its menu and the detail's buttons.
struct ReflogActions {
    let viewModel: ReflogViewModel
    let present: (GitDialog) -> Void
}

struct ReflogMenu: View {
    @Environment(\.gitHost) private var host
    let entry: ReflogEntry
    let actions: ReflogActions

    var body: some View {
        Button("New Branch Here", systemImage: "arrow.triangle.branch") { actions.present(.createBranch(from: entry.newSHA)) }
            .requires(.createBranch)
        Divider()
        Button("Soft Reset to Here") { actions.viewModel.requestReset(to: entry, mode: .soft) }
        Button("Mixed Reset to Here") { actions.viewModel.requestReset(to: entry, mode: .mixed) }
        Button("Hard Reset to Here", role: .destructive) { actions.viewModel.requestReset(to: entry, mode: .hard) }
        Divider()
        Button("Copy SHA", systemImage: "doc.on.doc") { host.copy(entry.newSHA) }
    }
}

private struct ReflogListPanel: View {
    let viewModel: ReflogViewModel
    let actions: ReflogActions

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Reflog", detail: "HEAD \u{00B7} \(viewModel.entries.count)") {
                if viewModel.isLoading && !viewModel.entries.isEmpty { ProgressView().controlSize(.small) }
            }
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                GitEmptyState(systemImage: "clock.arrow.circlepath", title: "No Reflog Entries",
                              subtitle: "HEAD movements such as commits, checkouts and resets appear here.")
            } else {
                GitSelectableList(items: indexed, selection: viewModel.selectedEntry?.id,
                                  onSelect: { item in Task { await viewModel.select(item.entry) } }) { item in
                    ReflogRow(entry: item.entry, index: item.index, action: viewModel.actionType(for: item.entry))
                        .contextMenu { ReflogMenu(entry: item.entry, actions: actions) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .gitPanel()
    }

    private var indexed: [IndexedEntry] {
        viewModel.entries.enumerated().map { IndexedEntry(index: $0.offset, entry: $0.element) }
    }
}

private struct IndexedEntry: Identifiable {
    let index: Int
    let entry: ReflogEntry
    var id: String { entry.id }
}

private struct ReflogRow: View {
    @Environment(\.gitStyle) private var style
    let entry: ReflogEntry
    let index: Int
    let action: ReflogActionType

    var body: some View {
        HStack(alignment: .top, spacing: GitMetrics.Spacing.sm) {
            Image(systemName: action.systemImage)
                .font(style.font(14))
                .foregroundStyle(action.color(style))
                .frame(width: 18 * style.fontScale)
                .padding(.top, 1)
                .help(action.displayName)
            VStack(alignment: .leading, spacing: 3) {
                Text(ReflogEntryText.detail(of: entry.message))
                    .font(style.font(13, .medium))
                    .foregroundStyle(style.textPrimary)
                    .lineLimit(1)
                HStack(spacing: GitMetrics.Spacing.sm) {
                    Text("HEAD@{\(index)}")
                    Text(String(entry.newSHA.prefix(7)))
                    Spacer(minLength: 0)
                    Text(entry.date, format: .relative(presentation: .named)).lineLimit(1)
                }
                .font(style.monoCaption)
                .foregroundStyle(style.textSecondary)
            }
        }
    }
}

enum ReflogEntryText {
    /// The message without its "commit: " style prefix, which the icon already says.
    static func detail(of message: String) -> String {
        guard let range = message.range(of: ": ") else { return message }
        return String(message[range.upperBound...])
    }
}

extension ReflogActionType {
    func color(_ style: GitUIStyle) -> Color {
        switch self {
        case .commit: style.success
        case .commitAmend, .checkout: style.info
        case .rebase: style.warning
        case .merge: style.renamed
        case .pull, .push: style.accent
        case .reset: style.danger
        case .cherryPick: style.lane(5)
        case .other: style.textSecondary
        }
    }
}
#endif
