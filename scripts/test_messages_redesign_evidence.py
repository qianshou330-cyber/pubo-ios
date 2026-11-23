"""Offline policy controls for synthetic proof; no Simulator claim."""
import copy
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from ui_selection import selection, MESSAGES_REDESIGN_SHARD, MESSAGES_REDESIGN_SUITE
from verify_messages_redesign_evidence import CAPTURES, method_id, verify_captures, verify_methods

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


if __name__ == '__main__':
    unittest.main()
