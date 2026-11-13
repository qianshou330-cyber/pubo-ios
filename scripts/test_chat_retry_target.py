"""Static source contracts only; simulator hit-testing still needs real verification."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'App/Components/ChatMessageContent.swift'


class ChatRetryTargetTests(unittest.TestCase):
    def test_retry_label_owns_minimum_hit_target(self):
        source = SOURCE.read_text()
        self.assertRegex(source, re.compile(
            r'\} label: \{\s*Text\("重试链接预览"\)\.font\(\.caption\)\s*'
            r'\.frame\(minWidth: 44, minHeight: 44\)\s*'
            r'\.contentShape\(Rectangle\(\)\)\s*'
            r'\}\.buttonStyle\(\.plain\)\s*'
            r'\.accessibilityIdentifier\(identifier \+ "\.retry"\)', re.S))

    def test_card_outline_is_not_a_touch_target(self):
        source = SOURCE.read_text()
        self.assertIn('.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PUBOTheme.divider).allowsHitTesting(false))', source)

    def test_attempt_diagnostics_are_synthetic_only_and_nonpersonal(self):
        source = SOURCE.read_text()
        blocks = re.findall(r'#if DEBUG(.*?)#endif', source, re.S)
        logs = [line.strip() for block in blocks for line in block.splitlines() if '[ChatPreview]' in line]
        self.assertEqual(len(logs), 3)
        for line in logs:
            self.assertTrue(line.startswith('if session.testMode { print('))
            self.assertEqual(re.findall(r'\\\((.*?)\)', line), ['retry'])
        self.assertIn('retry action accepted', '\n'.join(logs))
        self.assertIn('fetch started', '\n'.join(logs))
        self.assertIn('metadata published', '\n'.join(logs))


if __name__ == '__main__':
    unittest.main()
