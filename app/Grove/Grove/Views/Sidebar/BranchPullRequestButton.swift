// Views/Sidebar/BranchPullRequestButton.swift
// Grove

import AppKit
import GroveKit
import SwiftUI

/// "Open Pull Request #N in Browser", shared by local and remote branch menus.
struct BranchPullRequestButton: View {
    let pullRequest: BranchPullRequest

    var body: some View {
        Button("Open Pull Request \(pullRequest.label) in Browser", systemImage: "arrow.triangle.pull") {
            if let url = URL(string: pullRequest.url) { NSWorkspace.shared.open(url) }
        }
    }
}
