// DesignSystem/BranchLabel.swift
// Grove
//
// Capsule shown on commit rows for branches and remotes pointing at that commit.

import SwiftUI

struct BranchLabel: View {

    enum Kind {
        case localBranch(isHEAD: Bool)
        case remoteBranch
        case tag
    }

    let name: String
    let kind: Kind
    /// A local branch whose same-named remote branch points at the same commit.
    var isOnRemote = false
    /// Lets the name truncate in tight rows instead of forcing its full width.
    var truncates = false

    var body: some View {
        let label = HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(name).lineLimit(1).truncationMode(.middle)
            if isOnRemote {
                Image(systemName: "cloud").font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel("Also on remote")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        if truncates {
            label.fixedSize(horizontal: false, vertical: true)
        } else {
            label.fixedSize()
        }
    }

    private var symbol: String {
        switch kind {
        case .localBranch(let isHEAD): isHEAD ? "checkmark" : "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag"
        }
    }

    private var color: Color {
        switch kind {
        case .localBranch(let isHEAD): isHEAD ? Theme.accent : Theme.success
        case .remoteBranch: Theme.info
        case .tag: Theme.warning
        }
    }
}

extension BranchLabel {
    init(branch: BranchInfo) {
        self.name = branch.name
        self.kind = branch.isRemote ? .remoteBranch : .localBranch(isHEAD: branch.isHEAD)
    }

    init(tag: TagInfo) {
        self.name = tag.name
        self.kind = .tag
    }
}

#Preview {
    HStack {
        BranchLabel(name: "main", kind: .localBranch(isHEAD: true))
        BranchLabel(name: "feature/auth", kind: .localBranch(isHEAD: false), isOnRemote: true)
        BranchLabel(name: "origin/main", kind: .remoteBranch)
        BranchLabel(name: "v1.0.0", kind: .tag)
    }
    .padding()
    .background(Theme.surface)
}
