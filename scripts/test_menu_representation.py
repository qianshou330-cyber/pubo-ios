"""Source contracts only: actual MenuItem/UIButton tapping requires Simulator CI."""
from pathlib import Path
import unittest
class MenuRepresentationTests(unittest.TestCase):
 def setUp(self):
  s=(Path(__file__).resolve().parents[1]/"UITests/PUBOUITests.swift").read_text()
  self.s=s.split("func testChatEditConflictAndLostResponseKeepDraftUntilManualResolution()",1)[1].split("\n    func ",1)[0]
 def test_exact_type_and_action_for_each_native_representation(self):
  self.assertIn('(elementType == %d AND identifier == %@) OR (elementType == %d AND label == %@)',self.s)
  self.assertIn('XCUIElement.ElementType.button.rawValue, "chat.actions.chatpreview002"',self.s)
  self.assertIn('XCUIElement.ElementType.menuItem.rawValue, "编辑／撤回消息"',self.s)
  self.assertIn('app.descendants(matching: .any).matching(actionPredicate).firstMatch',self.s)
 def test_single_existence_budget_and_real_input(self):
  self.assertEqual(self.s.count('action.waitForExistence(timeout: 5)'),1)
  self.assertEqual(self.s.count('sent.press(forDuration: 1)'),1)
  self.assertEqual(self.s.count('action.tap()'),1)
  self.assertNotIn('coordinate(',self.s)
 def test_consequential_assertions_retained(self):
  for x in ['XCTAssertTrue((editor.value as? String)?.contains("Draft") == true)',
            'XCTAssertFalse(save.exists)', '另一台设备已编辑', '以当前版本继续编辑',
            '已核对，编辑已生效。', 'XCTAssertFalse(editor.exists)']:
   self.assertIn(x,self.s)
if __name__=="__main__": unittest.main()
