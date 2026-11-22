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
        tree = {'testNodes': [{'nodeType': 'Test Suite', 'name': MESSAGES_REDESIGN_SUITE, 'children': cases}]}
        self.assertEqual(len(verify_methods(tree)), 4)
        for replacement in (cases[:-1], cases + cases[:1],
                            [dict(cases[0], result='Skipped')] + cases[1:],
                            [dict(cases[0], nodeIdentifier='Other/method()')] + cases[1:]):
            with self.assertRaises(ValueError):
                verify_methods({'testNodes': replacement})
        tree['testNodes'][0]['name'] = 'WrongSuite'
        with self.assertRaises(ValueError):
            verify_methods(tree)

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
