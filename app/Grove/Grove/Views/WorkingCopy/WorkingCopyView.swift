// Views/WorkingCopy/WorkingCopyView.swift
// Grove
//
// The Changes tab: composer and file list on the left, diff on the right,
// as two cards with a draggable gap between them.

import AppKit
import SwiftUI

struct WorkingCopyView: View {
    let viewModel: WorkingCopyViewModel

    @AppStorage("WorkingCopyLeftWidth") private var leftWidth: Double = 360
    @State private var dragStartWidth: Double?

    private let minLeft: Double = 280
    private let minRight: Double = 320

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                WorkingCopyLeftColumn()
                    .frame(width: clampedLeftWidth(total: geo.size.width))
                resizeHandle(total: geo.size.width)
                DiffPanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.bottom, Theme.Spacing.lg)
        .environment(viewModel)
        .confirmationDialog(discardTitle, isPresented: discardBinding, presenting: viewModel.pendingDiscard) { entry in
            Button("Discard", role: .destructive) { Task { await viewModel.discard(entry) } }
            Button("Cancel", role: .cancel) { viewModel.cancelDiscard() }
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Resizing

    private func clampedLeftWidth(total: CGFloat) -> CGFloat {
        // In narrow windows both minimums can't fit; give the left column at most 45%.
        let lower = min(minLeft, Double(total) * 0.45)
        let upper = max(lower, Double(total) - minRight - Double(Theme.Spacing.md))
        return CGFloat(min(max(leftWidth, lower), upper))
    }

    private func resizeHandle(total: CGFloat) -> some View {
        Color.clear
            .frame(width: Theme.Spacing.md)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
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
    }

    // MARK: Dialog bindings

    private var discardTitle: String {
        guard let entry = viewModel.pendingDiscard else { return "Discard changes?" }
        return entry.workdirStatus == .untracked
            ? "Delete untracked file \(entry.fileName)?"
            : "Discard all changes to \(entry.fileName)?"
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { viewModel.pendingDiscard != nil },
                set: { if !$0 { viewModel.cancelDiscard() } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } })
    }
}

#Preview("Working Copy") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    WorkingCopyView(viewModel: vm)
        .frame(width: 1000, height: 700)
        .padding(.horizontal, Theme.Spacing.lg)
        .background(Theme.background)
        .task { await vm.refresh() }
}
