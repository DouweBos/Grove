// Views/Sidebar/OpenPullRequestButton.swift
// Grove

import AppKit
import SwiftUI

/// "Open Pull Request #N in Browser", shared by local and remote branch menus.
struct OpenPullRequestButton: View {
    let pullRequest: OpenPullRequest

    var body: some View {
        Button("Open Pull Request \(pullRequest.label) in Browser", systemImage: "arrow.triangle.pull") {
            if let url = URL(string: pullRequest.url) { NSWorkspace.shared.open(url) }
        }
    }
}
