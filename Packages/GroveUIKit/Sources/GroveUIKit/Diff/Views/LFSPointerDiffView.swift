// Diff/Views/LFSPointerDiffView.swift
// GroveUIKit
//
// A change to a Git LFS file: git only sees its pointer, so this shows the object's size and id before and after.

#if os(macOS)
import GroveKit
import SwiftUI

struct LFSPointerDiffView: View {
    @Environment(\.gitStyle) private var style
    let old: LFSPointer?
    let new: LFSPointer?
    var onShowPointer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(style.info)
                Text("Stored with Git LFS")
                    .font(style.font(13, .semibold))
                    .foregroundStyle(style.textPrimary)
                Spacer()
                if let onShowPointer {
                    Button("Show Pointer", action: onShowPointer)
                        .buttonStyle(.borderless)
                        .gitClickable()
                        .font(style.font(12, .medium))
                }
            }
            Text("Git tracks a small pointer file; the content lives on the LFS server.")
                .font(style.font(12))
                .foregroundStyle(style.textSecondary)
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
                row("Before", old, tint: style.danger)
                row("After", new, tint: style.success)
            }
        }
        .frame(maxWidth: 420 * style.fontScale, alignment: .leading)
        .gitCard(padding: GitMetrics.Spacing.lg)
        .padding(GitMetrics.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ label: String, _ pointer: LFSPointer?, tint: Color) -> some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            Text(label)
                .font(style.font(12))
                .foregroundStyle(style.textSecondary)
                .frame(width: 48 * style.fontScale, alignment: .leading)
            if let pointer {
                Text(ByteCountFormatter.string(fromByteCount: pointer.size, countStyle: .file))
                    .font(style.monoCaption)
                    .foregroundStyle(tint)
                Text(pointer.shortOID)
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                    .help("sha256:\(pointer.oid)")
            } else {
                Text("None").font(style.monoCaption).foregroundStyle(style.textSecondary)
            }
        }
    }
}

#Preview {
    LFSPointerDiffView(old: LFSPointer(oid: "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", size: 12_345),
                       new: LFSPointer(oid: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", size: 2_345_678),
                       onShowPointer: {})
        .frame(width: 560, height: 260)
        .background(GitUIStyle.system.surface)
}
#endif
