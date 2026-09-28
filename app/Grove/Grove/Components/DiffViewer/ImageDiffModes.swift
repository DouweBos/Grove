// Components/DiffViewer/ImageDiffModes.swift
// Grove
//
// The three comparison modes rendered by ImageDiffView.

import SwiftUI

struct ImageDiffSideBySide: View {
    let oldImage: Image?
    let newImage: Image?
    var oldSize: CGSize?
    var newSize: CGSize?

    var body: some View {
        HStack(spacing: 0) {
            panel(oldImage, label: "Before", size: oldSize, color: Theme.deleted, missing: "File Added")
            Rectangle().fill(Theme.border).frame(width: 0.5)
            panel(newImage, label: "After", size: newSize, color: Theme.added, missing: "File Deleted")
        }
    }

    private func panel(_ image: Image?, label: String, size: CGSize?, color: Color, missing: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
                if let size {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.surfaceRaised)
            ImageDiffLayer(image: image, missingLabel: missing)
        }
    }
}

struct ImageDiffSlider: View {
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
                    .fill(Theme.surface.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: dividerX - 1)
                    .shadow(radius: 4)
                dragHandle
                    .offset(x: dividerX - 12)
                    .gesture(DragGesture().onChanged { value in
                        position = max(0, min(1, value.location.x / geo.size.width))
                    })
                HStack {
                    tag("Before", color: Theme.deleted)
                    Spacer()
                    tag("After", color: Theme.added)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var dragHandle: some View {
        ZStack {
            Circle().fill(Theme.surface).frame(width: 24, height: 24).shadow(radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func tag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.pillSelectedText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .padding(Theme.Spacing.sm)
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
        .padding(Theme.Spacing.sm)
    }
}

/// One image scaled to fit, or a placeholder when that side doesn't exist.
struct ImageDiffLayer: View {
    let image: Image?
    let missingLabel: String

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit().padding(Theme.Spacing.sm)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                    Text(missingLabel).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Slider") {
    ImageDiffSlider(oldImage: Image(systemName: "photo"), newImage: Image(systemName: "photo.fill"))
        .frame(width: 600, height: 360)
        .background(Theme.background)
}
