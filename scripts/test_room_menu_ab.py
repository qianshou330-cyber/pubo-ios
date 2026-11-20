import json
from pathlib import Path
import struct
import tempfile
import unittest
import uuid
import zlib

from ui_selection import ROOM_MENU_AB_SHARD, selection
from verify_room_menu_ab import IDS, LABEL, classify, validate_arm


HERE = Path(__file__).resolve().parents[1]
SHA = 'f901c5a871d423a43869f560d69b469ae82fe8b8'
UDID = 'E10BEDAF-A83A-4CAB-9B27-206156D4F407'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-1'
DEVICE_TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17'


def put(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False))


def arm_receipt(arm, query, post=None):
    return {
        'schema': 1, 'arm': arm, 'theme': 'light', 'fixture': 'socialroom/room0002',
        'gesture': 'ownText.press' if arm == 'text' else 'bubble-padding.press',
        'pressCount': 1, 'pressSeconds': 1, 'deleteQueryTimeoutSeconds': 5,
        'deleteQueryFound': query, 'preLabels': [], 'postLabels': [LABEL] if
        (query if post is None else post) else [],
        'window': [0, 0, 402, 874], 'text': [223, 367, 150, 16],
        'overflow': [163, 347, 44, 44], 'timeline': [0, 163, 402, 711],
        'composerInput': [16, 740, 370, 44],
        'intendedPoint': [298, 375] if arm == 'text' else [217, 375],
    }


def png_fixture(w=1206, h=2622):
    def chunk(k, b):
        return struct.pack('>I', len(b)) + k + b + struct.pack('>I', zlib.crc32(k+b))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes((w + 1)*h))) + chunk(b'IEND', b''))


class RoomMenuABTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.context = self.root / 'room-menu-ab'
        self.context.mkdir()
        self.shots = self.root / 'screenshots' / '0'
        self.shots.mkdir(parents=True)
        self.result = self.root / 'ui-0.xcresult'
        self.result.mkdir()
        (self.result / 'Info.plist').touch()
        put(self.context / 'context.json', dict(repository='qianshou330-cyber/pubo-ios',
            ref='refs/heads/ui-four-tabs-148-20261112', commit=SHA, runId='123', runAttempt='1'))
        (self.context / 'c82-app-base.txt').write_text(SHA + '\n')
        self.env = dict(commit=SHA, size='small', runtime=RUNTIME, device='iPhone 17',
            deviceTypeIdentifier=DEVICE_TYPE, appearance='light', boot='READY', selection=ROOM_MENU_AB_SHARD,
            expectedTests=2, tests='PASS', udid=UDID, hostArchitecture='x86_64',
            xcode='Xcode 26.0.1\nBuild version 17A400')
        put(self.root / 'test-environment.json', [self.env])
        counts = dict(passedTests=2, failedTests=0, skippedTests=0, expectedFailures=0)
        config = dict(counts, device=dict(deviceId=UDID, modelName='iPhone 17', osVersion='26.1',
                                         platform='iOS Simulator', architecture='x86_64'))
        self.summary = dict(counts, devicesAndConfigurations=[config], result='Passed',
                            totalTestCount=2, startTime=100, finishTime=200, testFailures=[])
        put(self.root / 'ui-0-summary.json', self.summary)
        self.cases = [dict(nodeType='Test Case', nodeIdentifier=x, result='Passed') for x in IDS]
        self.tree = dict(testNodes=[dict(nodeType='Test Bundle', name='PUBOUITests', children=[
            dict(nodeType='Test Suite', name='RoomMenuABDiagnosticUITests', children=self.cases)])])
        put(self.context / 'tests.json', self.tree)
        self.manifest = []
        self.receipts = {}
        for n, (ident, arm) in enumerate(IDS.items()):
            group = []
            for i, (label, ext) in enumerate([('pre-ax','.txt'), ('pre-screen','.png'),
                                             ('post-ax','.txt'), ('post-screen','.png'), ('receipt','.txt')]):
                filename = str(uuid.uuid4())+ext
                path = self.shots / filename
                if ext == '.png':
                    path.write_bytes(png_fixture())
                elif label == 'receipt':
                    self.receipts[arm] = path
                    put(path, arm_receipt(arm, arm == 'padding'))
                else:
                    path.write_text('Fixture room.bubble.room0002 or pre/post snapshot')
                group.append(dict(suggestedHumanReadableName=f'room-menu-ab-{arm}-{label}_0_{uuid.uuid4()}{ext}',
                                  exportedFileName=filename, deviceId=UDID, isAssociatedWithFailure=False,
                                  timestamp=110+(n*20)+i))
            self.manifest.append(dict(testIdentifier=ident, attachments=group))
        put(self.shots / 'manifest.json', self.manifest)

    def report(self):
        return classify(self.root, SHA, '123', '1')

    def test_complete_a_b_preserves_distinction(self):
        report = self.report()
        self.assertEqual(report['status'], 'DELETE_AX_PADDING_ONLY')
        self.assertEqual(report['arms']['text']['deleteAX'], 'NOT_OBSERVED')
        self.assertFalse(report['videoAvailable'])
        self.assertEqual(report['scope'], 'EXPERIMENTAL_AX_OBSERVATIONS_ONLY')

    def test_both_variants_no_menu_valid_observation_not_gate_pass(self):
        put(self.receipts['padding'], arm_receipt('padding', False))
        self.assertEqual(self.report()['status'], 'DELETE_AX_NEITHER_OBSERVED')

    def test_query_and_snapshot_disagreement_is_explicit(self):
        put(self.receipts['text'], arm_receipt('text', True, False))
        self.assertEqual(self.report()['status'], 'DELETE_AX_INCONSISTENT')

    def test_wrong_or_duplicate_method_refused(self):
        self.cases[1]['nodeIdentifier'] = self.cases[0]['nodeIdentifier']
        put(self.context / 'tests.json', self.tree)
        with self.assertRaisesRegex(ValueError, 'Missing or duplicate'):
            self.report()

    def test_valid_fixture_blocked_is_distinct_from_ax_classifier(self):
        self.summary['testFailures'] = [dict(testIdentifierString=next(iter(IDS)),
            failureText='XCTFail failed - ROOM_MENU_AB_PRECONDITION: room fixture')]
        self.summary['result'] = 'Failed'
        self.env['tests'] = 'FAIL'
        put(self.root / 'test-environment.json', [self.env])
        put(self.root / 'ui-0-summary.json', self.summary)
        self.assertEqual(self.report()['status'], 'FIXTURE_OR_PRECONDITION_BLOCKED')

    def test_zero_native_tests_never_pass(self):
        self.summary['totalTestCount'] = 0
        put(self.root / 'ui-0-summary.json', self.summary)
        with self.assertRaisesRegex(ValueError, 'two native methods'):
            self.report()

    def test_fail_closed_wrong_device_or_png(self):
        self.summary['devicesAndConfigurations'][0]['device']['modelName'] = 'iPhone 17 Pro Max'
        put(self.root / 'ui-0-summary.json', self.summary)
        with self.assertRaisesRegex(ValueError, 'raw native device'):
            self.report()
        self.summary['devicesAndConfigurations'][0]['device']['modelName'] = 'iPhone 17'
        put(self.root / 'ui-0-summary.json', self.summary)
        (self.shots / self.manifest[0]['attachments'][1]['exportedFileName']).write_bytes(png_fixture(1320, 2868))
        with self.assertRaisesRegex(ValueError, 'screenshot raster'):
            self.report()

    def test_fail_closed_invalid_geometry_and_relabelled_sibling(self):
        receipt = arm_receipt('padding', True)
        receipt['intendedPoint'] = [185, 369]  # sibling overflow control, not bubble
        with self.assertRaisesRegex(ValueError, 'safe padding lane'):
            validate_arm(receipt, 'padding')
        receipt = arm_receipt('padding', True)
        receipt['pressCount'] = True
        with self.assertRaisesRegex(ValueError, 'wrong fixture|Wrong fixture'):
            validate_arm(receipt, 'padding')

    def test_fail_closed_wrong_order_or_missing_c82_pin(self):
        self.manifest[1]['attachments'][0]['timestamp'] = 109
        put(self.shots / 'manifest.json', self.manifest)
        with self.assertRaisesRegex(ValueError, 'arm order'):
            self.report()
        (self.context / 'c82-app-base.txt').write_text('wrong\n')
        with self.assertRaisesRegex(ValueError, 'C82 App'):
            self.report()

    def test_only_new_opt_in_selection_and_protocol(self):
        self.assertEqual(selection(ROOM_MENU_AB_SHARD), (2, ['-only-testing:PUBOUITests/' + prefix
                                                               for prefix in (i[:-2] for i in IDS)]))
        self.assertEqual(selection('chat-alignment-actions')[0], 5)
        self.assertNotIn('RoomMenuABDiagnosticUITests', ' '.join(selection('chat-alignment-actions')[1]))
        swift = (HERE / 'UITests/RoomMenuABDiagnosticUITests.swift').read_text()
        self.assertTrue(swift.startswith('#if DEBUG && PUBO_ROOM_MENU_AB_DIAGNOSTIC\n'))
        self.assertIn('ownText.press(forDuration: 1)', swift)
        self.assertIn('let found = delete.waitForExistence(timeout: 5)', swift)
        self.assertNotIn('delete.tap()', swift)
        self.assertNotIn('overflow.tap()', swift)
        workflow = (HERE / '.github/workflows/four-tabs.yml').read_text().split('  diagnostic-room-menu-ab:', 1)[-1]
        self.assertIn("'[room-menu-ab-probe]'", workflow)
        self.assertIn("'refs/heads/ui-four-tabs-148-20261112'", workflow)
        self.assertIn('PUBO_SIM_SIZE: small', workflow)
        self.assertIn('PUBO_PREBUILT_TESTS:', workflow)
        self.assertIn('$(inherited) DEBUG PUBO_ROOM_MENU_AB_DIAGNOSTIC', workflow)
        self.assertNotIn('needs:', workflow)
        self.assertNotIn('workflow_dispatch:', workflow)


if __name__ == '__main__':
    unittest.main()
