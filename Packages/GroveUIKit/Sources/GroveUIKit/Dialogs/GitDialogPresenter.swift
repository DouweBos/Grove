// Dialogs/GitDialogPresenter.swift
// GroveUIKit
//
// Shows dialogs asked for where no view is around to hang a sheet on: menus, keys, toolbar items.

#if os(macOS)
import GroveKit
import Observation
import SwiftUI

@MainActor
@Observable
public final class GitDialogPresenter {
    public struct Request: Identifiable {
        public let dialog: GitDialog
        let context: GitDialogContext
        public var id: String { dialog.id }
    }

    public private(set) var request: Request?
    /// Each dialog as it closes, and whether it ran.
    @ObservationIgnored public var onClose: ((GitDialog, _ submitted: Bool) -> Void)?
    @ObservationIgnored private var submitted = false

    public init() {}

    /// Replaces whatever dialog is showing.
    public func present(_ dialog: GitDialog, context: GitDialogContext) {
        if let request { onClose?(request.dialog, submitted) }
        submitted = false
        request = Request(dialog: dialog, context: context)
    }

    public func dismiss() {
        guard let request else { return }
        self.request = nil
        onClose?(request.dialog, submitted)
        submitted = false
    }

    fileprivate func finished(_ didSubmit: Bool) {
        submitted = submitted || didSubmit
    }
}

private struct GitDialogPresentation: ViewModifier {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var host
    @Bindable var presenter: GitDialogPresenter

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { presenter.request }, set: { if $0 == nil { presenter.dismiss() } })) { request in
            // A sheet is its own window: the style is handed over again, and follows the presenter's live.
            GitDialogView(request.dialog, context: request.context) { presenter.finished($0) }
                .gitUIStyle(style)
                .gitUIHost(host)
        }
    }
}

extension View {
    /// Shows the presenter's dialogs as sheets on this view's window, in the style set above it.
    public func gitDialogs(_ presenter: GitDialogPresenter) -> some View {
        modifier(GitDialogPresentation(presenter: presenter))
    }
}
#endif
