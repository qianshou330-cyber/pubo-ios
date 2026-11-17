from pathlib import Path
import unittest
P=Path(__file__).resolve().parents[1]/'App/Features/AccountSettingsView.swift'
class ProbeTests(unittest.TestCase):
 def setUp(self): self.s=P.read_text().split('private struct PrivacySwitchEventProbe:',1)[1].split('\n#endif',1)[0]
 def test_fixture_islocked_only_timer(self):
  self.assertIn('guard key == "isLocked"',self.s)
  self.assertIn('arguments.contains("--ui-testing")',self.s)
  self.assertIn('observationTimer == nil else { return }',self.s)
  self.assertIn('Timer(timeInterval: 0.5',self.s)
 def test_view_lifetime_and_weak_capture(self):
  self.assertIn('[weak self]',self.s)
  self.assertIn('guard let self, self.window != nil else',self.s)
  self.assertIn('if window == nil {\n                observationTimer?.invalidate()',self.s)
  self.assertIn('deinit { observationTimer?.invalidate() }',self.s)
  self.assertNotIn('observationDeadline',self.s)
 def test_scan_and_log_bound(self):
  self.assertIn('scanned <= 100',self.s)
  self.assertIn('for _ in 0..<8',self.s)
  self.assertIn('guard emitted < 128 else { return }',self.s)
  self.assertIn('emitted += 1',self.s)
 def test_no_input_or_state_manipulation(self):
  for x in ['sendActions','setOn(','.isOn =','.isEnabled =','addGestureRecognizer']:
   self.assertNotIn(x,self.s)
  self.assertIn('isUserInteractionEnabled = false',self.s)
  self.assertIn('isAccessibilityElement = false',self.s)
if __name__=='__main__': unittest.main()
