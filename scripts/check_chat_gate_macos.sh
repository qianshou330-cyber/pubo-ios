#!/bin/bash
# Optional preflight only. Does not start CI or access a network/service.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then echo 'Requires macOS / Darwin notify APIs' >&2; exit 2; fi
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/GateMain.swift" <<'SWIFT'
import Foundation

@main struct GateMain {
    static func main() async throws {
        if CommandLine.arguments.contains("--child") {
            try await ChatFixtureResponseGate.wait(path: "chat/messages/user-timeline")
            return
        }
        if CommandLine.arguments.contains("--cancel-child") {
            let task = Task { try await ChatFixtureResponseGate.wait(path: "chat/messages/user-timeline") }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            do { try await task.value; fatalError("Cancellation unexpectedly succeeded") }
            catch is CancellationError { return }
        }
        // Exercise actual app/runner helpers in separate processes, including
        // release before the app registers (the sticky-state no-lost-release case).
        for mode in ["held", "released-before-registration", "cancel"] {
            let gate = try ChatLoadingTestGate(room: false)
            defer { gate.close() }
            if mode == "released-before-registration" { try gate.release() }
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [mode == "cancel" ? "--cancel-child" : "--child"]
            child.environment = ProcessInfo.processInfo.environment.merging(gate.environment) { _, new in new }
            try child.run()
            defer { if child.isRunning { child.terminate() } }
            if mode == "held" {
                try await Task.sleep(for: .milliseconds(500))
                guard child.isRunning else { fatalError("Gate released without test authorization") }
                try gate.release()
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard !child.isRunning else { fatalError("Cross-process gate timed out") }
            child.waitUntilExit()
            guard child.terminationStatus == 0 else { fatalError("Child gate failed") }
            print("PASS: " + mode)
        }
    }
}
SWIFT
xcrun swiftc -D DEBUG -swift-version 5 -parse-as-library \
  "$root/App/Infrastructure/ChatFixtureResponseGate.swift" \
  "$root/UITests/ChatLoadingTestGate.swift" "$tmp/GateMain.swift" -o "$tmp/gate-preflight"
"$tmp/gate-preflight"
