import pathlib
import re
import unittest
from ui_selection import ALIGNMENT_PARTS, SHARDS, complete, selection


class ChatAlignmentPartsTests(unittest.TestCase):
    def test_parts_cover_real_methods_exactly_once(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        source = (root / 'UITests/ChatAlignmentUITests.swift').read_text()
        actual = re.findall(r'func (test\w+)\(', source)
        selected = [name for methods in ALIGNMENT_PARTS.values() for name in methods]
        self.assertEqual(len(actual), 10)
        self.assertEqual(len(selected), len(set(selected)))
        self.assertEqual(set(selected), set(actual))
        self.assertEqual(sum(len(x) for x in ALIGNMENT_PARTS.values()), SHARDS['chat-alignment'][0])
        for part, methods in ALIGNMENT_PARTS.items():
            count, selectors = selection(part)
            self.assertEqual(count, 5)
            self.assertEqual(selectors, ['-only-testing:PUBOUITests/ChatAlignmentUITests/' + x for x in methods])

    def test_failure_skip_missing_and_expected_failure_stay_failures(self):
        good = dict(passedTests=5, failedTests=0, skippedTests=0, expectedFailures=0)
        self.assertTrue(complete(good, 5))
        for key, value in [('passedTests', 4), ('failedTests', 1), ('skippedTests', 1), ('expectedFailures', 1)]:
            self.assertFalse(complete(dict(good, **{key: value}), 5))

    def test_all_matrix_parts_remain_required_by_package(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        workflow = (root / '.github/workflows/four-tabs.yml').read_text()
        block = workflow.split('  chat-alignment:\n', 1)[1].split('  chat-presentation:\n', 1)[0]
        self.assertIn('size: [small, large]', block)
        self.assertIn('part: [layout, actions]', block)
        self.assertIn('fail-fast: false', block)
        self.assertNotIn('continue-on-error', block)
        self.assertIn("PUBO_UI_SHARD: 'chat-alignment-${{ matrix.part }}'", block)
        self.assertIn('name: four-tabs-chat-alignment-${{ matrix.size }}-${{ matrix.part }}-${{ github.sha }}', block)
        self.assertIn('chat-alignment', workflow.split('  package:\n', 1)[1].split('runs-on:', 1)[0])


if __name__ == '__main__':
    unittest.main()
