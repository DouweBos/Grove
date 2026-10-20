// GitErrorMessageTests.swift
// GroveKitTests

import Testing
@testable import GroveKit

struct GitErrorMessageTests {

    @Test func rejectedPushExplainsToPullFirst() {
        let stderr = """
        To https://github.com/DouweBos/Argus.git
         ! [rejected]        HEAD -> main (fetch first)
        error: failed to push some refs to 'https://github.com/DouweBos/Argus.git'
        hint: Updates were rejected because the remote contains work that you do not
        hint: have locally.
        """
        #expect(GitErrorMessage.message(command: "push", stderr: stderr)
                == "The remote has commits you don't have yet. Pull them first, then push again.")
    }

    @Test func overwrittenChangesListTheFiles() {
        let stderr = """
        error: Your local changes to the following files would be overwritten by checkout:
        \tREADME.md
        \tSources/App.swift
        Please commit your changes or stash them before you switch branches.
        Aborting
        """
        #expect(GitErrorMessage.message(command: "checkout", stderr: stderr)
                == "Your uncommitted changes would be overwritten: README.md, Sources/App.swift. Commit or stash them first.")
    }

    @Test func unknownErrorsLoseHintsAndPrefixes() {
        let stderr = "fatal: invalid reference: nope\nhint: try something else\n"
        #expect(GitErrorMessage.message(command: "switch", stderr: stderr) == "Invalid reference: nope")
    }

    @Test func stalledTransferSaysTheRemoteStoppedResponding() {
        let stderr = "error: RPC failed; curl 28 Operation too slow. Less than 1 bytes/sec transferred the last 30 seconds\n"
        #expect(GitErrorMessage.message(command: "fetch", stderr: stderr)
                == "The remote stopped responding. Check your internet connection and try again.")
    }

    @Test func emptyStderrNamesTheCommand() {
        #expect(GitErrorMessage.message(command: "fetch", stderr: "hint: nothing\n") == "git fetch failed.")
    }
}
