// Views/History/HistoryView.swift
// Grove
//
// The History tab, from GroveUIKit, with what only Grove has: Gravatar pictures, the app's diff settings and Blame.

import CryptoKit
import Foundation
import GroveKit
import GroveUIKit
import SwiftUI

struct HistoryView: View {
    let viewModel: HistoryViewModel
    let session: RepositorySession
    private var settings = DiffSettings()

    init(viewModel: HistoryViewModel, session: RepositorySession) {
        self.viewModel = viewModel
        self.session = session
    }

    var body: some View {
        GitHistoryView(viewModel: viewModel, dialogs: dialogs, host: host)
            .padding(.bottom, Theme.Spacing.md)
    }

    private var dialogs: GitDialogContext {
        .grove(repository: viewModel.repository, refs: viewModel.refs, commands: viewModel.commands,
               undo: viewModel.undoManager) { [viewModel] in
            await viewModel.onRepositoryChanged?()
        }
    }

    private var host: GitHistoryHost {
        var host = GitHistoryHost()
        host.avatarURL = Self.gravatar
        host.diffOptions = settings.options
        host.openBlame = { [session] path, revision in Task { await session.showBlame(file: path, revision: revision) } }
        return host
    }

    /// `d=404` makes Gravatar fail for unknown addresses, so the initials show instead of a stock image.
    static func gravatar(email: String, pixels: Int) -> URL? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8)).map { String(format: "%02hhx", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(pixels)&d=404")
    }
}

#Preview {
    let session = RepositorySession(repository: MockGitRepository())
    HistoryView(viewModel: session.historyVM, session: session)
        .frame(width: 1000, height: 600)
        .padding()
        .background(Theme.background)
}
