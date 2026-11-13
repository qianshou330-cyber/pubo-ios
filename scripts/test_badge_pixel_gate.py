import json
from pathlib import Path
import struct
import tempfile
import unittest
from badge_pixel_gate import BADGE_TEST, PHASES, ENGINE_VERSION, MODEL_SHA256, decode_tsv, verify_badge_phases


def tsv(text='2', confidence='90'):
    return 'level\tconf\ttext\n5\t' + confidence + '\t' + text + '\n'


class BadgePixelGateTests(unittest.TestCase):
    def test_numeric_tokens_are_not_rewritten(self):
        for text in ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '12', '99+'):
            self.assertEqual(decode_tsv(tsv(text))['text'], text)

    def test_rejects_absence_ambiguity_non_numeric_and_low_confidence(self):
        for raw in ('', 'level\tconf\ttext\n', tsv() + '5\t99\t3\n', tsv('O'),
                    tsv('2A'), tsv('2 3'), tsv(' 2'), tsv('.'), tsv(''),
                    tsv('2', '79.99'), tsv('2', 'nan'), tsv('2', '101')):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                decode_tsv(raw)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.attachments = []
        for phase_index, phase in enumerate(PHASES):
            for index, kind in enumerate(('accessibility', 'screen', 'tab', 'glyphs', 'readings')):
                name = phase + '-' + kind
                png = kind in ('screen', 'tab', 'glyphs')
                filename = name + ('.png' if png else '.txt')
                # Header only is sufficient for gate metadata tests. Real OCR
                # regressions separately use actual decodable PNG pixels.
                data = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 16, 16)
                if not png:
                    data = b'redComponents=1\ninkBounds=5,5,10,10\nactual=nil\n'
                (self.root / filename).write_bytes(data)
                self.attachments.append(dict(suggestedHumanReadableName='four-tabs-chat-badge-' + name + '_0.png',
                    exportedFileName=filename, timestamp=100 + phase_index * 100 + index,
                    deviceId='current-device', configurationName='current-configuration'))
        self.write_manifest()

    def tearDown(self):
        self.directory.cleanup()

    def write_manifest(self):
        (self.root / 'manifest.json').write_text(json.dumps([
            dict(testIdentifier=BADGE_TEST, attachments=self.attachments)]))

    def proof(self, reader=lambda path: dict(text='2', confidence=90)):
        self.write_manifest()
        return verify_badge_phases(self.root, expected_device='current-device', commit='a' * 40, started=99, reader=reader, identity=dict(version=ENGINE_VERSION, modelSHA256=MODEL_SHA256))

    def test_all_three_phases_required_and_pixel_reader_only_receives_image(self):
        observed = []
        def reader(path):
            observed.append(path.name)
            return dict(text='2', confidence=90)
        proof = self.proof(reader)
        self.assertEqual(proof['status'], 'PASS')
        self.assertEqual(observed, [phase + '-glyphs.png' for phase in PHASES])
        self.assertEqual(len(proof['phases']), 3)

    def test_wrong_digit_in_each_phase_is_fatal(self):
        for phase in PHASES:
            proof = self.proof(lambda path: dict(text='3' if path.name.startswith(phase) else '2', confidence=99))
            self.assertEqual(proof['status'], 'FAIL')

    def test_missing_phase_fails(self):
        self.attachments = self.attachments[:10]
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_duplicate_attachment_fails(self):
        self.attachments.append(self.attachments[-1].copy())
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_mixed_devices_fail(self):
        self.attachments[-1]['deviceId'] = 'another-device'
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_previous_run_device_fails(self):
        for attachment in self.attachments:
            attachment['deviceId'] = 'previous-run-device'
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_out_of_order_phase_fails(self):
        self.attachments[-1]['timestamp'] = 99
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_missing_or_unsafe_file_fails(self):
        self.attachments[-1]['exportedFileName'] = '../outside.txt'
        self.assertEqual(self.proof()['status'], 'FAIL')

    def test_reader_rejection_never_falls_back_to_accessibility(self):
        def reject(path):
            raise ValueError('No glyph recognized')
        self.assertEqual(self.proof(reject)['status'], 'FAIL')

    def test_unvalidated_engine_fails(self):
        self.assertEqual(verify_badge_phases(self.root, expected_device='current-device', commit='a' * 40, started=99, identity=dict(version='tesseract 9.0.0', modelSHA256=MODEL_SHA256))['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
