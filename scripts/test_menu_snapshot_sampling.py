"""Source contracts; real two-sample UIKit execution remains required in CI."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class MenuSnapshotSamplingTests(unittest.TestCase):
    def setUp(self):
        source=(ROOT/'UITests/PUBOUITests.swift').read_text()
        self.test=source.split('func testChatEditConflictAndLostResponseKeepDraftUntilManualResolution()',1)[1].split('\n    func ',1)[0]
        self.probe=self.test.split('let probeStarted',1)[1].split('}, object: action)',1)[0]
    def test_one_snapshot_one_native_hit_query(self):
        self.assertEqual(self.probe.count('action.snapshot()'),1)
        self.assertEqual(self.probe.count('action.isHittable'),1)
        for x in ['action.exists','action.isEnabled','action.frame']:
            self.assertNotIn(x,self.probe)
        self.assertIn('snapshot?.isEnabled == true',self.probe)
        self.assertIn('snapshot?.frame',self.probe)
    def test_failed_snapshot_cannot_pass_and_error_is_retained(self):
        self.assertIn('snapshot = nil; snapshotError = String(describing: error)',self.probe)
        self.assertIn('snapshotError=\\(snapshotError)',self.probe)
        self.assertIn('guard hittable else',self.probe)
    def test_two_samples_and_same_time_budget(self):
        self.assertIn('frame == previousFrame',self.probe)
        self.assertIn('previousFrame = frame; stableSince = observedAt; return false',self.probe)
        self.assertIn('observedAt - stableSince >= 0.3',self.probe)
        self.assertEqual(self.test.count('timeout: 12'),1)
    def test_real_single_click_and_both_scenarios(self):
        self.assertIn('for conflict in [true, false]',self.test)
        self.assertEqual(self.test.count('action.tap()'),1)
        self.assertLess(self.test.index('guard outcome == .completed'),self.test.index('action.tap()'))
        self.assertIn('evidence.lifetime = .keepAlways',self.test)
        self.assertNotIn('coordinate(',self.probe)
if __name__=='__main__':unittest.main()
