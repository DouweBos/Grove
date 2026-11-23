// WorkingCopy/GitWorkingCopyView.swift
// GroveUIKit
//
// The Changes screen: composer and file list on the left, the diff or conflict resolver on the right,
// as two cards with a draggable gap between them.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

public struct GitWorkingCopyView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: WorkingCopyViewModel
    private let host: GitWorkingCopyHost
    private let slots: GitWorkingCopySlots
    @State private var ownWidth: Double = 360
    @State private var dragStartWidth: Double?

    private let minLeft: Double = 260
    private let minRight: Double = 380

    public init(viewModel: WorkingCopyViewModel, host: GitWorkingCopyHost = GitWorkingCopyHost(),
                slots: GitWorkingCopySlots = GitWorkingCopySlots()) {
        self.viewModel = viewModel
        self.host = host
        self.slots = slots
    }

    public var body: some View {
        GeometryReader { geo in
            // Too narrow for two usable columns: the detail goes below.
            if geo.size.width >= (minLeft + minRight) * style.fontScale + GitMetrics.Spacing.md {
                HStack(spacing: 0) {
                    WorkingCopyLeftColumn()
                        .frame(width: clampedLeftWidth(total: geo.size.width))
                    resizeHandle(total: geo.size.width)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: GitMetrics.Spacing.md) {
                    WorkingCopyLeftColumn(axis: .horizontal)
                        .frame(height: max(240, geo.size.height * 0.4))
                    detail
                }
            }
        }
        .environment(viewModel)
        .environment(\.workingCopyHost, host)
        .environment(\.workingCopySlots, slots)
        .gitWorkingCopyDialogs(viewModel)
        .modifier(PatchDialogs(viewModel: viewModel, host: host))
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let replacement = slots.replacement, viewModel.selectedEntry?.isConflicted != true {
            replacement.detail.gitPanel()
        } else {
            WorkingCopyDetail()
        }
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
        let lower = minLeft * style.fontScale
        let upper = max(lower, Double(total) - minRight * style.fontScale - Double(GitMetrics.Spacing.md))
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
#endif
