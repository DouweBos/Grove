// Views/PullRequests/PRActionBar.swift
// Grove

import SwiftUI

/// Bottom action bar for an open pull request.
///
/// Provides "Check Out", "Close", and — for open PRs — "Merge" buttons.
/// The view is inert; actions are delivered via closures so it can be
/// driven by any parent without needing environment access.
struct PRActionBar: View {

    let pr: PullRequestInfo
    let onCheckout: () -> Void
    let onClose: () -> Void
    let onMerge: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Check Out
            Button("Check Out") {
                onCheckout()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // Merge — only visible for open PRs
            if pr.state == .open {
                Button("Merge") {
                    onMerge()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
            }

            Spacer()

            // Close
            if pr.state == .open {
                Button("Close", role: .destructive) {
                    onClose()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    VStack(spacing: 0) {
        Spacer()
        Divider()
        PRActionBar(
            pr: MockData.pullRequests[0],
            onCheckout: {},
            onClose: {},
            onMerge: {}
        )
    }
    .frame(width: 480, height: 80)
}
