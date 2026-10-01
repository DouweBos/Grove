// Views/CI/CIGraphView.swift
// Grove

import SwiftUI

/// The run's jobs in columns by `needs`, framed like GitHub's workflow card; a job opens its steps and log.
struct CIGraphView: View {

    @Environment(CIRunDetailViewModel.self) private var viewModel

    var body: some View {
        let graph = viewModel.graph
        if graph.nodes.isEmpty {
            Group {
                if viewModel.isLoadingGraph || viewModel.isLoadingJobs {
                    ProgressView().controlSize(.small)
                } else {
                    EmptyStateView(systemImage: "point.3.connected.trianglepath.dotted", title: "No Jobs")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .summarySection()
        } else {
            canvas(graph)
        }
    }

    /// The workflow file and its trigger above the graph, pinned top-leading, zoom bottom-right.
    private func canvas(_ graph: CIGraph) -> some View {
        let zoom = viewModel.graphZoom
        let layout = CIGraphLayout(graph)
        let contentWidth = layout.size.width * zoom + 2 * Theme.Spacing.xl
        return GeometryReader { geo in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    CIGraphCanvas(graph: graph, layout: layout) { node in Task { await viewModel.open(node) } }
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading)
                }
                .padding(Theme.Spacing.xl)
                .frame(minWidth: geo.size.width, alignment: .topLeading)
            }
            // "Always show scroll bars" would otherwise draw one under a graph that fits.
            .scrollIndicators(contentWidth <= geo.size.width ? .never : .automatic)
        }
        // The summary scrolls vertically, so the card is as tall as its graph, with room below for the zoom controls.
        .frame(height: layout.size.height * zoom + Self.chromeHeight)
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(Theme.Spacing.md) }
        .summarySection()
    }

    /// The header, padding and a strip for the zoom controls around the graph itself.
    private static let chromeHeight: CGFloat = 150

    @ViewBuilder private var header: some View {
        if let run = viewModel.run {
            CISummaryHeader(title: run.workflowPath.isEmpty ? run.workflowName : (run.workflowPath as NSString).lastPathComponent,
                            subtitle: "on: \(run.event)")
        }
    }

    private var zoomControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button { viewModel.resetGraphZoom() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Actual Size")
            ControlGroup {
                Button { viewModel.zoomGraph(by: -0.25) } label: { Image(systemName: "minus") }
                    .disabled(viewModel.graphZoom <= CIRunDetailViewModel.graphZoomRange.lowerBound)
                    .help("Zoom Out")
                Button { viewModel.zoomGraph(by: 0.25) } label: { Image(systemName: "plus") }
                    .disabled(viewModel.graphZoom >= CIRunDetailViewModel.graphZoomRange.upperBound)
                    .help("Zoom In")
            }
            .fixedSize()
        }
    }
}

