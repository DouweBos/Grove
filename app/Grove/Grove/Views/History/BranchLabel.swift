// Views/History/BranchLabel.swift
// Grove

import SwiftUI

/// A colored pill label shown inline on commit rows to indicate branch/tag association.
///
/// - Green: local branch (HEAD branch uses accent color)
/// - Blue: remote-tracking branch
/// - Orange: tag
struct BranchLabel: View {

    enum Kind {
        case localBranch(isHEAD: Bool)
        case remoteBranch
        case tag
    }

    let name: String
    let kind: Kind

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }

    private var backgroundColor: Color {
        switch kind {
        case .localBranch(let isHEAD):
            return isHEAD ? Color.accentColor.opacity(0.25) : Color.green.opacity(0.2)
        case .remoteBranch:
            return Color.blue.opacity(0.2)
        case .tag:
            return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .localBranch(let isHEAD):
            return isHEAD ? Color.accentColor : Color.green
        case .remoteBranch:
            return Color.blue
        case .tag:
            return Color.orange
        }
    }
}

// MARK: - Convenience Init

extension BranchLabel {

    /// Creates a label from a ``BranchInfo``.
    init(branch: BranchInfo) {
        self.name = branch.name
        self.kind = branch.isRemote
            ? .remoteBranch
            : .localBranch(isHEAD: branch.isHEAD)
    }

    /// Creates a label from a ``TagInfo``.
    init(tag: TagInfo) {
        self.name = tag.name
        self.kind = .tag
    }
}

#Preview {
    HStack {
        BranchLabel(name: "main", kind: .localBranch(isHEAD: true))
        BranchLabel(name: "feature/auth", kind: .localBranch(isHEAD: false))
        BranchLabel(name: "origin/main", kind: .remoteBranch)
        BranchLabel(name: "v1.0.0", kind: .tag)
    }
    .padding()
}
