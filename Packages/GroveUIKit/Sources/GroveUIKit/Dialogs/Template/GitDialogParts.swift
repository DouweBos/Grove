// Dialogs/Template/GitDialogParts.swift
// GroveUIKit
//
// The pieces a dialog's fields are built from: a card, labelled rows, checkboxes and a collapsible Options card.

#if os(macOS)
import GroveKit
import SwiftUI

/// Rounded card grouping a dialog's fields.
public struct GitDialogCard<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitCard(padding: GitMetrics.Spacing.md)
    }
}

/// Label and control, with a fixed label column so controls line up.
public struct GitDialogField<Content: View>: View {
    @Environment(\.gitStyle) private var style
    private let label: String
    private let content: () -> Content

    public init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GitMetrics.Spacing.md) {
            Text(label)
                .font(style.font(13))
                .foregroundStyle(style.textSecondary)
                .frame(width: GitDialogField<EmptyView>.labelWidth * style.fontScale, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where controls start, for a row that lines up with them without a label of its own.
    public static var labelWidth: CGFloat { 96 }
}

/// A path in mono with a Choose button, for folder pickers.
public struct GitDialogPathField: View {
    @Environment(\.gitStyle) private var style
    private let path: String?
    private let placeholder: String
    private let onChoose: () -> Void

    /// `path` shows as given; abbreviate the home folder first if wanted.
    public init(path: String?, placeholder: String = "No folder selected", onChoose: @escaping () -> Void) {
        self.path = path
        self.placeholder = placeholder
        self.onChoose = onChoose
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Text(path ?? placeholder)
                .font(style.monoCaption)
                .foregroundStyle(path == nil ? style.textSecondary : style.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose", action: onChoose).gitClickable()
        }
    }
}

/// Checkbox with an optional one-line explanation underneath.
public struct GitDialogOptionRow: View {
    @Environment(\.gitStyle) private var style
    @Binding private var isOn: Bool
    private let label: String
    private let description: String?

    public init(isOn: Binding<Bool>, label: String, description: String? = nil) {
        self._isOn = isOn
        self.label = label
        self.description = description
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(label, isOn: $isOn)
                .toggleStyle(.checkbox)
                .font(style.font(13))
                .gitClickable()
            if let description {
                Text(description)
                    .font(style.font(12))
                    .foregroundStyle(style.textSecondary)
                    .padding(.leading, 20 * style.fontScale)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Collapsible "Options" card for the settings most people leave alone.
public struct GitDialogOptionsSection<Content: View>: View {
    @Environment(\.gitStyle) private var style
    @State private var isExpanded: Bool
    @State private var contentHeight: CGFloat = 0
    private let content: () -> Content

    public init(isExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header spans the card's padding so the whole card toggles, not just the chevron.
            Button {
                withAnimation(.snappy(duration: 0.1)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: GitMetrics.Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(style.font(10, .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Options").font(style.sectionLabel)
                }
                .foregroundStyle(style.textSecondary)
                .padding(GitMetrics.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gitClickable()
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
                content()
            }
            .padding([.horizontal, .bottom], GitMetrics.Spacing.md)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            .modifier(RevealHeight(fullHeight: contentHeight, fraction: isExpanded ? 1 : 0))
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitCard(padding: 0)
    }
}

/// Clips to `fraction` of `fullHeight`; animatable so layout, and with it the sheet, grows every frame.
private struct RevealHeight: ViewModifier, Animatable {
    let fullHeight: CGFloat
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: fullHeight * fraction, alignment: .top)
            .clipped()
            .opacity(fraction)
    }
}

/// Focuses a dialog's first field once it's on screen.
private struct InitialFocus: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .task { focused = true }
    }
}

extension View {
    /// The field a dialog's typing starts in.
    public func gitInitialFocus() -> some View { modifier(InitialFocus()) }
}

#Preview("Dialog") {
    GitDialogSheet(title: "Push main", message: "Sends your local commits on 'main' to the chosen remote branch.",
                   symbol: "arrow.up.to.line", progress: "Pushing to origin",
                   errorMessage: "Push rejected: the remote contains work you do not have.",
                   primaryTitle: "Push", onCancel: {}, onPrimary: {}) {
        GitDialogCard {
            GitDialogField("Destination") { Text("origin/main") }
            GitDialogField("Location") { GitDialogPathField(path: "~/Projects/grove") {} }
        }
        GitDialogOptionsSection(isExpanded: true) {
            GitDialogOptionRow(isOn: .constant(false), label: "Push All Tags", description: "All refs under refs/tags are pushed.")
        }
    }
}
#endif
