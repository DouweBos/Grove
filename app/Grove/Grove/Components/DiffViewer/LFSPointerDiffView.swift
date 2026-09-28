// Components/DiffViewer/LFSPointerDiffView.swift
// Grove
//
// A change to a Git LFS file: git only sees its pointer, so this shows the object's size and id before and after.

import SwiftUI

struct LFSPointerDiffView: View {
    let old: LFSPointer?
    let new: LFSPointer?
    var onShowPointer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(Theme.info)
                Text("Stored with Git LFS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let onShowPointer {
                    Button("Show Pointer", action: onShowPointer)
                        .buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            Text("Git tracks a small pointer file; the content lives on the LFS server.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                row("Before", old, tint: Theme.deleted)
                row("After", new, tint: Theme.added)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .card(padding: Theme.Spacing.lg)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func row(_ label: String, _ pointer: LFSPointer?, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 48, alignment: .leading)
            if let pointer {
                Text(ByteCountFormatter.string(fromByteCount: pointer.size, countStyle: .file))
                    .font(.monoCaption)
                    .foregroundStyle(tint)
                Text(pointer.shortOID)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .help("sha256:\(pointer.oid)")
            } else {
                Text("None").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

#Preview {
    LFSPointerDiffView(old: LFSPointer(oid: "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", size: 12_345),
                       new: LFSPointer(oid: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", size: 2_345_678),
                       onShowPointer: {})
        .frame(width: 560, height: 260)
        .background(Theme.background)
}
