// Views/Merge/ConflictResolutionArea.swift
// Grove
//
// The center / lower area of the Conflict Wizard that shows the current
// resolution state for the selected conflicted file.
//
// Two states:
//   Unresolved — illustration + "Please select a version above" prompt
//   Resolved   — display the chosen content with a green "Resolved" badge
//
// This view is intentionally passive: it only presents state. All
// resolution decisions are driven by ConflictWizardView.

import SwiftUI

// MARK: - ConflictResolutionArea

/// The resolution-state display area shown below the two version panels in
/// ``ConflictWizardView``.
///
/// When no version has been chosen, it shows a prompt illustration.
/// When a side has been selected, it shows the resolved content together
/// with a "Resolved" badge.
///
/// ```swift
/// ConflictResolutionArea(
///     resolvedContent: viewModel.resolvedContent,
///     resolvedSide: viewModel.resolvedSide,
///     resolvedBranch: viewModel.resolvedBranch
/// )
/// ```
struct ConflictResolutionArea: View {

    // MARK: Properties

    /// The content that will be written to the file as the resolution.
    /// `nil` means no version has been chosen yet.
    let resolvedContent: String?

    /// Which side was selected as the resolution.
    let resolvedSide: ConflictSide?

    /// Branch name of the chosen resolution (for display only).
    let resolvedBranch: String?

    // MARK: Body

    var body: some View {
        Group {
            if let content = resolvedContent, let branch = resolvedBranch {
                resolvedView(content: content, branch: branch)
            } else {
                unresolvedPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: Unresolved Placeholder

    /// Centred illustration + instruction text for the empty state.
    private var unresolvedPlaceholder: some View {
        VStack(spacing: 16) {
            mergeIllustration

            VStack(spacing: 6) {
                Text("Please select a version above")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Choose the version that should be kept for this file,\nor open the file in an external merge tool.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(24)
    }

    /// Simple SVG-style merge branch illustration using SwiftUI shapes.
    private var mergeIllustration: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let midY = h / 2

            // Shared line style
            let lineStroke = GraphicsContext.Shading.color(Color.secondary.opacity(0.4))
            _ = lineStroke  // suppress unused warning — used via withStroke below

            let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round)

            // Left branch line (ours — green tint)
            var leftPath = Path()
            leftPath.move(to: CGPoint(x: cx - 28, y: midY - 22))
            leftPath.addQuadCurve(
                to: CGPoint(x: cx, y: midY + 10),
                control: CGPoint(x: cx - 28, y: midY + 10)
            )
            context.stroke(leftPath, with: .color(Color.green.opacity(0.5)), style: strokeStyle)

            // Right branch line (theirs — blue tint)
            var rightPath = Path()
            rightPath.move(to: CGPoint(x: cx + 28, y: midY - 22))
            rightPath.addQuadCurve(
                to: CGPoint(x: cx, y: midY + 10),
                control: CGPoint(x: cx + 28, y: midY + 10)
            )
            context.stroke(rightPath, with: .color(Color.blue.opacity(0.5)), style: strokeStyle)

            // Merge node circle
            let nodeRect = CGRect(x: cx - 7, y: midY + 4, width: 14, height: 14)
            let nodePath = Path(ellipseIn: nodeRect)
            context.fill(nodePath, with: .color(Color.secondary.opacity(0.25)))
            context.stroke(nodePath, with: .color(Color.secondary.opacity(0.5)), style: strokeStyle)

            // Left dot
            let leftDot = CGRect(x: cx - 33, y: midY - 29, width: 10, height: 10)
            context.fill(Path(ellipseIn: leftDot), with: .color(Color.green.opacity(0.5)))

            // Right dot
            let rightDot = CGRect(x: cx + 23, y: midY - 29, width: 10, height: 10)
            context.fill(Path(ellipseIn: rightDot), with: .color(Color.blue.opacity(0.5)))
        }
        .frame(width: 80, height: 60)
    }

    // MARK: Resolved View

    /// Shows the chosen content with a "Resolved" badge at the top.
    private func resolvedView(content: String, branch: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Resolved header bar
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))

                Text("Resolved using '\(branch)'")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)

                Spacer(minLength: 4)

                resolvedBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.10))

            Divider()
                .background(Color.green.opacity(0.3))

            // Resolved content
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var resolvedBadge: some View {
        Text("RESOLVED")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview("Unresolved") {
    ConflictResolutionArea(
        resolvedContent: nil,
        resolvedSide: nil,
        resolvedBranch: nil
    )
    .frame(width: 500, height: 200)
    .padding()
    .background(Color(white: 0.13))
}

#Preview("Resolved") {
    ConflictResolutionArea(
        resolvedContent: """
        import Foundation

        final class AuthManager {
            private var token: String?

            func authenticate() async throws {
                token = try await OAuthService.shared.fetchToken()
            }
        }
        """,
        resolvedSide: .ours,
        resolvedBranch: "feature/auth"
    )
    .frame(width: 500, height: 220)
    .padding()
    .background(Color(white: 0.13))
}
