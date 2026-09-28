// Components/DiffViewer/ImageDiffView.swift
// Grove
//
// Side-by-side image comparison for diffs involving image files.
// Supports a draggable divider overlay mode and an onion-skin opacity mode.

import SwiftUI

// MARK: - ImageDiffMode

/// The active comparison mode for the image diff viewer.
enum ImageDiffMode: String, CaseIterable {
    case sideBySide = "Side by Side"
    case slider     = "Slider"
    case onionSkin  = "Onion Skin"
}

// MARK: - ImageDiffView

/// A diff viewer for image files that renders a before/after comparison
/// using one of three modes: side-by-side, a draggable split-slider, or
/// an onion-skin opacity blend.
///
/// Pass `nil` for `oldImage` or `newImage` to represent an added or deleted file.
///
/// Usage:
/// ```swift
/// ImageDiffView(oldImage: Image("before"), newImage: Image("after"))
/// ImageDiffView(oldImage: nil, newImage: Image("added"))   // added file
/// ImageDiffView(oldImage: Image("deleted"), newImage: nil) // deleted file
/// ```
struct ImageDiffView: View {

    // MARK: Properties

    /// The previous version of the image, or `nil` for newly added files.
    let oldImage: Image?
    /// The new version of the image, or `nil` for deleted files.
    let newImage: Image?
    /// Optional size metadata for the before image.
    var oldSize: CGSize?
    /// Optional size metadata for the after image.
    var newSize: CGSize?

    // MARK: State

    @State private var mode: ImageDiffMode = .sideBySide
    /// Normalised position of the slider divider (0.0 = far left, 1.0 = far right).
    @State private var sliderPosition: CGFloat = 0.5
    /// Onion-skin blend factor (0.0 = fully old, 1.0 = fully new).
    @State private var onionOpacity: CGFloat = 0.5

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            modeToolbar
            Divider()
            contentArea
        }
    }

    // MARK: Mode Toolbar

    private var modeToolbar: some View {
        HStack {
            Picker("Mode", selection: $mode) {
                ForEach(ImageDiffMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            if mode == .onionSkin {
                HStack(spacing: 6) {
                    Text("Before")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Slider(value: $onionOpacity)
                        .frame(width: 120)
                    Text("After")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
    }

    // MARK: Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .sideBySide:
            sideBySideView
        case .slider:
            sliderView
        case .onionSkin:
            onionSkinView
        }
    }

    // MARK: Side-by-Side Mode

    private var sideBySideView: some View {
        HStack(spacing: 1) {
            imagePanelView(
                image: oldImage,
                label: "Before",
                size: oldSize,
                labelColor: Theme.deleted,
                missingLabel: "File Added"
            )
            Divider()
            imagePanelView(
                image: newImage,
                label: "After",
                size: newSize,
                labelColor: Theme.added,
                missingLabel: "File Deleted"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: Slider Mode

    private var sliderView: some View {
        GeometryReader { geometry in
            let dividerX = geometry.size.width * sliderPosition

            ZStack(alignment: .leading) {
                // New image fills the full frame (shown on the right of the divider)
                imageLayerView(newImage, missingLabel: "File Deleted")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Old image clipped to the left portion
                imageLayerView(oldImage, missingLabel: "File Added")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(
                        Path { path in
                            path.addRect(CGRect(
                                x: 0,
                                y: 0,
                                width: dividerX,
                                height: geometry.size.height
                            ))
                        }
                    )

                // Divider line
                Rectangle()
                    .fill(Theme.surface.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: dividerX - 1)
                    .shadow(radius: 4)

                // Drag handle
                dragHandle
                    .offset(x: dividerX - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                sliderPosition = max(0, min(1, value.location.x / geometry.size.width))
                            }
                    )

                // Labels
                HStack {
                    Text("Before")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.pillSelectedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.deleted, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                        .padding(8)
                    Spacer()
                    Text("After")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.pillSelectedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.added, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
                        .padding(8)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dragHandle: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 24, height: 24)
                .shadow(radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: Onion Skin Mode

    private var onionSkinView: some View {
        ZStack {
            if let old = oldImage {
                old
                    .resizable()
                    .scaledToFit()
                    .opacity(Double(1.0 - onionOpacity))
            }
            if let new = newImage {
                new
                    .resizable()
                    .scaledToFit()
                    .opacity(Double(onionOpacity))
            }
            if oldImage == nil && newImage == nil {
                missingImagePlaceholder(label: "No Images")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: Shared Helpers

    private func imagePanelView(
        image: Image?,
        label: String,
        size: CGSize?,
        labelColor: Color,
        missingLabel: String
    ) -> some View {
        VStack(spacing: 0) {
            // Panel header
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(labelColor)
                if let size {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surfaceRaised)

            // Image or placeholder
            imageLayerView(image, missingLabel: missingLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func imageLayerView(_ image: Image?, missingLabel: String) -> some View {
        if let image {
            image
                .resizable()
                .scaledToFit()
                .padding(8)
        } else {
            missingImagePlaceholder(label: missingLabel)
        }
    }

    private func missingImagePlaceholder(label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview("Slider Mode") {
    ImageDiffView(
        oldImage: Image(systemName: "photo"),
        newImage: Image(systemName: "photo.fill")
    )
    .frame(width: 700, height: 400)
}
