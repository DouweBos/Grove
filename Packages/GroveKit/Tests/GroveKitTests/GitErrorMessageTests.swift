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

    @Test func refRaceDropsTheRefSummaries() {
        let stderr = """
        error: cannot lock ref 'refs/remotes/origin/main': is at 136dd83a939b0c6679a4c7469ce6a7ba621e8d65 but expected 149529122725eb7a3e2403b329534a4fcc1c1c2a
        From https://github.com/acme/app
         ! 1495291227..95cf1f02a7  main       -> origin/main  (unable to update local ref)
           2e5367a6a7..9c18d5ef57  chore/transifex_f62f419cbb -> origin/chore/transifex_f62f419cbb
         + e7f55233c6...8fcd04ae34 george/disco-8885-import-upsell -> origin/george/disco-8885-import-upsell  (forced update)
        """
        #expect(GitErrorMessage.isRefLockRace(stderr))
        #expect(GitErrorMessage.message(command: "pull", stderr: stderr)
                == "Another git process updated the remote branches at the same time. Try again.")
    }

    @Test func unknownErrorsLoseRefSummaries() {
        let stderr = "fatal: something odd\n * [new branch]      feature    -> origin/feature\n"
        #expect(GitErrorMessage.message(command: "fetch", stderr: stderr) == "Something odd")
    }

    @Test func emptyStderrNamesTheCommand() {
        #expect(GitErrorMessage.message(command: "fetch", stderr: "hint: nothing\n") == "git fetch failed.")
    }
}
