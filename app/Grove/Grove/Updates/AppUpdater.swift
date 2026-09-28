// Updates/AppUpdater.swift
// Grove
//
// Sparkle updates from the appcast on houwert.dev, stable or beta.

import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {

    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Debug builds never update themselves; only a signed release replaces its own bundle.
    static var isEnabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    override init() {
        super.init()
        guard Self.isEnabled else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
        self.controller = controller
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // Stable items carry no channel, so every client sees them; beta items only reach opted-in clients.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        GrovePreferences.receivesBetaUpdates ? ["beta"] : []
    }
}
