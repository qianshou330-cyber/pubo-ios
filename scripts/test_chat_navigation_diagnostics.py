from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class NavigationDiagnosticsTests(unittest.TestCase):
 def test_bounded_synthetic_and_nonpersonal(self):
  s=(ROOT/'App/Infrastructure/ChatNavigationDiagnostics.swift').read_text()
  for x in ['#if DEBUG','--ui-testing','--chat-align','--four-tabs-drafts','!ProcessInfo.processInfo.arguments.contains("--isolated-backend")','emitted < 128','capReached=']:
   self.assertIn(x,s)
  for x in ['peer.id','session.user','session.token','debugDescription','Timer(','Task {','addTarget','gestureRecognizer','sendAction']:
   self.assertNotIn(x,s)
 def test_passive_path_lease_and_keyboard(self):
  s=(ROOT/'App/Infrastructure/AppSession.swift').read_text()
  self.assertIn('previousDepth: oldValue.count',s)
  self.assertIn('ChatNavigationDiagnostics.record(.leasesChanged, session: self)',s)
  b=(ROOT/'App/Components/BottomTabBar.swift').read_text()
  self.assertIn('if !keyboardVisible && !session.hidesBottomTabs',b)
  self.assertIn('.onAppear { session.conversationTabLeases[lease] = session.selectedTab }',b)
  self.assertIn('.onDisappear { session.conversationTabLeases.removeValue(forKey: lease) }',b)
  self.assertIn('visible ? .keyboardVisible : .keyboardHidden',b)
 def test_private_lifecycle_and_gate_preserved(self):
  s=(ROOT/'App/Features/ChatView.swift').read_text()
  for event in ['privateTaskEntered','privatePeerReturned','privateDisappear']:
   self.assertIn('ChatNavigationDiagnostics.record(.'+event,s)
  self.assertIn('guard !Task.isCancelled, active else { return }',s)
  ui=(ROOT/'UITests/ChatComposerParityUITests.swift').read_text()
  self.assertIn('waitForExistence(timeout: 8)',ui)
 def test_export_cannot_override_results(self):
  s=(ROOT/'scripts/simulator-tests.py').read_text()
  block=s.split("if shard == 'chat-presentation-composer' or private_back_probe:",1)[1].split("if shard == 'chat-presentation-states':",1)[0]
  for x in ['timeout=60',"'INCOMPLETE'",'chatnavigation-capture','event=privateTaskEntered']:
   self.assertIn(x,block)
  self.assertNotIn('test_exit =',block)