/// Nodes at fixed positions, so the links can be drawn between them without measuring.
private struct CIGraphCanvas: View {
    let graph: CIGraph
    let layout: CIGraphLayout
    let onOpen: (CIGraph.Node) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let from = layout.frames[edge.from], let to = layout.frames[edge.to] else { continue }
                    let start = CGPoint(x: from.maxX, y: from.minY + CIGraphLayout.headerHeight / 2)
                    let end = CGPoint(x: to.minX, y: to.minY + CIGraphLayout.headerHeight / 2)
                    context.stroke(Self.link(from: start, to: end), with: .color(Theme.textSecondary.opacity(0.45)), lineWidth: 1.2)
                    for point in [start, end] {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(Theme.textSecondary))
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            ForEach(graph.nodes) { node in
                if let frame = layout.frames[node.id] {
                    CIGraphNodeView(node: node) { onOpen(node) }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

extension CIGraphCanvas {
    /// Right from the needed job, down or up in the gap before the waiting job's column, then into it; links into a column
    /// share that gap, which draws them as trunks like GitHub's graph.
    static func link(from start: CGPoint, to end: CGPoint) -> Path {
        let gapX = end.x - CIGraphLayout.columnGap / 2
        let radius = min(6, abs(end.y - start.y) / 2)
        let down: CGFloat = end.y > start.y ? 1 : -1
        var path = Path()
        path.move(to: start)
        guard radius > 0.5 else {
            path.addLine(to: end)
            return path
        }
        path.addLine(to: CGPoint(x: gapX - radius, y: start.y))
        path.addQuadCurve(to: CGPoint(x: gapX, y: start.y + radius * down), control: CGPoint(x: gapX, y: start.y))
        path.addLine(to: CGPoint(x: gapX, y: end.y - radius * down))
        path.addQuadCurve(to: CGPoint(x: gapX + radius, y: end.y), control: CGPoint(x: gapX, y: end.y))
        path.addLine(to: end)
        return path
    }
}

/// Where each node sits: a column per dependency depth, a node's height growing with its matrix jobs.
struct CIGraphLayout {
    static let nodeWidth: CGFloat = 260
    static let headerHeight: CGFloat = 40
    static let matrixRowHeight: CGFloat = 24
    static let columnGap: CGFloat = 56
    static let rowGap: CGFloat = 14

    let frames: [String: CGRect]
    let size: CGSize

    init(_ graph: CIGraph) {
        var frames: [String: CGRect] = [:]
        var height: CGFloat = 0
        for (column, nodes) in graph.columns.enumerated() {
            var y: CGFloat = 0
            let x = CGFloat(column) * (Self.nodeWidth + Self.columnGap)
            for node in nodes {
                let nodeHeight = Self.height(of: node)
                frames[node.id] = CGRect(x: x, y: y, width: Self.nodeWidth, height: nodeHeight)
                y += nodeHeight + Self.rowGap
            }
            height = max(height, y - Self.rowGap)
        }
        self.frames = frames
        let columns = CGFloat(graph.columns.count)
        size = CGSize(width: max(0, columns * Self.nodeWidth + (columns - 1) * Self.columnGap), height: max(0, height))
    }

    static func height(of node: CIGraph.Node) -> CGFloat {
        node.jobs.count > 1 ? headerHeight + CGFloat(node.jobs.count) * matrixRowHeight + 4 : headerHeight
    }
}

/// A job's card: status and name, and a matrix's jobs listed under it.
private struct CIGraphNodeView: View {
    let node: CIGraph.Node
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                row(title: node.title, status: node.status, job: node.jobs.count == 1 ? node.jobs.first : nil, isHeader: true)
                    .frame(height: CIGraphLayout.headerHeight)
                if node.jobs.count > 1 {
                    ForEach(node.jobs) { job in
                        row(title: job.name, status: job.status, job: job, isHeader: false)
                            .frame(height: CIGraphLayout.matrixRowHeight)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(node.jobs.isEmpty)
        .help(node.jobs.isEmpty ? "\(node.title) hasn\u{2019}t started" : "Show \(node.title)\u{2019}s steps and log")
    }

    private func row(title: String, status: CIRunStatus?, job: CIJob?, isHeader: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let status {
                CIStatusIcon(status: status, size: isHeader ? 12 : 11)
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Not started")
            }
            Text(title)
                .font(.system(size: 12, weight: isHeader ? .medium : .regular))
                .foregroundStyle(status == nil || status == .skipped ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.xs)
            if let job, job.status != .skipped {
                CIElapsedText(start: job.startedDate, end: job.completedDate, isActive: job.status.isActive)
            }
        }
        .padding(.leading, isHeader ? 0 : Theme.Spacing.md)
    }
}

#Preview {
    let vm = CIRunDetailViewModel(repository: MockGitRepository())
    return CIGraphView()
        .environment(vm)
        .frame(width: 760)
        .padding()
        .background(Theme.background)
        .task { await vm.show(MockData.ciRuns[0]) }
}
