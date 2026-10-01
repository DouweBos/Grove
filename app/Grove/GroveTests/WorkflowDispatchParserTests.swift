// WorkflowDispatchParserTests.swift
// GroveTests
//
// The workflow_dispatch block of real-world workflow files: every input type, the ways `on` is written,
// and YAML beyond the reader's subset.

import Foundation
import Testing
@testable import Grove

struct WorkflowDispatchParserTests {

    @Test func grovesReleaseWorkflowHasAChannelChoice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let yaml = try String(contentsOf: root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)

        #expect(WorkflowDispatchParser.parse(yaml) == .inputs([
            CIDispatchInput(name: "channel", description: "Release channel", defaultValue: "beta", kind: .choice(["beta", "production"]))
        ]))
    }

    @Test func everyInputTypeIsRead() {
        let yaml = """
        name: Deploy
        "on":
          push:
            branches: [main]
          workflow_dispatch:   # started by hand
            inputs:
              version:
                description: 'The version: "x.y.z"'   # quoted, with a colon
                required: true
              dry-run:
                type: boolean
                default: true
                description: Don't publish
              retries:
                type: number
                default: 3
              target:
                type: environment
              level:
                type: choice
                options: [debug, "info", 'warn']
              notes:
                description: >
                  Shown in the
                  release notes
                default: ''
              bare: {}
        jobs:
          deploy:
            runs-on: ubuntu-latest
            steps:
              - run: echo "inputs: ${{ inputs.version }}"
        """
        guard case .inputs(let inputs) = WorkflowDispatchParser.parse(yaml) else {
            Issue.record("Expected inputs")
            return
        }
        #expect(inputs.map(\.name) == ["version", "dry-run", "retries", "target", "level", "notes", "bare"])
        #expect(inputs[0] == CIDispatchInput(name: "version", description: "The version: \"x.y.z\"", isRequired: true))
        #expect(inputs[1].kind == .boolean && inputs[1].defaultValue == "true" && inputs[1].description == "Don't publish")
        #expect(inputs[2].kind == .number && inputs[2].defaultValue == "3")
        #expect(inputs[3].kind == .environment && inputs[3].defaultValue.isEmpty)
        #expect(inputs[4].kind == .choice(["debug", "info", "warn"]) && inputs[4].defaultValue == "debug")
        #expect(inputs[5].description == "Shown in the release notes" && inputs[5].defaultValue.isEmpty)
        #expect(inputs[6] == CIDispatchInput(name: "bare"))
    }

    @Test func optionsMayBeIndentedOrNot() {
        let yaml = """
        on:
          workflow_dispatch:
            inputs:
              a:
                type: choice
                options:
                - one
                - two
              b:
                type: boolean
        """
        #expect(WorkflowDispatchParser.parse(yaml) == .inputs([
            CIDispatchInput(name: "a", defaultValue: "one", kind: .choice(["one", "two"])),
            CIDispatchInput(name: "b", defaultValue: "false", kind: .boolean)
        ]))
    }

    @Test func aNullDefaultLeavesTheFieldEmpty() {
        let yaml = """
        on:
          workflow_dispatch:
            inputs:
              version:
                default: null
              build:
                type: number
                default: ~   # none
              literal:
                default: 'null'
        """
        #expect(WorkflowDispatchParser.parse(yaml) == .inputs([
            CIDispatchInput(name: "version"),
            CIDispatchInput(name: "build", kind: .number),
            CIDispatchInput(name: "literal", defaultValue: "null")
        ]))
    }

    @Test func theTriggerIsFoundHoweverOnIsWritten() {
        #expect(WorkflowDispatchParser.parse("on: workflow_dispatch\njobs: {}") == .inputs([]))
        #expect(WorkflowDispatchParser.parse("on: [push, workflow_dispatch]") == .inputs([]))
        #expect(WorkflowDispatchParser.parse("on:\n  - push\n  - workflow_dispatch\n") == .inputs([]))
        #expect(WorkflowDispatchParser.parse("on:\n  workflow_dispatch:\n  push:\n") == .inputs([]))
        #expect(WorkflowDispatchParser.parse("on:\r\n  workflow_dispatch: {}\r\n") == .inputs([]))
        #expect(WorkflowDispatchParser.parse("'on':\n  workflow_dispatch:\n    inputs:\n") == .inputs([]))
    }

    @Test func workflowsWithoutTheTriggerAreNotDispatchable() {
        #expect(WorkflowDispatchParser.parse("on: push") == .notDispatchable)
        #expect(WorkflowDispatchParser.parse("on: [push, pull_request]") == .notDispatchable)
        #expect(WorkflowDispatchParser.parse("on:\n  push:\n    branches: [main]\n  # workflow_dispatch:\n") == .notDispatchable)
        #expect(WorkflowDispatchParser.parse("name: x\njobs:\n  a:\n    on: workflow_dispatch\n") == .notDispatchable)
        #expect(WorkflowDispatchParser.parse("") == .notDispatchable)
    }

    @Test func yamlBeyondTheSubsetIsReportedRatherThanMisread() {
        #expect(WorkflowDispatchParser.parse("on: { workflow_dispatch: { inputs: { a: { type: boolean } } } }") == .unreadable)
        #expect(WorkflowDispatchParser.parse("on:\n  workflow_dispatch:\n    inputs: *shared\n") == .unreadable)
        #expect(WorkflowDispatchParser.parse("on:\n  workflow_dispatch:\n    inputs:\n      a: *defaults\n") == .unreadable)
        #expect(WorkflowDispatchParser.parse("on:\n  workflow_dispatch:\n    inputs:\n      a:\n        default: *version\n") == .unreadable)
        #expect(WorkflowDispatchParser.parse("on: { push: {} }") == .notDispatchable)
    }
}
