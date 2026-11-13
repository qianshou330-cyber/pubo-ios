"""Source contracts only, not proof of Darwin compilation or UI behavior."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ChatLoadingGateContract(unittest.TestCase):
    def test_notify_apis_import_explicit_header_module_in_both_processes(self):
        # Source regression only; the macOS preflight remains the compilation gate.
        for path in ('App/Infrastructure/ChatFixtureResponseGate.swift',
                     'UITests/ChatLoadingTestGate.swift'):
            source = (ROOT / path).read_text()
            self.assertIn('import PUBONotify\n', source)

    def test_notify_module_uses_real_sdk_header_and_all_build_paths(self):
        self.assertIn('#include <notify.h>', (ROOT / 'Interop/PUBONotify/PUBONotify.h').read_text())
        self.assertIn('header "PUBONotify.h"', (ROOT / 'Interop/PUBONotify/module.modulemap').read_text())
        self.assertIn("SWIFT_INCLUDE_PATHS: '$(inherited) $(SRCROOT)/Interop/PUBONotify'", (ROOT / 'project.yml').read_text())
        self.assertIn('swiftc -I "$root/Interop/PUBONotify"', (ROOT / 'scripts/check_chat_gate_macos.sh').read_text())

    def test_gate_is_debug_transport_only_and_keeps_failure_delay(self):
        gate = (ROOT / 'App/Infrastructure/ChatFixtureResponseGate.swift').read_text()
        transport = (ROOT / 'App/Infrastructure/FixtureTransport.swift').read_text()
        self.assertTrue(gate.startswith('#if DEBUG\n'))
        self.assertIn('guard path == expected else { return }', gate)
        self.assertIn('UUID(uuidString: nonce) != nil', gate)
        block = transport[transport.index('if ["chat/messages/user-timeline"'):transport.index('if path == "i/registry/get"')]
        self.assertIn('if args.contains("--chat-load-gate")', block)
        self.assertIn('ChatFixtureResponseGate.wait(path: path)', block)
        self.assertIn('if args.contains("--chat-load-delay") { try await Task.sleep(for: .seconds(5)) }', block)
        self.assertIn('--chat-load-fail-once', block)

    def test_real_loading_before_release_and_original_timeouts(self):
        ui = (ROOT / 'UITests/ChatComposerParityUITests.swift').read_text()
        block = ui[ui.index('func testInitialLoadingAndEmptyConversationStates'):ui.index('func testInitialFailureHasExplicitRetryAndRecovers')]
        self.assertIn('loading.waitForExistence(timeout: 3)', block)
        self.assertIn('empty.waitForExistence(timeout: 15)', block)
        self.assertIn('XCTAssertFalse(loading.exists)', block)
        self.assertLess(block.index('capture(app, "chat-state-loading-"'), block.index('try gate.release()'))
        self.assertLess(block.index('ChatLoadingTestGate(room: room)'), block.index('let app = launch'))
        self.assertNotIn('--chat-load-delay', block)
        self.assertIn('defer { gate.close() }', block)
        self.assertIn('defer { app.terminate() }', block)

    def test_state_persists_and_wait_cancels_or_fails_not_succeeds(self):
        app = (ROOT / 'App/Infrastructure/ChatFixtureResponseGate.swift').read_text()
        runner = (ROOT / 'UITests/ChatLoadingTestGate.swift').read_text()
        self.assertIn('notify_get_state(token, &state)', app)
        self.assertIn('if state == 1 { return }', app)
        self.assertIn('throw failure("timeout")', app)
        self.assertIn('try Task.checkCancellation()', app)
        self.assertIn('defer { notify_cancel(token) }', app)
        self.assertNotIn('try?', app)
        self.assertIn('UUID().uuidString', runner)
        self.assertIn('notify_set_state(value, 0)', runner)
        self.assertIn('notify_set_state(token, 1)', runner)
        self.assertIn('notify_cancel(token)', runner)
        self.assertNotIn('CFNotification', app + runner)

if __name__ == '__main__':
    unittest.main()
