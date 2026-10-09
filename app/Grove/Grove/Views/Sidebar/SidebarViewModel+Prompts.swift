// Views/Sidebar/SidebarViewModel+Prompts.swift
// Grove
//
// Sheets and confirmations sidebar rows ask for. The sidebar presents them outside its List,
// since a List hands a section's modifiers to every row and each copy would present again.

import GroveKit

enum SidebarSheet: Identifiable {
    case createBranch(from: String)
    case renameBranch(BranchInfo)
    case deleteBranch(BranchInfo)
    case trackRemoteBranch(BranchInfo)

    var id: String {
        switch self {
        case .createBranch(let ref): "create:\(ref)"
        case .renameBranch(let branch): "rename:\(branch.id)"
        case .deleteBranch(let branch): "delete:\(branch.id)"
        case .trackRemoteBranch(let branch): "track:\(branch.id)"
        }
    }
}

enum SidebarConfirmation: Identifiable {
    case removeRemote(RemoteInfo)
    case deleteRemoteBranch(BranchInfo)
    case deleteTag(TagInfo)
    case removeSubmodule(SubmoduleInfo)

    var id: String {
        switch self {
        case .removeRemote(let remote): "remote:\(remote.id)"
        case .deleteRemoteBranch(let branch): "remoteBranch:\(branch.id)"
        case .deleteTag(let tag): "tag:\(tag.id)"
        case .removeSubmodule(let submodule): "submodule:\(submodule.id)"
        }
    }
}

extension SidebarViewModel {
    func present(_ sheet: SidebarSheet) { self.sheet = sheet }
    func dismissSheet() { sheet = nil }

    func requestConfirmation(_ confirmation: SidebarConfirmation) { self.confirmation = confirmation }
    func dismissConfirmation() { confirmation = nil }

    func confirm(_ confirmation: SidebarConfirmation) async {
        self.confirmation = nil
        switch confirmation {
        case .removeRemote(let remote): await actions.removeRemote(remote)
        case .deleteRemoteBranch(let branch): await actions.deleteRemoteBranch(branch)
        case .deleteTag(let tag): await actions.deleteTag(tag)
        case .removeSubmodule(let submodule): await actions.removeSubmodule(submodule)
        }
    }
}
