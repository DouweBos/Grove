// DesignSystem/GitUIHost+Grove.swift
// Grove
//
// Grove's clipboard and toasts for GroveUIKit.

import GroveUIKit

extension GitUIHost {
    static let grove = GitUIHost(toast: { message in ToastCenter.shared.show(message) })
}
