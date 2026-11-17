"""Source wiring contracts, not substitute for UIKit execution."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class RefreshScrollProbeTests(unittest.TestCase):
 def setUp(self):
  self.probe=(ROOT/'App/Infrastructure/RefreshScrollProbe.swift').read_text()
  self.diag=(ROOT/'App/Infrastructure/RefreshDiagnostics.swift').read_text()
  self.timeline=(ROOT/'App/Features/TimelineView.swift').read_text()
 def test_probe_debug_and_fixture_only(self):
  self.assertTrue(self.probe.startswith('#if DEBUG\n'))
  self.assertTrue(self.probe.rstrip().endswith('#endif'))
  for flag in ('--ui-testing','--refreshable-feed'):
   self.assertIn('arguments.contains("'+flag+'")',self.probe)
   self.assertIn('arguments.contains("'+flag+'")',self.timeline)
  self.assertIn('.allowsHitTesting(false).accessibilityHidden(true)',self.timeline)
 def test_observation_is_passive(self):
  for forbidden in ('.delegate =','addGestureRecognizer(','.beginRefreshing(','.endRefreshing(','.setContentOffset(','.sendActions(','.isEnabled =','Timer('):
   self.assertNotIn(forbidden,self.probe)
  self.assertIn('found.observe(\\.contentOffset',self.probe)
  self.assertIn('scroll.adjustedContentInset.top',self.probe)
  self.assertIn('scroll.refreshControl?.isRefreshing',self.probe)
 def test_cleanup_and_output_bounds(self):
  self.assertIn('coordinator.detach()',self.probe)
  self.assertIn('offsetObservation?.invalidate()',self.probe)
  self.assertIn('removeTarget(self',self.probe)
  self.assertIn('scrollEmitted < 128',self.diag)
  self.assertIn('offsetEmitted < 64',self.diag)
  self.assertIn('if emitted < 128',self.diag)
  self.assertIn('systemUptime',self.diag)
  self.assertIn('processIdentifier',self.diag)
 def test_original_refresh_and_gesture_remain(self):
  self.assertIn('RefreshDiagnostics.shared.record(.pullStarted)',self.timeline)
  self.assertIn('defer { RefreshDiagnostics.shared.record(.pullEnded) }',self.timeline)
  self.assertIn('await refreshOwner.run',self.timeline)
  self.assertIn('.simultaneousGesture(DragGesture(minimumDistance: 60).onEnded(switchTimeline))',self.timeline)
if __name__=='__main__':unittest.main()
