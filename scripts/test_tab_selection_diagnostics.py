from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class SelectionDiagnosticsTests(unittest.TestCase):
 def test_bounded_typed_events(self):
  s=(ROOT/'App/Infrastructure/TabHitDiagnostics.swift').read_text()
  for x in ['enum SelectionEvent: String','selectionEvents < 64','guard enabled','from: AppTab, to: AppTab','--ui-testing','--isolated-backend']:
   self.assertIn(x,s)
  method=s.split('static func selection(',1)[1].split('static var started',1)[0]
  for x in ['token','user','label','selectedTab =']:
   self.assertNotIn(x,method)
 def test_original_action_once(self):
  s=(ROOT/'App/Components/BottomTabBar.swift').read_text()
  self.assertEqual(s.count('if session.selectedTab != tab { session.selectedTab = tab }'),1)
  self.assertLess(s.index('.actionEntered'),s.index('if session.selectedTab != tab'))
  self.assertGreater(s.index('.actionReturned'),s.index('if session.selectedTab != tab'))
 def test_observer_readonly(self):
  s=(ROOT/'App/Infrastructure/AppSession.swift').read_text().split('var selectedTab = AppTab.messages',1)[1].split('var hidesBottomTabs',1)[0]
  self.assertIn('didSet',s);self.assertIn('#if DEBUG',s);self.assertIn('oldValue != selectedTab',s)
  self.assertIn('.selectionChanged',s);self.assertNotIn('selectedTab =',s)
