// Views/Repositories/RepositoryDropZoneView.swift
// Grove
//
// The empty-state drop zone shown when no repository is selected.
// Dashed border, git icon, label + three action buttons.

import SwiftUI

// MARK: - RepositoryDropZoneView

/// Drop zone shown when no repository is selected in the browser.
///
/// Accepts folder drops to add repositories. Also surfaces
/// Add / Create / Clone action buttons.
struct RepositoryDropZoneView: View {

    @Environment(WindowViewModel.self) private var viewModel
    @State private var isTargeted = false

    var body: some View {
        VStack {
            Spacer()
            dropZoneCard
            actionButtons
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Drop Zone Card

    private var dropZoneCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Drop Folder or URL\nto Add Git Repository")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 200, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted
                      ? Color.accentColor.opacity(0.05)
                      : Color(nsColor: .windowBackgroundColor))
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleDroppedURLs(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button("Add") {
                viewModel.isShowingAddDialog = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("Create") {
                viewModel.isShowingCreateDialog = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("Clone") {
                viewModel.isShowingCloneDialog = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
        .font(.callout)
    }
}

// MARK: - Preview

#Preview {
    RepositoryDropZoneView()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
        .frame(width: 580, height: 500)
}
