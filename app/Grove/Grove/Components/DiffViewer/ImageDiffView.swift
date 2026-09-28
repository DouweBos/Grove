// Components/DiffViewer/ImageDiffView.swift
// Grove
//
// Before/after comparison for image files: side by side, a draggable
// split slider, or an onion-skin blend.

import SwiftUI

// MARK: - ImageDiffMode

enum ImageDiffMode: String, CaseIterable {
    case sideBySide = "Side by Side"
    case slider     = "Slider"
    case onionSkin  = "Onion Skin"
}

// MARK: - ImageDiffView

/// Pass `nil` for `oldImage` or `newImage` to represent an added or deleted file.
struct ImageDiffView: View {
    let oldImage: Image?
    let newImage: Image?
    var oldSize: CGSize?
    var newSize: CGSize?

    @AppStorage("ImageDiffMode") private var mode: ImageDiffMode = .sideBySide
    /// 0 shows only the old image, 1 only the new one.
    @State private var onionOpacity: CGFloat = 0.5

    /// Extensions rendered as images; SVG stays a text diff since its source is readable.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff",
                                               "bmp", "webp", "ico", "icns", "pdf"]

    static func supports(path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            modeToolbar
            Rectangle().fill(Theme.border).frame(height: 0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    private var modeToolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Picker("Mode", selection: $mode) {
                ForEach(ImageDiffMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Spacer(minLength: Theme.Spacing.sm)
            if mode == .onionSkin {
                Text("Before").font(.caption).foregroundStyle(Theme.textSecondary)
                Slider(value: $onionOpacity).controlSize(.small).frame(width: 120)
                Text("After").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .sideBySide:
            ImageDiffSideBySide(oldImage: oldImage, newImage: newImage, oldSize: oldSize, newSize: newSize)
        case .slider:
            ImageDiffSlider(oldImage: oldImage, newImage: newImage)
        case .onionSkin:
            ImageDiffOnionSkin(oldImage: oldImage, newImage: newImage, opacity: onionOpacity)
        }
    }
}

// MARK: - Preview

#Preview("Side by Side") {
    ImageDiffView(
        oldImage: Image(systemName: "photo"),
        newImage: Image(systemName: "photo.fill"),
        oldSize: CGSize(width: 800, height: 600),
        newSize: CGSize(width: 1024, height: 768)
    )
    .frame(width: 700, height: 400)
}

#Preview("Added") {
    ImageDiffView(oldImage: nil, newImage: Image(systemName: "photo.fill"))
        .frame(width: 700, height: 400)
}
