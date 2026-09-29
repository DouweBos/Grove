// DesignSystem/Toast.swift
// Grove
//
// Brief confirmation at the bottom of the key window, e.g. after copying a SHA.

import SwiftUI

@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Equatable {
        let id = UUID()
        let symbol: String
        let message: String
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        let toast = Toast(symbol: symbol, message: message)
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, self?.current == toast else { return }
            self?.current = nil
        }
    }
}

struct ToastView: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol).foregroundStyle(Theme.success)
            Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .shadow(color: Theme.textPrimary.opacity(0.12), radius: 8, y: 2)
    }
}

private struct ToastOverlay: ViewModifier {
    // Every window observes the shared center, so only the active one shows it.
    @Environment(\.appearsActive) private var appearsActive
    private let center = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if appearsActive, let toast = center.current {
                ToastView(symbol: toast.symbol, message: toast.message)
                    .id(toast.id)
                    .padding(.bottom, Theme.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.25), value: center.current)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

#Preview {
    ToastView(symbol: "checkmark.circle.fill", message: "Copied SHA")
        .padding(40)
        .background(Theme.background)
}
