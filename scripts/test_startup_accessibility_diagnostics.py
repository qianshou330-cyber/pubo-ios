"""Observation-only source contracts; do not assert native readiness on Linux."""
import pathlib
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class StartupDiagnosticsTests(unittest.TestCase):
 def test_synthetic_bounded_main_actor(self):
  s=(ROOT/'App/Infrastructure/StartupAccessibilityDiagnostics.swift').read_text()
  for x in ['#if DEBUG','@MainActor enum','--ui-testing','--chat-load-fail-once','--isolated-backend','!samplingStarted','0..<60','emitted < 128','layoutEmitted < 32','terminal || emitted < 124','catch { return }','ProcessInfo.processInfo.systemUptime']:
   self.assertIn(x,s)
  for x in ['session.token','peer.id','@State','PreferenceKey','isHittable','setNeedsLayout']:
   self.assertNotIn(x,s)
 def test_background_observation_not_control(self):
  s=(ROOT/'App/Infrastructure/StartupAccessibilityDiagnostics.swift').read_text()
  for x in ['content.background','geometry.frame(in: .global)','.allowsHitTesting(false).accessibilityHidden(true)','.onAppear','.onChange(of: frame)']:
   self.assertIn(x,s)
 def test_sampling_not_joined_to_start(self):
  s=(ROOT/'App/PUBOApp.swift').read_text()
  self.assertIn('await session.start()',s)
  self.assertIn('await StartupAccessibilityDiagnostics.sampleMainScheduling()',s)
  self.assertNotIn('async let',s)
 def test_export_does_not_replace_gate(self):
  s=(ROOT/'scripts/simulator-tests.py').read_text().split('startup_capture =',1)[1].split("if shard == 'video-poster':",1)[0]
  self.assertIn("'1h'",s)
  self.assertIn("'INCOMPLETE'",s)
  self.assertNotIn('test_exit =',s)
  gate=(ROOT/'UITests/AppNavigationUITestSupport.swift').read_text()
  for x in ['timeout: 8','button.isHittable == true','button.tap()','button.isSelected']:
   self.assertIn(x,gate)
if __name__=='__main__': unittest.main()
