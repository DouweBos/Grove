// Refs/GitRefsSidebar.swift
// GroveUIKit
//
// The repository's refs as a sidebar: branches in folders, worktrees, archived branches, remotes, tags and submodules.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitRefsSidebar<Header: View, Branches: View>: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    @Bindable private var model: GitRefsModel
    private let dialogs: GitDialogContext
    private let presenter: GitDialogPresenter?
    @Binding private var selection: GitRefItem?
    private let host: GitRefsHost
    private let header: () -> Header
    private let branches: () -> Branches
    @State private var ownPresenter = GitDialogPresenter()

    /// - Parameters:
    ///   - model: Runs every change through its `actions.commands`.
    ///   - dialogs: New branch, rename, delete, track, push, pull and remote dialogs run against it.
    ///   - presenter: Where the dialogs show; nil shows them on this view.
    ///   - selection: The selected ref; the app decides what it opens.
    ///   - header: Leads the list, not selectable, e.g. the repository's summary.
    ///   - branches: The app's rows after the flat branches, e.g. stacks; `gitRefBranchRow(_:)` gives them branch actions.
    public init(model: GitRefsModel, dialogs: GitDialogContext, presenter: GitDialogPresenter? = nil,
                selection: Binding<GitRefItem?>, host: GitRefsHost = GitRefsHost(),
                @ViewBuilder header: @escaping () -> Header, @ViewBuilder branches: @escaping () -> Branches) {
        self.model = model
        self.dialogs = dialogs
        self.presenter = presenter
        _selection = selection
        self.host = host
        self.header = header
        self.branches = branches
    }

    public var body: some View {
        let context = RefContext(model: model, host: host, present: present)
        List(selection: $selection) {
            if Header.self != EmptyView.self {
                Section { header().listRowSeparator(.hidden).selectionDisabled() }
            }
            BranchesSection(context: context, extra: branches)
            WorktreesSection(context: context)
            ArchivedSection(context: context)
            RemotesSection(context: context)
            TagsSection(context: context)
            SubmodulesSection(context: context)
        }
        .listStyle(.sidebar)
        .environment(\.refContext, context)
        // Double-click or Return; a tap gesture on a row would eat the click that selects it.
        .contextMenu(forSelectionType: GitRefItem.self) { _ in
        } primaryAction: { items in
            guard let item = items.first else { return }
            Task { await model.activate(item, features: features, host: host) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .refPrompts(model, context: context)
        .modifier(OwnDialogs(presenter: presenter == nil ? ownPresenter : nil))
    }

    private func present(_ dialog: GitDialog) {
        (presenter ?? ownPresenter).present(dialog, context: dialogs)
    }

    private var footer: some View {
        VStack(spacing: GitMetrics.Spacing.sm) {
            if let activity = model.actions.activity {
                GitProgressStrip(title: activity, detail: "", fraction: nil)
            } else if host.showsFailures, let message = model.errorMessage {
                GitBanner(symbol: "xmark.octagon", message: message, tone: .negative) { model.dismissError() }
            }
            GitSearchField(placeholder: "Filter", text: model.filter, onChange: { model.filter = $0 })
        }
        .padding(GitMetrics.Spacing.sm)
    }
}

extension GitRefsSidebar where Header == EmptyView, Branches == EmptyView {
    public init(model: GitRefsModel, dialogs: GitDialogContext, presenter: GitDialogPresenter? = nil,
                selection: Binding<GitRefItem?>, host: GitRefsHost = GitRefsHost()) {
        self.init(model: model, dialogs: dialogs, presenter: presenter, selection: selection, host: host,
                  header: { EmptyView() }, branches: { EmptyView() })
    }
}

private struct OwnDialogs: ViewModifier {
    let presenter: GitDialogPresenter?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let presenter { content.gitDialogs(presenter) } else { content }
    }
}

extension EnvironmentValues {
    @Entry var refContext: RefContext?
}

extension View {
    /// An app's own branch row inside `GitRefsSidebar`, e.g. a stack's layer: selection, drag, drops and the branch menu.
    public func gitRefBranchRow(_ branch: BranchInfo, menuLeading: AnyView? = nil) -> some View {
        modifier(HostBranchRow(branch: branch, menuLeading: menuLeading))
    }
}

private struct HostBranchRow: ViewModifier {
    @Environment(\.refContext) private var context
    let branch: BranchInfo
    let menuLeading: AnyView?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let context {
            content.branchActions(branch, context: context, menuLeading: menuLeading)
        } else {
            content
        }
    }
}
#endif
