// Diff/Views/GitImageDiffView.swift
// GroveUIKit
//
// Both versions of an image file from the repository: side by side, a draggable split, or an onion-skin blend.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

public struct GitImageDiffView: View {
    private let images: GitDiffImages
    private let path: String
    private let oldPath: String?
    private let mode: Binding<GitImageDiffMode>
    @State private var loaded: LoadedImages?

    /// Extensions shown as images; SVG stays a text diff since its source is readable.
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff",
                                                       "bmp", "webp", "ico", "icns", "pdf"]

    public static func supports(path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// - Parameter oldPath: The path on the old side of a rename.
    public init(_ images: GitDiffImages, path: String, oldPath: String? = nil, mode: Binding<GitImageDiffMode>) {
        self.images = images
        self.path = path
        self.oldPath = oldPath
        self.mode = mode
    }

    private struct LoadedImages {
        let old: NSImage?
        let new: NSImage?
    }

    private var request: [AnyHashable] {
        [path, oldPath ?? path, images.old, images.new, images.reloadToken]
    }

    public var body: some View {
        Group {
            if let loaded {
                ImageDiffContent(old: loaded.old, new: loaded.new, mode: mode)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: request) {
            // A side that fails to load (added/deleted file, root commit) renders as missing.
            let old = try? await images.repository.fileData(path: oldPath ?? path, at: images.old)
            let new = try? await images.repository.fileData(path: path, at: images.new)
            guard !Task.isCancelled else { return }
            loaded = LoadedImages(old: old.flatMap(NSImage.init(data:)), new: new.flatMap(NSImage.init(data:)))
        }
    }
}

struct ImageDiffContent: View {
    @Environment(\.gitStyle) private var style
    let old: NSImage?
    let new: NSImage?
    @Binding var mode: GitImageDiffMode
    /// 0 shows only the old image, 1 only the new one.
    @State private var onionOpacity: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 0) {
            modeToolbar
            Rectangle().fill(style.border).frame(height: 0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(style.background)
        }
    }

    private var modeToolbar: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Picker("Mode", selection: $mode) {
                ForEach(GitImageDiffMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .gitClickable()
            Spacer(minLength: GitMetrics.Spacing.sm)
            if mode == .onionSkin {
                Text("Before").font(style.font(10)).foregroundStyle(style.textSecondary)
                Slider(value: $onionOpacity).controlSize(.small).frame(width: 120)
                Text("After").font(style.font(10)).foregroundStyle(style.textSecondary)
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.md)
        .padding(.vertical, GitMetrics.Spacing.sm)
        .background(style.surface)
    }

    @ViewBuilder
    private var content: some View {
        let oldImage = old.map(Image.init(nsImage:))
        let newImage = new.map(Image.init(nsImage:))
        switch mode {
        case .sideBySide:
            ImageDiffSideBySide(oldImage: oldImage, newImage: newImage, oldSize: old?.size, newSize: new?.size)
        case .slider:
            ImageDiffSlider(oldImage: oldImage, newImage: newImage)
        case .onionSkin:
            ImageDiffOnionSkin(oldImage: oldImage, newImage: newImage, opacity: onionOpacity)
        }
    }
}

#Preview("Side by Side") {
    ImageDiffContent(old: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
                     new: NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil),
                     mode: .constant(.sideBySide))
        .frame(width: 700, height: 400)
}
#endif
