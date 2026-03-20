// Views/Repositories/RepositoryBrowserContent.swift
// Grove
//
// Right-side content area of the repository browser.
// Shows either the drop zone (no selection) or the repository info panel.

import SwiftUI

// MARK: - RepositoryBrowserContent

/// Content area that switches between drop zone and repo info panel.
struct RepositoryBrowserContent: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel

    var body: some View {
        if let bookmark = viewModel.selectedBookmark {
            RepositoryInfoPanel(bookmark: bookmark)
        } else {
            RepositoryDropZoneView()
        }
    }
}

// MARK: - Preview

#Preview {
    RepositoryBrowserContent()
        .environment(RepositoryBrowserViewModel(manager: MockRepositoryManager()))
        .frame(width: 580, height: 500)
}
