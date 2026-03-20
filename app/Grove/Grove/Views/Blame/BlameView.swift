// Views/Blame/BlameView.swift
// Grove

import SwiftUI

// MARK: - BlameView

/// Full-screen blame view for a single file.
///
/// Three-column layout that scrolls vertically as a unit:
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │  BlameNavigationBar (file path, revision, Prev/Current) │
/// ├──────┬──────────────────────────────────┬───────────────┤
/// │  ##  │  source code (monospaced)        │ commit summary│
/// │  ##  │                                  │ author · date │
/// │  ##  │                                  │               │
/// └──────┴──────────────────────────────────┴───────────────┘
/// ```
///
/// All three columns share a single `ScrollView` so they stay in sync.
struct BlameView: View {

    // MARK: - Properties

    @State private var viewModel: BlameViewModel

    // MARK: - Column Widths

    private static let lineNumberWidth: CGFloat = 52
    private static let annotationWidth: CGFloat = 260

    // MARK: - Init

    /// - Parameters:
    ///   - filePath: Repository-relative path of the file to blame.
    ///   - revision: Starting revision. Pass `nil` to start at HEAD.
    ///   - repository: The backing Git repository.
    init(
        filePath: String,
        revision: String? = nil,
        repository: any GitRepositoryProtocol
    ) {
        _viewModel = State(
            initialValue: BlameViewModel(
                filePath: filePath,
                revision: revision,
                repository: repository
            )
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            BlameNavigationBar(
                filePath: viewModel.filePath,
                revision: viewModel.revision,
                canNavigateToPrevious: viewModel.canNavigateToPrevious,
                canNavigateToCurrent: viewModel.canNavigateToCurrent,
                onPrevious: {
                    Task { await viewModel.navigateToPreviousRevision() }
                },
                onCurrent: {
                    Task { await viewModel.navigateToCurrentRevision() }
                }
            )

            // Content area
            contentArea
        }
        .task {
            await viewModel.loadBlame()
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading {
            loadingState
        } else if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.sourceLines.isEmpty {
            emptyState
        } else {
            blameContent
        }
    }

    // MARK: - Blame Content

    private var blameContent: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {

                // Left: line numbers
                BlameLineNumberColumn(lineCount: viewModel.lineCount)
                    .frame(width: Self.lineNumberWidth)

                Divider()

                // Centre: source code
                BlameSourceColumn(lines: viewModel.sourceLines)
                    .frame(minWidth: 400)

                Divider()

                // Right: blame annotations
                BlameAnnotationColumn(
                    entries: viewModel.blameEntries,
                    lineCount: viewModel.lineCount
                )
                .frame(width: Self.annotationWidth)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - State Views

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading blame\u{2026}")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Failed to load blame")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await viewModel.loadBlame() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No blame information available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    BlameView(
        filePath: "Sources/Grove/Views/WorkingCopy/WorkingCopyView.swift",
        revision: nil,
        repository: MockGitRepository()
    )
    .frame(width: 900, height: 600)
}
