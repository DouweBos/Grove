// Primitives/GitBranchLabel.swift
// GroveUIKit
//
// Capsule shown on commit rows for branches and remotes pointing at that commit.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitBranchLabel: View {

    public nonisolated enum Kind: Sendable {
        case localBranch(isHEAD: Bool)
        case remoteBranch
        case tag
    }

    @Environment(\.gitStyle) private var style
    private let name: String
    private let kind: Kind
    private let isOnRemote: Bool
    private let maxNameWidth: CGFloat?

    /// - Parameters:
    ///   - isOnRemote: A local branch whose same-named remote branch points at the same commit.
    ///   - maxNameWidth: Longest the name may get before it truncates in the middle; nil shows it in full.
    public init(name: String, kind: Kind, isOnRemote: Bool = false, maxNameWidth: CGFloat? = nil) {
        self.name = name
        self.kind = kind
        self.isOnRemote = isOnRemote
        self.maxNameWidth = maxNameWidth
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(style.font(9, .semibold))
            // Fixed size of a max-width frame is the smaller of the name's width and the cap.
            Text(name).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: maxNameWidth.map { $0 * style.fontScale }, alignment: .leading)
                .fixedSize()
            if isOnRemote {
                Image(systemName: "cloud").font(style.font(9, .semibold))
                    .accessibilityLabel("Also on remote")
            }
        }
        .font(style.font(11, .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .fixedSize()
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
        case .localBranch(let isHEAD): isHEAD ? style.accent : style.success
        case .remoteBranch: style.info
        case .tag: style.warning
        }
    }
}

extension GitBranchLabel {
    public init(branch: BranchInfo) {
        self.init(name: branch.name, kind: branch.isRemote ? .remoteBranch : .localBranch(isHEAD: branch.isHEAD))
    }

    public init(tag: TagInfo) {
        self.init(name: tag.name, kind: .tag)
    }
}

#Preview {
    HStack {
        GitBranchLabel(name: "main", kind: .localBranch(isHEAD: true))
        GitBranchLabel(name: "feature/auth", kind: .localBranch(isHEAD: false), isOnRemote: true)
        GitBranchLabel(name: "origin/main", kind: .remoteBranch)
        GitBranchLabel(name: "v1.0.0", kind: .tag)
    }
    .padding()
    .background(GitUIStyle.system.surface)
}
#endif
