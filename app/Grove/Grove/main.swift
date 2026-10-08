// main.swift
// Grove
//
// `grove` runs this binary with --grove-cli, which answers in Terminal and exits instead of starting the app.

import SwiftUI

MainActor.assumeIsolated {
    if CommandLine.arguments.dropFirst().first == GroveCLI.flag {
        GroveCLI.run(Array(CommandLine.arguments.dropFirst(2)))
    }
    GroveApp.main()
}
