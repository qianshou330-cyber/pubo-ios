"""Offline policy controls for synthetic proof; no Simulator claim."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from ui_selection import selection, MESSAGES_REDESIGN_SHARD, MESSAGES_REDESIGN_SUITE
from verify_messages_redesign_evidence import CAPTURES, method_id, verify_captures, verify_method_bytes, verify_methods

UDID = '12ABCDEF-1234-AAAA-BBBB-1234567890AB'


def png(width, height):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes((width + 1) * height))) + chunk(b'IEND', b''))


class MessagesRedesignEvidence(unittest.TestCase):
    def test_exact_separate_four_method_selection(self):
        count, selectors = selection(MESSAGES_REDESIGN_SHARD)
        self.assertEqual(count, 4)
        self.assertEqual(selectors, ['-only-testing:PUBOUITests/' + method_id(m)[:-2] for m in CAPTURES])

    def test_method_gate_rejects_missing_wrong_failed_and_duplicate(self):
        cases = [{'nodeType': 'Test Case', 'nodeIdentifier': method_id(m), 'result': 'Passed'} for m in CAPTURES]
        suite = dict(nodeType='Test Suite', name=MESSAGES_REDESIGN_SUITE, children=cases)

        def tree(bundle_kind='UI test bundle', bundle_name='PUBOUITests', test_suite=suite):
            bundle = dict(nodeType=bundle_kind, name=bundle_name, children=[test_suite])
            return {'testNodes': [dict(nodeType='Test Plan', name='PUBO', children=[bundle])]}

        for kind in ('UI test bundle', 'Test Bundle'):
            with self.subTest(bundle_kind=kind):
                self.assertEqual(len(verify_methods(tree(bundle_kind=kind))), 4)
                with self.assertRaisesRegex(ValueError, 'Wrong test bundle'):
                    verify_methods(tree(bundle_kind=kind, bundle_name='WrongBundle'))
        for replacement in (cases[:-1], cases + cases[:1],
                            [dict(cases[0], result='Skipped')] + cases[1:],
                            [dict(cases[0], nodeIdentifier='Other/method()')] + cases[1:]):
            with self.assertRaises(ValueError):
                verify_methods(tree(test_suite=dict(suite, children=replacement)))
        for wrong in ({'testNodes': [suite]}, tree(bundle_kind='Unknown bundle type'),
                      tree(test_suite=dict(suite, name='WrongSuite'))):
            with self.assertRaises(ValueError):
                verify_methods(wrong)

    def test_rejection_receipt_does_not_make_warning_or_retry_children_pass(self):
        cases = [dict(nodeType='Test Case', nodeIdentifier=method_id(m), result='Passed') for m in CAPTURES]
        suite = dict(nodeType='Test Suite', name=MESSAGES_REDESIGN_SUITE, children=cases)
        bundle = dict(nodeType='UI test bundle', name='PUBOUITests', children=[suite])
        tree = dict(testNodes=[dict(nodeType='Test Plan', children=[bundle])])
        commit = 'b' * 40
        with tempfile.TemporaryDirectory() as directory:
            diagnostic = Path(directory) / 'method-tree-rejection.json'
            raw = json.dumps(tree).encode()
            self.assertEqual(len(verify_method_bytes(raw, diagnostic, commit, '12', '1', 'small')), 4)
            self.assertFalse(diagnostic.exists())
            for kind, descendants, tag in (('Runtime Warning', [], 'NONE'),
                                            ('Test Case Run', [cases[1]], 'PRESENT')):
                with self.subTest(kind=kind):
                    cases[0]['children'] = [dict(nodeType=kind, children=descendants, name='/private/warning')]
                    raw = json.dumps(tree).encode()
                    with self.assertRaisesRegex(ValueError, 'Nonpassing, retried, or wrong-suite test'):
                        verify_method_bytes(raw, diagnostic, commit, '12', '1', 'small')
                    receipt = json.loads(diagnostic.read_text())
                    self.assertEqual(receipt['status'], 'METHOD_TREE_REJECTED')
                    self.assertEqual((receipt['commit'], receipt['run'], receipt['attempt'], receipt['profile']),
                                     (commit, '12', '1', 'small'))
                    self.assertEqual(receipt['inputSHA256'], hashlib.sha256(raw).hexdigest())
                    self.assertEqual(receipt['inputBytes'], len(raw))
                    self.assertEqual(receipt['case']['childSample'], [dict(kind=kind, descendants=tag)])
                    self.assertEqual(receipt['case']['children'], 'PRESENT')
                    self.assertEqual(receipt['case']['childCount'], 1)
                    self.assertEqual(receipt['case']['result'], 'Passed')
                    self.assertNotIn('/private/warning', diagnostic.read_text())

    def test_rejection_receipt_bounds_and_redacts_unexpected_tree_values(self):
        opaque = '/private/arbitrary annotation\n' * 128
        case = dict(nodeType='Test Case', nodeIdentifier=opaque, result=opaque,
                    children=[dict(nodeType=opaque, children=[], output=opaque)] * 64)
        suite = dict(nodeType='Test Suite', name=opaque, children=[case])
        tree = dict(testNodes=[dict(nodeType=opaque, name=opaque, children=[suite])])
        with tempfile.TemporaryDirectory() as directory:
            diagnostic = Path(directory) / 'method-tree-rejection.json'
            with self.assertRaisesRegex(ValueError, 'Nonpassing, retried, or wrong-suite test'):
                verify_method_bytes(json.dumps(tree).encode(), diagnostic, opaque, opaque, opaque, opaque)
            text = diagnostic.read_text()
            self.assertLess(len(text), 1600)
            self.assertNotIn('/private/', text)
            receipt = json.loads(text)
            self.assertTrue(all(receipt[k] is None for k in ('commit', 'run', 'attempt', 'profile')))
            case = receipt['case']
            self.assertEqual([case[k] for k in ('method', 'suite', 'bundle', 'result')],
                             ['OTHER', 'OTHER', 'MISSING', 'OTHER'])
            self.assertEqual(case['childCount'], 64)
            self.assertTrue(case['childSampleTruncated'])
            self.assertEqual(case['childSample'], [dict(kind='OTHER', descendants='NONE')] * 8)

    def test_plus_canonical_names_match_xcresult_export_shape(self):
        # Capture label precedes _0_UUID; the old dotted identifier was treated as the suffix.
        example_id = '12000000-2000-4000-8000-900000000000'
        labels = ('plus-scan', 'sheet-scan', 'plus-add-username', 'sheet-add-username')
        with tempfile.TemporaryDirectory() as directory:
            shots = Path(directory)
            rows = [dict(testIdentifier='MessagesRedesignUITests/testPlusKeepsBothFriendSheetsAndRealClose()',
                         attachments=[])]
            for idx, label in enumerate(labels):
                file = f'20000000-2000-4000-8000-90000000000{idx}.png'
                (shots / file).write_bytes(png(1320, 2868))
                rows[0]['attachments'].append(dict(suggestedHumanReadableName=f'messages-redesign-{label}_0_{example_id}.png',
                    exportedFileName=file, deviceId=UDID, isAssociatedWithFailure=False))
            self.assertEqual(set(verify_captures(rows, shots, 'large', UDID, partial=True)), set(labels))
            for attachment, label in zip(rows[0]['attachments'],
                    ('plus-messages.scan', 'sheet-messages.scan', 'plus-messages.addUsername', 'sheet-messages.addUsername')):
                head, suffix = label.split('.')
                attachment['suggestedHumanReadableName'] = f'messages-redesign-{head}_0_{example_id}.{suffix}'
            self.assertEqual(verify_captures(rows, shots, 'large', UDID, partial=True), {})

    def test_each_profile_requires_original_named_captures(self):
        for size, dimensions in (('small', (1206, 2622)), ('large', (1320, 2868))):
            with tempfile.TemporaryDirectory() as directory:
                shots = Path(directory)
                rows = []
                for method, captures in CAPTURES.items():
                    attachments = []
                    for c in captures:
                        file = c + '.png'
                        (shots / file).write_bytes(png(*dimensions))
                        attachments.append(dict(suggestedHumanReadableName='messages-redesign-' + c + '_attempt.png',
                                                deviceId=UDID, isAssociatedWithFailure=False, exportedFileName=file))
                    rows.append(dict(testIdentifier=method_id(method), attachments=attachments))
                self.assertEqual(len(verify_captures(rows, shots, size, UDID)), 13)
                for key, value in (('deviceId', 'wrong'), ('isAssociatedWithFailure', True),
                                   ('exportedFileName', '../bad.png')):
                    wrong = copy.deepcopy(rows)
                    wrong[0]['attachments'][0][key] = value
                    with self.assertRaises(ValueError):
                        verify_captures(wrong, shots, size, UDID)
                with self.assertRaises(ValueError):
                    verify_captures(rows[1:], shots, size, UDID)
                self.assertEqual(len(verify_captures(rows[1:], shots, size, UDID, partial=True)), 9)
                first = rows[0]['attachments'][0]['exportedFileName']
                (shots / first).write_bytes(png(1, 1))
                with self.assertRaises(ValueError):
                    verify_captures(rows, shots, size, UDID)

    def test_home_header_plus_menu_keeps_compositing_boundary_and_identifiers(self):
        source = (Path(__file__).resolve().parents[1] / 'App/Features/ChatListView.swift').read_text(encoding='utf-8')
        header_start = source.index('private var homeHeader: some View')
        search_start = source.index('NavigationLink(value: MessagesHomePage.search)', header_start)
        menu_start = source.index('Menu {', header_start, search_start)
        menu_block = source[menu_start:search_start]
        self.assertIn('.accessibilityIdentifier("messages.scan")', menu_block)
        self.assertIn('.accessibilityIdentifier("messages.addUsername")', menu_block)
        self.assertIn('.accessibilityLabel("添加好友")', menu_block)
        self.assertIn('.accessibilityIdentifier("messages.add")', menu_block)
        compositing = menu_block.index('.compositingGroup()')
        plain_style = menu_block.index('.buttonStyle(.plain)')
        add_id = menu_block.index('.accessibilityIdentifier("messages.add")')
        self.assertLess(compositing, plain_style)
        self.assertLess(plain_style, add_id)


if __name__ == '__main__':
    unittest.main()
