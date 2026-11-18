"""Source contracts only: native report presentation still requires real CI."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RoomReportDiagnosticsTests(unittest.TestCase):
 def test_capture_is_bounded_synthetic_nonpersonal(self):
  s=(ROOT/'App/Infrastructure/RoomReportDiagnostics.swift').read_text()
  for x in ['#if DEBUG','@MainActor','--ui-testing','--chat-align','--isolated-backend','count < 32','flags: [Bool]','ProcessInfo.processInfo.systemUptime']:
   self.assertIn(x,s)
  for x in ['message.text','message.id','session.user','token','localizedDescription']:
   self.assertNotIn(x,s)
 def test_original_action_guards_retained(self):
  s=(ROOT/'App/Features/RoomChatView.swift').read_text()
  block=s.split('func command(_ id:',1)[1].split('var actions:',1)[0]
  for x in ['guard active, scenePhase == .active, section == "messages", preview == nil,','epoch == session.generation, owner == session.user?.id,','let current = messages.first(where: { $0.id == message.id }),','current["recalledAt"].isNull, current.raw == message.raw else {']:
   self.assertIn(x,block)
  self.assertEqual(block.count('perform()'),1)
  for stage in ['actionEntered','rejected','accepted','stateAssigned']:
   self.assertIn('.'+stage,block)
 def test_real_sheet_and_assertions_retained(self):
  s=(ROOT/'App/Features/RoomChatView.swift').read_text()
  for x in ['.sheet(item: $reporting)','ReportView(userID:', '.sheetAppeared', '.sheetDisappeared', 'reporting = message']:
   self.assertIn(x,s)
  u=(ROOT/'UITests/ChatAlignmentUITests.swift').read_text()
  for x in ['reportAction.tap()','reason.waitForExistence(timeout: 5)','/chat/messages/room0001','欢迎来到音乐交流群']:
   self.assertIn(x,u)
 def test_collector_does_not_pass_failed_job(self):
  s=(ROOT/'scripts/simulator-tests.py').read_text().split("if shard == 'chat-alignment-actions':",1)[1].split("if shard == 'video-poster':",1)[0]
  self.assertIn("'INCOMPLETE'",s)
  self.assertIn('timeout=60',s)
  self.assertNotIn('test_exit =',s)
if __name__=='__main__':unittest.main()
