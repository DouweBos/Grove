// Diff/Views/ImageDiffModes.swift
// GroveUIKit
//
// The three comparison modes rendered by GitImageDiffView.

#if os(macOS)
import SwiftUI

struct ImageDiffSideBySide: View {
    @Environment(\.gitStyle) private var style
    let oldImage: Image?
    let newImage: Image?
    var oldSize: CGSize?
    var newSize: CGSize?

    var body: some View {
        HStack(spacing: 0) {
            panel(oldImage, label: "Before", size: oldSize, color: style.danger, missing: "File Added")
            Rectangle().fill(style.border).frame(width: 0.5)
            panel(newImage, label: "After", size: newSize, color: style.success, missing: "File Deleted")
        }
    }

    private func panel(_ image: Image?, label: String, size: CGSize?, color: Color, missing: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Text(label).font(style.font(10, .semibold)).foregroundStyle(color)
                if let size {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(style.monoCaption)
                        .foregroundStyle(style.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, GitMetrics.Spacing.md)
            .padding(.vertical, GitMetrics.Spacing.xs)
            .background(style.surfaceRaised)
            ImageDiffLayer(image: image, missingLabel: missing)
        }
    }
}

struct ImageDiffSlider: View {
    @Environment(\.gitStyle) private var style
    let oldImage: Image?
    let newImage: Image?

    /// 0 is the far left, 1 the far right.
    @State private var position: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let dividerX = geo.size.width * position
            ZStack(alignment: .leading) {
                ImageDiffLayer(image: newImage, missingLabel: "File Deleted")
                ImageDiffLayer(image: oldImage, missingLabel: "File Added")
                    .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: dividerX, height: geo.size.height)))
                Rectangle()
                    .fill(style.surface.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: dividerX - 1)
                    .shadow(radius: 4)
                dragHandle
                    .offset(x: dividerX - 12)
                    .gitClickable()
                    .gesture(DragGesture().onChanged { value in
                        position = max(0, min(1, value.location.x / geo.size.width))
                    })
                HStack {
                    tag("Before", color: style.danger)
                    Spacer()
                    tag("After", color: style.success)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var dragHandle: some View {
        ZStack {
            Circle().fill(style.surface).frame(width: 24, height: 24).shadow(radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(style.font(10, .bold))
                .foregroundStyle(style.textPrimary)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(style.font(10, .semibold))
            .foregroundStyle(style.pillSelectedText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
            .padding(GitMetrics.Spacing.sm)
    }
}

struct ImageDiffOnionSkin: View {
    let oldImage: Image?
    let newImage: Image?
    /// 0 shows only the old image, 1 only the new one.
    let opacity: CGFloat

    var body: some View {
        ZStack {
            if let oldImage { oldImage.resizable().scaledToFit().opacity(1 - opacity) }
            if let newImage { newImage.resizable().scaledToFit().opacity(opacity) }
            if oldImage == nil && newImage == nil { ImageDiffLayer(image: nil, missingLabel: "No Images") }
        }
        .padding(GitMetrics.Spacing.sm)
    }
}

/// One image scaled to fit, or a placeholder when that side doesn't exist.
struct ImageDiffLayer: View {
    @Environment(\.gitStyle) private var style
    let image: Image?
    let missingLabel: String

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit().padding(GitMetrics.Spacing.sm)
            } else {
                VStack(spacing: GitMetrics.Spacing.sm) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(style.font(28, .light))
                        .foregroundStyle(style.textSecondary)
                    Text(missingLabel).font(style.font(10)).foregroundStyle(style.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Slider") {
    ImageDiffSlider(oldImage: Image(systemName: "photo"), newImage: Image(systemName: "photo.fill"))
        .frame(width: 600, height: 360)
        .background(GitUIStyle.system.background)
}
#endif
