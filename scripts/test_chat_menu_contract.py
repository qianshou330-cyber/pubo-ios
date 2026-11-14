"""Source wiring checks only; UIKit runtime menu evidence remains mandatory."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class ChatMenuContractTests(unittest.TestCase):
    def test_textkit_retains_system_selection_and_default_note_menu(self):
        s = (ROOT / 'App/Components/RichNoteText.swift').read_text()
        self.assertIn('view.isSelectable = true', s)
        self.assertIn('guard !menuActions.isEmpty else { return nil }', s)
        self.assertIn('let commands: [UIMenuElement] = menuActions.map { $0.uiAction }', s)
        self.assertIn('commands + suggestedActions', s)
        self.assertIn('shouldInteractWith URL: URL', s)
        self.assertIn('coordinator.menuActions = []', s)

    def test_three_entry_points_share_actions_for_both_chat_types(self):
        for name, role in [('ChatView', 'own'), ('RoomChatView', 'mine')]:
            s = (ROOT / ('App/Features/' + name + '.swift')).read_text()
            self.assertIn('menuActions: messageActions(message, ' + role + ': ' + role + ')', s)
            self.assertIn('ChatMenuButtons(actions: messageActions(message, ' + role + ': ' + role + '))', s)
            self.assertIn('.contextMenu { messageMenu(message, ' + role + ': ' + role + ') }', s)
            self.assertIn('epoch == session.generation, owner == session.user?.id', s)
            self.assertIn('current.raw == message.raw', s)
            self.assertIn('current["recalledAt"].isNull', s)
            self.assertIn('guard active, scenePhase == .active', s)
        content = (ROOT / 'App/Components/ChatMessageContent.swift').read_text()
        self.assertIn('menuActions: enabled ? menuActions : []', content)

    def test_destructive_action_keeps_confirmation_and_original_longpress_test(self):
        s = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        self.assertIn('requestMessageDeletion(message)', s)
        ui = (ROOT / 'UITests/ChatAlignmentUITests.swift').read_text()
        self.assertIn('bubble.press(forDuration: 1)', ui)
        self.assertIn('XCTAssertTrue(reportAction.waitForExistence(timeout: 5))', ui)
        self.assertIn('Confirmed deletion must remove the original message', ui)
        self.assertIn('ownText.press(forDuration: 1)', ui)
        self.assertIn('Cancel must retain the original message', ui)

    def test_recalled_private_message_details_remain_available(self):
        s = (ROOT / 'App/Features/ChatView.swift').read_text()
        self.assertIn('allowRecalled: Bool = false', s)
        self.assertIn('(allowRecalled || current["recalledAt"].isNull), current.raw == message.raw', s)
        self.assertIn('own ? "编辑／撤回消息" : "消息反应／举报", allowRecalled: true) { actionMessage = message }', s)
        self.assertEqual(s.count('allowRecalled: true'), 1)
