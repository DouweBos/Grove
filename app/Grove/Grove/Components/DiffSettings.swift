// Components/DiffSettings.swift
// Grove
//
// How every diff is shown, as GroveUIKit's options.

import GroveUIKit
import SwiftUI

struct DiffSettings: DynamicProperty {
    static let wrapLinesKey = "DiffWrapLines"
    static let layoutKey = "DiffLayout"
    static let imageModeKey = "ImageDiffMode"

    @AppStorage(Self.wrapLinesKey) private var wrapsLines = false
    @AppStorage(Self.layoutKey) private var layout: GitDiffLayout = .inline
    @AppStorage(Self.imageModeKey) private var imageMode: GitImageDiffMode = .sideBySide

    var options: GitDiffOptions {
        GitDiffOptions(layout: $layout, wrapsLines: $wrapsLines, imageMode: $imageMode)
    }
}

/// For a header over a read-only diff.
struct DiffToggles: View {
    private var settings = DiffSettings()

    var body: some View {
        GitWrapLinesToggle(isOn: settings.options.wrapsLines)
        GitDiffLayoutPicker(layout: settings.options.layout)
    }
}

/// The shared preference alone, for what isn't a diff, like a CI log.
struct WrapLinesToggle: View {
    @AppStorage(DiffSettings.wrapLinesKey) private var wrapsLines = false

    var body: some View {
        GitWrapLinesToggle(isOn: $wrapsLines)
    }
}

#Preview {
    HStack { DiffToggles() }.padding().background(Theme.surface).gitUIStyle(Theme.gitUI)
}
