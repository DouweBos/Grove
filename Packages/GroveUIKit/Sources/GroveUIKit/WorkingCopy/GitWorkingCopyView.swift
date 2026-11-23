// WorkingCopy/GitWorkingCopyView.swift
// GroveUIKit
//
// The Changes screen: composer and file list on the left, the diff or conflict resolver on the right,
// as two cards with a draggable gap between them; narrower, the compact list over the diff.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// How the working copy arranges its composer, files and diff.
public enum GitWorkingCopyLayout: Equatable, Sendable {
    /// Two columns, or the compact layout with the composer when too narrow for them.
    case automatic
    /// The file list over the diff, e.g. in a side panel; without the composer, committing is left to the app's other views.
    case compact(composer: Bool)
}

public struct GitWorkingCopyView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: WorkingCopyViewModel
    private let host: GitWorkingCopyHost
    private let slots: GitWorkingCopySlots
    private let layout: GitWorkingCopyLayout
    @State private var ownWidth: Double = 360
    @State private var dragStartWidth: Double?

    static let minLeft: Double = 260
    static let minRight: Double = 380

    public init(viewModel: WorkingCopyViewModel, host: GitWorkingCopyHost = GitWorkingCopyHost(),
                slots: GitWorkingCopySlots = GitWorkingCopySlots(), layout: GitWorkingCopyLayout = .automatic) {
        self.viewModel = viewModel
        self.host = host
        self.slots = slots
        self.layout = layout
    }

    public var body: some View {
        GeometryReader { geo in
            switch Self.arrangement(width: geo.size.width, fontScale: style.fontScale, layout: layout) {
            case .columns:
                HStack(spacing: 0) {
                    WorkingCopyLeftColumn()
                        .frame(width: clampedLeftWidth(total: geo.size.width))
                    resizeHandle(total: geo.size.width)
                    WorkingCopyDetailArea().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .compact(let composer):
                WorkingCopyCompact(showsComposer: composer)
            }
        }
        .environment(viewModel)
        .environment(\.workingCopyHost, host)
        .environment(\.workingCopySlots, slots)
        .modifier(WorkingCopyPresentation(viewModel: viewModel, host: host))
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    enum Arrangement: Equatable {
        case columns
        case compact(composer: Bool)
    }

    /// The one place the working copy decides between columns and compact.
    static func arrangement(width: CGFloat, fontScale: Double, layout: GitWorkingCopyLayout) -> Arrangement {
        switch layout {
        case .compact(let composer): .compact(composer: composer)
        case .automatic: width >= compactBelow(fontScale: fontScale) ? .columns : .compact(composer: true)
        }
    }

    /// Narrower than both columns' minimums and the gap between them: 652pt at the default size.
    static func compactBelow(fontScale: Double) -> CGFloat {
        CGFloat((minLeft + minRight) * fontScale) + GitMetrics.Spacing.md
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { host.showsErrors && viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } })
    }

    // MARK: Resizing

    private var leftWidth: Double {
        get { host.leftWidth?.wrappedValue ?? ownWidth }
        nonmutating set {
            if let binding = host.leftWidth { binding.wrappedValue = newValue } else { ownWidth = newValue }
        }
    }

    private func clampedLeftWidth(total: CGFloat) -> CGFloat {
        let lower = Self.minLeft * style.fontScale
        let upper = max(lower, Double(total) - Self.minRight * style.fontScale - Double(GitMetrics.Spacing.md))
        return CGFloat(min(max(leftWidth, lower), upper))
    }

    private func resizeHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(width: GitMetrics.Spacing.md)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidth ?? Double(clampedLeftWidth(total: total))
                        dragStartWidth = start
                        leftWidth = start + value.translation.width
                    }
                    .onEnded { _ in
                        leftWidth = Double(clampedLeftWidth(total: total))
                        dragStartWidth = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

/// The confirmations and patch sheets, unless another view of the same view model presents them.
private struct WorkingCopyPresentation: ViewModifier {
    let viewModel: WorkingCopyViewModel
    let host: GitWorkingCopyHost

    func body(content: Content) -> some View {
        if host.presentsDialogs {
            content
                .gitWorkingCopyDialogs(viewModel)
                .modifier(PatchDialogs(viewModel: viewModel, host: host))
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var workingCopyHost = GitWorkingCopyHost()
    @Entry var workingCopySlots = GitWorkingCopySlots()
}

extension WorkingCopyViewModel {
    /// A person's action: the last failure goes, so a new one shows on its own.
    func act(_ work: @escaping @MainActor () async -> Void) {
        Task {
            clearError()
            await work()
        }
    }
}

#Preview("Working Copy") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    GitWorkingCopyView(viewModel: vm)
        .frame(width: 1000, height: 700)
        .padding(.horizontal, 16)
        .task { await vm.refresh() }
}

#Preview("Compact") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    GitWorkingCopyView(viewModel: vm, layout: .compact(composer: false))
        .frame(width: 300, height: 700)
        .padding(8)
        .task { await vm.refresh() }
}
#endif
