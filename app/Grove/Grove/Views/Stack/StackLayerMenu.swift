// Views/Stack/StackLayerMenu.swift
// Grove

import SwiftUI

/// Actions on one layer of the Stack tab.
struct StackLayerMenu: View {
    @Environment(StackViewModel.self) private var viewModel
    let layer: StackLayer
    let onNewBranch: (StackLayer) -> Void

    var body: some View {
        Button("Check Out \u{201C}\(layer.branch)\u{201D}", systemImage: "arrow.uturn.backward") {
            Task { await viewModel.checkOut(layer) }
        }
        .disabled(layer.isHEAD || layer.worktreePath != nil)
        Button("New Branch on Top\u{2026}", systemImage: "plus.square.on.square") { onNewBranch(layer) }
        if let pullRequest = layer.pullRequest, !pullRequest.isMerged {
            BranchPullRequestButton(pullRequest: pullRequest)
        } else {
            Button("Create Pull Request\u{2026}", systemImage: "arrow.triangle.pull") { viewModel.createPullRequest(for: layer) }
        }
        Button("Push", systemImage: "arrow.up") { Task { await viewModel.push(layer) } }
            .disabled(layer.health.isDisjoint(with: [.unpushed, .diverged]))
        Divider()
        Button("Restack from Here", systemImage: "arrow.triangle.2.circlepath") { Task { await viewModel.restack(from: layer) } }
        Menu("Move onto", systemImage: "arrow.turn.down.right") {
            ForEach(viewModel.moveTargets(for: layer), id: \.self) { target in
                Button(target) { Task { await viewModel.move(layer, onto: target) } }
            }
        }
        Button("Fold into \u{201C}\(layer.parent ?? "parent")\u{201D}", systemImage: "arrow.down.to.line") {
            Task { await viewModel.fold(layer) }
        }
        .disabled(!viewModel.canFold(layer))
    }
}
