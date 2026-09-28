// DesignSystem/InitialAvatar.swift
// Grove
//
// Circle with a person's initial, for authors and committers.

import SwiftUI

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 20

    private var initial: String { String(name.prefix(1)).uppercased() }
    // String.hashValue is seeded per launch; a scalar sum keeps each person's color stable.
    private var colorIndex: Int { name.unicodeScalars.reduce(0) { $0 + Int($1.value) } }

    var body: some View {
        Text(initial.isEmpty ? "?" : initial)
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.pillSelectedText)
            .frame(width: size, height: size)
            .background(Theme.laneColor(colorIndex), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        InitialAvatar(name: "Douwe Bos")
        InitialAvatar(name: "Test User", size: 28)
        InitialAvatar(name: "")
    }
    .padding()
    .background(Theme.surface)
}
