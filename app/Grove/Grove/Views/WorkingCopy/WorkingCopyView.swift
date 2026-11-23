// Views/WorkingCopy/WorkingCopyView.swift
// Grove
//
// The Changes tab, from GroveUIKit, with what only Grove has: profiles and templates in Settings,
// external diff and merge tools, Finder, and the toolbar's stash and snapshot sheets.

import AppKit
import GroveKit
import GroveUIKit
import SwiftUI

struct WorkingCopyView: View {
    let viewModel: WorkingCopyViewModel
    /// Opens the toolbar's Stash sheet with these paths ticked.
    var stashFiles: ([String]) -> Void = { _ in }

    @Environment(\.openSettings) private var openSettings
    @AppStorage("WorkingCopyLeftWidth") private var leftWidth: Double = 360
    @AppStorage(GrovePreferences.Key.diffToolPath) private var diffToolPath = ""
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""
    private var settings = DiffSettings()

    init(viewModel: WorkingCopyViewModel, stashFiles: @escaping ([String]) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.stashFiles = stashFiles
    }

    var body: some View {
        GitWorkingCopyView(viewModel: viewModel, host: host)
            .padding(.bottom, Theme.Spacing.lg)
    }

    private var host: GitWorkingCopyHost {
        var host = GitWorkingCopyHost()
        let root = viewModel.repository.path
        host.openFile = { NSWorkspace.shared.open(root.appendingPathComponent($0)) }
        host.profiles = GitIdentityProfiles(load: { UserProfileStore.shared.profiles },
                                            manage: { [openSettings] in PreferencesTab.profiles.open(openSettings) })
        host.manageTemplates = { [openSettings] in PreferencesTab.templates.open(openSettings) }
        host.present = { [stashFiles] dialog in
            switch dialog {
            case .stash(let paths?): stashFiles(paths)
            case .stash(nil): GroveAction.stash.post()
            case .snapshot: GroveAction.saveSnapshot.post()
            default: break
            }
        }
        let vm = viewModel
        if !diffToolPath.isEmpty {
            host.openInDiffTool = { entry, side in Task { await vm.openInDiffTool(entry, side: side) } }
        }
        if !mergeToolPath.isEmpty {
            host.openInMergeTool = { entry in Task { await vm.openInMergeTool(entry) } }
        }
        host.diffOptions = settings.options
        host.leftWidth = $leftWidth
        return host
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
