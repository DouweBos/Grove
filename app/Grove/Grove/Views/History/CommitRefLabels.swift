// Views/History/CommitRefLabels.swift
// Grove

import SwiftUI

/// Ref labels before a commit's subject: a local branch and its same-named remote branch
/// collapse into one label, and past two labels the rest fold into "+N".
struct CommitRefLabels: View {
    let branches: [BranchInfo]
    let tags: [TagInfo]

    private static let maxShown = 2

    var body: some View {
        let refs = Self.displayRefs(branches: branches, tags: tags)
        if !refs.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(refs.prefix(Self.maxShown)) { ref in
                    BranchLabel(name: ref.name, kind: ref.kind, isOnRemote: ref.isOnRemote, maxNameWidth: 140)
                }
                if refs.count > Self.maxShown {
                    Text("+\(refs.count - Self.maxShown)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.subtleFill, in: Capsule())
                        .fixedSize()
                }
            }
            .help(refs.map(\.fullName).joined(separator: "\n"))
            .layoutPriority(1)
        }
    }

    struct DisplayRef: Identifiable {
        let id: String
        let name: String
        let fullName: String
        let kind: BranchLabel.Kind
        let isOnRemote: Bool
    }

    /// HEAD first, then local branches, remote-only branches and tags.
    static func displayRefs(branches: [BranchInfo], tags: [TagInfo]) -> [DisplayRef] {
        let locals = branches.filter { !$0.isRemote }
        let remotes = branches.filter(\.isRemote)
        func remoteTwin(of local: BranchInfo) -> BranchInfo? {
            remotes.first { $0.name.split(separator: "/", maxSplits: 1).last.map(String.init) == local.name }
        }
        let twinned = Set(locals.compactMap { remoteTwin(of: $0)?.name })
        let localRefs = locals.sorted { $0.isHEAD && !$1.isHEAD }.map { local in
            let twin = remoteTwin(of: local)
            return DisplayRef(id: "l:\(local.name)", name: local.name,
                              fullName: twin.map { "\(local.name) (also \($0.name))" } ?? local.name,
                              kind: .localBranch(isHEAD: local.isHEAD), isOnRemote: twin != nil)
        }
        let remoteRefs = remotes.filter { !twinned.contains($0.name) }.map {
            DisplayRef(id: "r:\($0.name)", name: $0.name, fullName: $0.name, kind: .remoteBranch, isOnRemote: false)
        }
        let tagRefs = tags.map {
            DisplayRef(id: "t:\($0.name)", name: $0.name, fullName: "tag \($0.name)", kind: .tag, isOnRemote: false)
        }
        return localRefs + remoteRefs + tagRefs
    }
}
