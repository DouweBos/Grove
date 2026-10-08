// Domain/RepositorySession+Intents.swift
// Grove
//
// Views the `grove` command asks for: History on a branch, Blame on a file, the Stack tab on a branch's stack.

import Foundation
import GroveKit

extension RepositorySession {

    /// Refs load first, so a branch named on the command line is there to select.
    func open(_ intent: RepositoryIntent) async {
        await sidebarVM.loadIfNeeded()
        switch intent {
        case .history(let name):
            if let name, let branch = sidebarVM.localBranches.first(where: { $0.name == name }) {
                sidebarVM.select(.branch(branch))
            } else if let name, let branch = sidebarVM.remoteBranches.first(where: { $0.name == name }) {
                sidebarVM.select(.remoteBranch(branch))
            } else {
                sidebarVM.select(.history)
            }
        case .blame(let file):
            sidebarVM.select(.blame)
            await blameVM.open(file: file)
        case .stack(let name):
            if let name, refs.stack(containing: name) != nil {
                sidebarVM.showStack(containing: name)
            } else {
                sidebarVM.select(.stack)
            }
        }
    }
}
