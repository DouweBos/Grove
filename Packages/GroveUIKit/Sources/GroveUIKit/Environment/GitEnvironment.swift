// Environment/GitEnvironment.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

extension EnvironmentValues {
    @Entry var gitStyle = GitUIStyle.system
    @Entry var gitFeatures = GitFeatures.all
    @Entry var gitHost = GitUIHost.system
}

extension View {
    /// The host's colours and zoom, for every kit view below.
    public func gitUIStyle(_ style: GitUIStyle) -> some View {
        environment(\.gitStyle, style)
    }

    /// What this repository supports; the kit disables the rest.
    public func gitFeatures(_ features: GitFeatures) -> some View {
        environment(\.gitFeatures, features)
    }

    func gitClickable(_ active: Bool = true) -> some View {
        modifier(GitClickable(active: active))
    }

    /// Off with the reason when the repository lacks `feature`.
    func requires(_ feature: GitFeature) -> some View {
        modifier(RequiresFeature(feature: feature))
    }
}

private struct GitClickable: ViewModifier {
    @Environment(\.gitStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    let active: Bool

    func body(content: Content) -> some View {
        content.pointerStyle(style.showsPointingHand && active && isEnabled ? .link : nil)
    }
}

private struct RequiresFeature: ViewModifier {
    @Environment(\.gitFeatures) private var features
    let feature: GitFeature

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reason = features.unavailableReason(feature) {
            content.disabled(true).help(reason)
        } else {
            content
        }
    }
}
#endif
