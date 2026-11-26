"""Static source contracts for C103 chat non-toolbar Menu compositing boundaries; not a substitute for simulator verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C103ChatMenuBoundaryContracts(unittest.TestCase):
    def test_private_chat_non_toolbar_menus_keep_compositing_boundary(self):
        chat = (ROOT / 'App/Features/ChatView.swift').read_text()
        composer = chat.split('private var inputBar: some View', 1)[1].split('private func bubble(', 1)[0]
        self.assertIn(
            '} label: { Image(systemName: recorder.recording ? "mic.fill" : "paperclip").frame(width: 44, height: 44).foregroundStyle(recorder.recording ? .red : PUBOTheme.secondary) }.compositingGroup().disabled(busy).accessibilityLabel("文件与语音").accessibilityIdentifier("chat.attachments")',
            composer,
        )

        overflow = chat.split('private func messageOverflow(', 1)[1].split('private func messageMenu(', 1)[0]
        self.assertIn(
            '        }\n'
            '        .compositingGroup()\n'
            '        .buttonStyle(.plain)\n'
            '        .accessibilityLabel("消息菜单")\n'
            '        .accessibilityIdentifier("chat.menu." + message.id)',
            overflow,
        )

    def test_room_chat_composer_non_toolbar_menus_keep_compositing_boundary(self):
        room = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        composer = room.split('private var composer: some View', 1)[1].split('private var roomContent: some View', 1)[0]
        self.assertIn(
            'Menu("核对后处理") {\n'
            '                        Button("已发出，清空待发内容") { draft = RoomDraft(); persist() }\n'
            '                        Button("确认未发出，恢复编辑") { draft.pending = false; persist() }\n'
            '                    }.compositingGroup()',
            composer,
        )
        self.assertIn(
            '} label: { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.compositingGroup().disabled(busy || draft.pending).accessibilityLabel("添加群聊附件").accessibilityIdentifier("room.attachments")',
            composer,
        )

    def test_room_chat_message_overflow_menu_keeps_compositing_boundary(self):
        room = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        overflow = room.split('private func messageOverflow(', 1)[1].split('private func messageMenu(', 1)[0]
        self.assertIn(
            '        }\n'
            '        .compositingGroup()\n'
            '        .buttonStyle(.plain)\n'
            '        .accessibilityLabel("群消息菜单")\n'
            '        .accessibilityIdentifier("room.menu." + message.id)',
            overflow,
        )


if __name__ == '__main__':
    unittest.main()
