"""Static privacy/noninterference contracts; native hit-test behavior needs CI."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class TabHitDiagnosticsTests(unittest.TestCase):
 def test_gates_bounds_and_privacy(self):
  s=(ROOT/'App/Infrastructure/TabHitDiagnostics.swift').read_text()
  for token in ['#if DEBUG','--ui-testing','--isolated-backend','--chat-preview-failure','--video-poster-fixture=','0..<30','<= 120','windows.prefix(8)','0..<12','!TabHitDiagnostics.started','Task.isCancelled','sampling?.cancel()']:
   self.assertIn(token,s)
  for token in ['accessibilityLabel','accessibilityIdentifier','NSStringFromClass','session.token','sendAction','touchesBegan','setNeedsLayout','layoutIfNeeded']:
   self.assertNotIn(token,s)
 def test_background_only_and_no_ax_override(self):
  s=(ROOT/'App/Infrastructure/TabHitDiagnostics.swift').read_text()
  self.assertIn('view.isUserInteractionEnabled = false',s)
  self.assertIn('.allowsHitTesting(false).accessibilityHidden(true)',s)
  self.assertIn('candidate.hitTest(local, with: nil)',s)
  self.assertNotIn('isHittable',s)
 def test_collector_not_gate(self):
  s=(ROOT/'scripts/simulator-tests.py').read_text().split('hit_capture =',1)[1].split("if shard == 'chat-alignment-actions':",1)[0]
  self.assertIn("'INCOMPLETE'",s); self.assertIn('timeout=60',s)
  self.assertNotIn('test_exit =',s)
