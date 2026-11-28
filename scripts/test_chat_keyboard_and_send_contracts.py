"""Static source contracts for C118 comprehensive chat audit fixes (keyboard dismissal, send reliability, IME sync, emoji loading, local preference persistence, voice auto-finish, context-mode send). Not a substitute for Simulator UI tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ChatKeyboardAndSendContracts(unittest.TestCase):
    def test_cursor_text_editor_ime_sync_and_keyboard_control(self):
        source = (ROOT / 'App/Components/CursorTextEditor.swift').read_text()
        for required in [
            'enum KeyboardControl',
            'static func dismiss()',
            'window.endEditing(true)',
            'static func flushActiveTextView(matching identifier: String) -> String?',
            'textView.unmarkText()',
            'UITextView.textDidChangeNotification',
            'var lastAppliedFocused: Bool?',
            'static func dismantleUIView(',
            'if view.isEditable != enabled { view.isEditable = enabled }',
        ]:
            self.assertIn(required, source)

    def test_private_chat_keyboard_dismiss_send_persist_and_audit_fixes(self):
        chat = (ROOT / 'App/Features/ChatView.swift').read_text()
        for required in [
            '.scrollBounceBehavior(.always)',
            'TapGesture().onEnded { dismissKeyboard() }',
            'UIResponder.keyboardWillShowNotification',
            'UIResponder.keyboardWillHideNotification',
            'focused: $editingText',
            '.accessibilityIdentifier("chat.keyboard.dismiss")',
            'Image(systemName: "paperplane.fill")',
            'PUBOTheme.adaptive(0xffffff, 0x0c1210)',
            '.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("发送消息").accessibilityIdentifier("chat.send")',
            'flushComposerText()',
            'persist(reportAuthError: true)',
            'if ownerID == nil { ownerID = account }',
            'Task { await session.ensureEmojisLoaded() }',
            'recorder.onAutoFinish =',
            'NSUserCancelledError',
            'if contextMode {\n                await returnToLatest()',
        ]:
            self.assertIn(required, chat)
        self.assertNotIn('.buttonStyle(.borderless)', chat)

    def test_room_chat_keyboard_dismiss_send_persist_and_context_send(self):
        room = (ROOT / 'App/Features/RoomChatView.swift').read_text()
        for required in [
            '.scrollBounceBehavior(.always)',
            'TapGesture().onEnded { dismissKeyboard() }',
            'UIResponder.keyboardWillShowNotification',
            'UIResponder.keyboardWillHideNotification',
            'focused: $editingText',
            '.accessibilityIdentifier("room.keyboard.dismiss")',
            'Image(systemName: "paperplane.fill")',
            'PUBOTheme.adaptive(0xffffff, 0x0c1210)',
            '.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("发送").accessibilityIdentifier("room.send")',
            'flushComposerText()',
            'persist(reportAuthError: true)',
            'if ownerID == nil { ownerID = account }',
            'Task { await session.ensureEmojisLoaded() }',
            'if contextMode {\n                await returnToLatest()',
            '.puboList().scrollDismissesKeyboard(.interactively)',
        ]:
            self.assertIn(required, room)
        self.assertNotIn('.buttonStyle(.borderless)', room)

    def test_app_session_emoji_recovery_and_valid_sender_name_storage_key(self):
        session = (ROOT / 'App/Infrastructure/AppSession.swift').read_text()
        for required in [
            'private(set) var emojiURLsByName: [String: String] = [:]',
            'func ensureEmojisLoaded() async',
            'func emojiURLString(named name: String) -> String?',
            'if emojis.isEmpty { Task { await refreshEmojis() } }',
            'key: "chat-show-sender-name"',
        ]:
            self.assertIn(required, session)
        # ProtectedStore strictly validates ^[a-zA-Z0-9_-]+$; dot-separated local key silently failed.
        self.assertNotIn('key: "chat.showSenderName"', session)

    def test_voice_recorder_handles_duration_auto_finish_and_cleanup(self):
        voice = (ROOT / 'App/Infrastructure/VoiceRecorder.swift').read_text()
        for required in [
            'AVAudioRecorderDelegate',
            'audioRecorderDidFinishRecording',
            'var onAutoFinish: (@MainActor (Bool) -> Void)?',
            'instance.delegate = proxy',
        ]:
            self.assertIn(required, voice)

    def test_aux_chat_screens_support_keyboard_dismissal(self):
        search = (ROOT / 'App/Features/ChatSearchView.swift').read_text()
        self.assertIn('.scrollDismissesKeyboard(.interactively)', search)
        self.assertIn('KeyboardControl.dismiss(); select(row.id)', search)
        self.assertIn('KeyboardControl.dismiss(); selectMessage(row)', search)

        actions = (ROOT / 'App/Features/ChatMessageActions.swift').read_text()
        self.assertIn('.puboForm().scrollDismissesKeyboard(.interactively)', actions)
        self.assertIn('KeyboardControl.dismiss()', actions)
        self.assertIn('.accessibilityLabel("收起键盘")', actions)

        forward = (ROOT / 'App/Features/ChatForwardSheet.swift').read_text()
        self.assertIn('.scrollDismissesKeyboard(.interactively)', forward)
        self.assertIn('KeyboardControl.dismiss()', forward)

        common = (ROOT / 'App/Components/CommonViews.swift').read_text()
        self.assertIn('await session.ensureEmojisLoaded()', common)
        self.assertIn('session.emojiURLString(named: name)', common)

    def test_composer_ui_tests_cover_dismiss_and_send_with_keyboard_up_keeping_exact_method_count(self):
        ui = (ROOT / 'UITests/ChatComposerParityUITests.swift').read_text()
        self.assertEqual(ui.count('    func test'), 8)
        for required in [
            'prefix + ".keyboard.dismiss"',
            'dismissButton.tap()',
            'Keyboard must dismiss via explicit dismiss button',
            'Keyboard must dismiss when tapping blank timeline area',
            'Message must send and appear while keyboard is open',
            'chat-composer-sent-',
        ]:
            self.assertIn(required, ui)


if __name__ == '__main__':
    unittest.main()
