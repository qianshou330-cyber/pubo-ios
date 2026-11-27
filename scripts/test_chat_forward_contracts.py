"""Static source contracts for C114 1-on-1 chat multi-select (max 10) & friend forwarding; not a substitute for iOS Simulator or physical-device testing."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ChatForwardContracts(unittest.TestCase):
    def test_core_policy_enforces_ten_message_cap_and_safety_rules(self):
        src = (ROOT / 'Sources/PUBOCore/ChatForwardPolicy.swift').read_text()
        self.assertIn('public static let maxSelectionCount = 10', src)
        self.assertIn('public static let maxTextLength = 2_000', src)
        self.assertIn('case limitReached(max: Int)', src)
        self.assertIn('case ineligibleRecalled', src)
        self.assertIn('不能转发消息给自己。', src)
        self.assertIn('ChatEligibility.problem(account: account, peer: recipient)', src)

    def test_forward_sheet_reuploads_private_attachments_per_target_recipient(self):
        src = (ROOT / 'App/Features/ChatForwardSheet.swift').read_text()
        self.assertIn('session.api.privateAttachment(id: attachment.id, token: token)', src)
        self.assertIn('peer: recipient.id', src)
        self.assertIn('session.call("chat/messages/create-to-user", pending.payload, mutation: true)', src)
        self.assertIn('CHAT_FIRST_MESSAGE_TEXT_ONLY', src)
        self.assertIn('CHAT_REPLY_REQUIRED', src)
        self.assertIn('YOU_HAVE_BEEN_BLOCKED', src)
        # Never forward to public rooms/Drive from private chat.
        self.assertNotIn('create-to-room', src)
        self.assertNotIn('drive/files/create', src)

    def test_chat_view_wires_multiselect_in_shared_menu_without_breaking_recalled_contract(self):
        src = (ROOT / 'App/Features/ChatView.swift').read_text()
        self.assertIn('actions.append(command("chat.multiselect." + message.id, "多选")', src)
        self.assertIn('actions.append(command("chat.forward." + message.id, "转发")', src)
        self.assertIn('最多只能选择 \\(maxCount) 条消息', src)
        self.assertIn('accessibilityIdentifier("chat.select." + message.id)', src)
        self.assertIn('accessibilityIdentifier("chat.select.forward")', src)
        self.assertIn('accessibilityIdentifier("chat.select.copy")', src)
        self.assertIn('accessibilityIdentifier("chat.forward.toast")', src)
        # Existing recalled-message details contract must stay strictly 1.
        self.assertEqual(src.count('allowRecalled: true'), 1)

    def test_ui_test_exercises_real_longpress_ten_limit_and_forward_without_changing_method_count(self):
        ui = (ROOT / 'UITests/ChatAlignmentUITests.swift').read_text()
        self.assertIn('lastText.press(forDuration: 1)', ui)
        self.assertIn('已选 10 / 10', ui)
        self.assertIn('最多只能选择 10 条消息', ui)
        self.assertIn('chat.forward.recipient.syntheticfriend2', ui)
        self.assertIn('已转发 10 条消息给 测试好友二', ui)


if __name__ == '__main__':
    unittest.main()
