// History/GitHistoryView.swift
// GroveUIKit
//
// The History screen: the commit list beside the selected commit's detail, side by side when there's room.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitHistoryView: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    private let viewModel: HistoryViewModel
    private let dialogs: GitDialogContext
    private let host: GitHistoryHost
    @State private var presenter = HistoryPresenter()

    /// - Parameters:
    ///   - viewModel: Mutates through its `commands`; set them to the app's for its rules to apply.
    ///   - dialogs: New Branch and New Tag at a commit, and the kit's own comparison.
    public init(viewModel: HistoryViewModel, dialogs: GitDialogContext, host: GitHistoryHost = GitHistoryHost()) {
        self.viewModel = viewModel
        self.dialogs = dialogs
        self.host = host
    }

    public var body: some View {
        let actions = CommitActions(viewModel: viewModel, features: features, host: host, uiHost: uiHost, presenter: presenter)
        GeometryReader { geometry in
            let width = geometry.size.width
            // Side by side needs ~600pt; narrower stacks the panels.
            if width >= Self.sideBySideWidth(fontScale: style.fontScale) {
                HStack(spacing: GitMetrics.Spacing.md) {
                    CommitListPanel(viewModel: viewModel, actions: actions)
                        .frame(width: min(max(280 * style.fontScale, width * 0.44), width - 320 * style.fontScale))
                    CommitDetailPanel(viewModel: viewModel, actions: actions)
                }
            } else {
                VStack(spacing: GitMetrics.Spacing.md) {
                    CommitListPanel(viewModel: viewModel, actions: actions)
                        .frame(height: geometry.size.height * 0.45)
                    CommitDetailPanel(viewModel: viewModel, actions: actions)
                }
            }
        }
        .environment(\.historyHost, host)
        .task { await viewModel.loadIfNeeded() }
        .sheet(item: Binding(get: { viewModel.pendingAction }, set: { if $0 == nil { viewModel.dismissAction() } })) { action in
            HistoryActionSheet(viewModel: viewModel, dialogs: dialogs, action: action)
                .environment(\.historyHost, host)
                .gitUIStyle(style)
                .gitFeatures(features)
                .gitUIHost(uiHost)
        }
        .sheet(item: Binding(get: { presenter.compare }, set: { presenter.compare = $0 })) { request in
            HistoryToolSheet(title: "Compare", done: { presenter.compare = nil }) {
                CompareSheetContent(context: dialogs, base: request.base, compare: request.compare)
            }
            .environment(\.historyHost, host)
            .gitUIStyle(style)
            .gitFeatures(features)
            .gitUIHost(uiHost)
        }
        .confirmationDialog("Check out \(presenter.checkout?.shortSHA ?? "")?",
                            isPresented: Binding(get: { presenter.checkout != nil }, set: { if !$0 { presenter.checkout = nil } }),
                            presenting: presenter.checkout) { commit in
            Button("Check Out") { Task { await viewModel.checkout(commit) } }
        } message: { _ in
            Text("HEAD will be detached at this commit. Commits made there belong to no branch until you create one.")
        }
    }

    static func sideBySideWidth(fontScale: CGFloat) -> CGFloat { 600 * fontScale }
}
#endif
