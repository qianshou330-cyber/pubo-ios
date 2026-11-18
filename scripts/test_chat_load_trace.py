"""Source contracts for observation-only recovery diagnostics, not runtime proof."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class ChatLoadTraceTests(unittest.TestCase):
    def test_synthetic_only_nonpersonal(self):
        s=(ROOT/'App/Features/ChatView.swift').read_text()
        block=s.split('private func traceLoad(',1)[1].split('private func retryInitialLoad()',1)[0]
        for x in ['#if DEBUG', 'guard session.testMode', '--chat-load-fail-once', 'com.pubo.chatload.diagnostics']:
            self.assertIn(x,block)
        for x in ['peer.id','error.localizedDescription','session.token','message.text']:
            self.assertNotIn(x,block)
    def test_all_recovery_stages_observed(self):
        s=(ROOT/'App/Features/ChatView.swift').read_text()
        for x in ['retry-enter','guard-skipped','load-start','load-exit','timeline-request','timeline-return','state-request','state-return','published','caught','appear','disappear']:
            self.assertIn('traceLoad("'+x+'"',s)
        block=s.split('private func load(older:',1)[1].split('private func updateDraft',1)[0]
        self.assertEqual(block.count('guard epoch == syncEpoch, !Task.isCancelled else { return }'),2)
        self.assertIn('defer { loading = false;',block)
    def test_collection_cannot_override_acceptance(self):
        s=(ROOT/'scripts/simulator-tests.py').read_text()
        block=s.split("if shard == 'chat-presentation-states':",1)[1].split("if shard == 'video-poster':",1)[0]
        self.assertIn('timeout=60',block)
        self.assertIn("'INCOMPLETE'",block)
        self.assertNotIn('test_exit =',block)
        ui=(ROOT/'UITests/ChatComposerParityUITests.swift').read_text()
        self.assertIn('message.waitForExistence(timeout: 15)',ui)
        self.assertIn('retry.tap()',ui)
if __name__=='__main__': unittest.main()
