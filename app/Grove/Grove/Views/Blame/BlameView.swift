// Views/Blame/BlameView.swift
// Grove
//
// The Blame tab, from GroveUIKit, with what only Grove has: showing a blamed commit in History.

import GroveKit
import GroveUIKit
import SwiftUI

struct BlameView: View {
    let viewModel: BlameViewModel
    let session: RepositorySession

    var body: some View {
        GitBlameView(viewModel: viewModel, host: host)
            .padding(.bottom, Theme.Spacing.md)
    }

    private var host: GitBlameHost {
        var host = GitBlameHost()
        host.showInHistory = { [session] sha in Task { await session.revealInHistory(sha) } }
        return host
    }
}

#Preview {
    let session = RepositorySession(repository: MockGitRepository())
    BlameView(viewModel: session.blameVM, session: session)
        .frame(width: 1100, height: 600)
        .padding()
        .background(Theme.background)
        .task { await session.blameVM.open(file: "Sources/App.swift") }
}
