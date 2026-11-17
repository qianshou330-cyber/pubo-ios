from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ConversationDiagnosticTests(unittest.TestCase):
 def test_fixture_and_debug_gated(self):
  s=(ROOT/'App/Infrastructure/ConversationDiagnostics.swift').read_text()
  self.assertTrue(s.startswith('#if DEBUG\n'))
  self.assertTrue(s.rstrip().endswith('#endif'))
  self.assertIn('arguments.contains("--ui-testing") && arguments.contains("--chat-align")',s)
  self.assertIn('guard emitted < 128 else { return }',s)
 def test_no_input_handlers_or_request_data(self):
  s=(ROOT/'App/Infrastructure/ConversationDiagnostics.swift').read_text()
  for token in ['gesture','addTarget','sendAction','session.call','row.id','userId','message.raw']:
   self.assertNotIn(token,s)
  self.assertIn('processIdentifier',s);self.assertIn('systemUptime',s)
 def test_observation_only_hooks(self):
  s=(ROOT/'App/Features/ChatListView.swift').read_text()
  self.assertEqual(s.count('ConversationDiagnostics.shared.record(.rowAppeared)'),1)
  self.assertEqual(s.count('ConversationDiagnostics.shared.record(.destinationAppeared)'),2)
  self.assertNotIn('simultaneousGesture',s)
if __name__=='__main__':unittest.main()
