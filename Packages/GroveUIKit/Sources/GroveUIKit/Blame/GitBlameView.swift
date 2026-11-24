// Blame/GitBlameView.swift
// GroveUIKit
//
// Tracked files on the left and the chosen one annotated line by line on the right; one at a time when narrow.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitBlameView: View {
    @Environment(\.gitStyle) private var style
    private let viewModel: BlameViewModel
    private let host: GitBlameHost
    @State private var width: CGFloat = 0

    public init(viewModel: BlameViewModel, host: GitBlameHost = GitBlameHost()) {
        self.viewModel = viewModel
        self.host = host
    }

    /// Below this the picker and the file take turns.
    static func compactBelow(fontScale: CGFloat) -> CGFloat {
        ((pickerWidth + 460) * fontScale).rounded() + GitMetrics.Spacing.md
    }

    static let pickerWidth: CGFloat = 300

    public var body: some View {
        Group {
            if width > 0, width < Self.compactBelow(fontScale: style.fontScale) {
                if viewModel.selectedFile == nil {
                    BlameFileList(viewModel: viewModel, host: host, pick: pick)
                } else {
                    BlameFilePanel(viewModel: viewModel, host: host, back: { pick(nil) })
                }
            } else {
                HStack(spacing: GitMetrics.Spacing.md) {
                    BlameFileList(viewModel: viewModel, host: host, pick: pick)
                        .frame(width: Self.pickerWidth * style.fontScale)
                    BlameFilePanel(viewModel: viewModel, host: host, back: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await viewModel.loadFilesIfNeeded() }
    }

    private func pick(_ path: String?) {
        if let pick = host.pick { return pick(path) }
        if let path {
            Task { await viewModel.open(file: path) }
        } else {
            viewModel.close()
        }
    }
}

#Preview {
    let vm = BlameViewModel(repository: MockGitRepository())
    return GitBlameView(viewModel: vm)
        .frame(width: 1100, height: 600)
        .padding()
        .task { await vm.open(file: "Sources/App.swift") }
}
#endif
