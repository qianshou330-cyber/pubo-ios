"""Synthetic gate fixtures only: no claim of simulator/UI execution."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zlib

import four_tabs_gate
from verify_navigation_shards import verify, GateError

SHA = 'a' * 40
SHARDS = {'routing': ['testRouting' + str(i) for i in range(6)],
          'interaction': ['testInteraction' + str(i) for i in range(7)]}


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def png_bytes():
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\x00\xff\x00\x00')) + chunk(b'IEND', b''))


class AggregateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'artifacts'
        self.root.mkdir()
        self.source = Path(self.temp.name) / 'tests.swift'
        self.source.write_text('\n'.join('    func ' + name + '() {}' for names in SHARDS.values() for name in names))
        self.patch = patch.object(four_tabs_gate, 'SHARDS', SHARDS, create=True)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.addCleanup(self.temp.cleanup)
        self.receipts = []
        for size in ('small', 'large'):
            for shard, names in SHARDS.items():
                directory = self.root / f'four-tabs-evidence-{size}-{shard}-{SHA}-a2'
                shots = directory / 'screenshots' / 'device'
                shots.mkdir(parents=True)
                udid = str(uuid.uuid4())
                methods = [f'FourTabNavigationUITests/{name}()' for name in names]
                receipt = dict(schemaVersion=1, repository='qianshou330-cyber/pubo-ios',
                               commit=SHA, runId='123', runAttempt='2', size=size, shard=shard,
                               udid=udid, tests='PASS', boot='READY', suite='FourTabNavigationUITests',
                               expectedTests=len(names), selectedMethods=methods, successfulMethodIDs=methods,
                               methodGate='PASS', testExitCode=0, started=100., exportedPNGs=9,
                               pixelGate='PASS' if shard == 'routing' else 'NOT_APPLICABLE')
                manifest = [{'testIdentifier': methods[0], 'attachments': []}]
                for i in range(9):
                    name = f'image-{i}.png'
                    (shots / name).write_bytes(png_bytes())
                    manifest[0]['attachments'].append(dict(exportedFileName=name, deviceId=udid,
                        timestamp=110. + (i // 3) * 10, isAssociatedWithFailure=False))
                self.write(shots / 'manifest.json', manifest)
                proof = dict(status=receipt['pixelGate'], shard=shard, commit=SHA, expectedDevice=udid, started=100.)
                if shard == 'routing':
                    proof.update(commit=SHA, expectedDevice=udid, deviceId=udid, started=100., phases=[])
                    for i, phase in enumerate(('initial', 'notifications', 'returned')):
                        attachments = {}
                        for j, kind in enumerate(('screen', 'tab', 'glyphs', 'readings', 'accessibility')):
                            attachments[kind] = dict(file=f'image-{i*3+j}.png',
                                sha256=hashlib.sha256(png_bytes()).hexdigest(), timestamp=110. + i * 10)
                        proof['phases'].append(dict(phase=phase, ocr={'text': '2'}, attachments=attachments))
                self.write(directory / 'four-tabs-badge-pixels.json', proof)
                self.write(directory / 'four-tabs-summary.json', dict(passedTests=len(methods), failedTests=0, skippedTests=0, expectedFailures=0))
                self.write(directory / 'four-tabs-tests.json', {'testNodes': [dict(nodeType='Test Case', nodeIdentifier=m, result='Passed') for m in methods]})
                path = directory / 'four-tabs-environment.json'
                self.write(path, receipt)
                self.receipts.append(path)

    def write(self, path, obj):
        path.write_text(json.dumps(obj))

    def check(self):
        return verify(self.root, SHA, '123', '2', self.source)

    def mutate(self, path, update):
        data = json.loads(path.read_text())
        update(data)
        self.write(path, data)

    def test_complete_fixture(self):
        self.assertEqual(self.check()['status'], 'PASS')

    def test_receipt_identity_and_status_fail_closed(self):
        path = self.receipts[0]
        original = path.read_text()
        for key, value in [('commit', 'b'*40), ('runId', '124'), ('runAttempt', '1'),
                           ('size', 'large'), ('shard', 'interaction'), ('udid', ''),
                           ('tests', 'FAIL'), ('methodGate', 'FAIL'), ('testExitCode', 1),
                           ('boot', 'NOT_READY'), ('schemaVersion', 2), ('repository', 'other/repo'),
                           ('started', None), ('exportedPNGs', 8), ('pixelGate', 'NOT_APPLICABLE')]:
            with self.subTest(key=key):
                path.write_text(original)
                self.mutate(path, lambda d: d.update({key: value}))
                with self.assertRaises((ValueError, TypeError)):
                    self.check()
        path.write_text(original)

    def test_missing_or_duplicate_methods(self):
        path = self.receipts[0]
        original = path.read_text()
        for key in ('selectedMethods', 'successfulMethodIDs'):
            for mode in ('missing', 'duplicate', 'wrong'):
                with self.subTest(key=key, mode=mode):
                    path.write_text(original)
                    def change(d):
                        d[key] = list(d[key])
                        if mode == 'missing': d[key].pop()
                        elif mode == 'duplicate': d[key].append(d[key][0])
                        else: d[key][0] = 'FourTabNavigationUITests/testOther()'
                    self.mutate(path, change)
                    with self.assertRaises(ValueError): self.check()

    def test_raw_results_cannot_be_overridden_by_pass_receipt(self):
        path = self.receipts[0].parent / 'four-tabs-tests.json'
        self.mutate(path, lambda d: d['testNodes'][0].update(result='Failed'))
        with self.assertRaises(ValueError): self.check()

    def test_summary_skipped_rejected(self):
        path = self.receipts[0].parent / 'four-tabs-summary.json'
        self.mutate(path, lambda d: d.update(skippedTests=1))
        with self.assertRaises(ValueError): self.check()

    def test_source_drift(self):
        self.source.write_text(self.source.read_text() + '\n    func testNew() {}')
        with self.assertRaises(ValueError): self.check()

    def test_wrong_directory_attempt(self):
        path = self.receipts[0].parent
        path.rename(path.with_name(path.name.replace('-a2', '-a1')))
        with self.assertRaises(ValueError): self.check()

    def test_missing_and_extra_artifact(self):
        (self.root / 'extra').mkdir()
        with self.assertRaises(ValueError): self.check()
        (self.root / 'extra').rmdir()
        self.receipts[0].unlink()
        with self.assertRaises(ValueError): self.check()

    def test_duplicate_udid(self):
        first = json.loads(self.receipts[0].read_text())['udid']
        self.mutate(self.receipts[1], lambda d: d.update(udid=first))
        with self.assertRaises(ValueError): self.check()

    def test_badge_negative_cases(self):
        path = self.receipts[0].parent / 'four-tabs-badge-pixels.json'
        original = path.read_text()
        changes = [lambda d: d.update(status='FAIL'), lambda d: d.update(commit='b'*40),
                   lambda d: d.update(started=99), lambda d: d.update(deviceId='wrong'),
                   lambda d: d['phases'].pop(), lambda d: d['phases'].reverse(),
                   lambda d: d['phases'][0]['ocr'].update(text='3'),
                   lambda d: d['phases'][0]['attachments']['screen'].update(sha256='bad'),
                   lambda d: d['phases'][0]['attachments']['screen'].update(timestamp=90)]
        for i, change in enumerate(changes):
            with self.subTest(case=i):
                path.write_text(original)
                self.mutate(path, change)
                with self.assertRaises(ValueError): self.check()

    def test_interaction_must_be_not_applicable(self):
        path = self.receipts[1].parent / 'four-tabs-badge-pixels.json'
        self.write(path, {'status': 'PASS'})
        with self.assertRaises(ValueError): self.check()

    def test_fake_png_and_symlink(self):
        path = next(self.receipts[0].parent.rglob('*.png'))
        path.write_bytes(b'not a png')
        with self.assertRaises(ValueError): self.check()
        path.unlink()
        path.symlink_to(self.source)
        with self.assertRaises(ValueError): self.check()

    def test_manifest_bad_identity_failure_stale_duplicate(self):
        path = next(self.receipts[0].parent.rglob('manifest.json'))
        original = path.read_text()
        for key, value in [('deviceId', 'wrong'), ('timestamp', 99),
                           ('isAssociatedWithFailure', True), ('exportedFileName', '../escape.png')]:
            with self.subTest(key=key):
                path.write_text(original)
                self.mutate(path, lambda d: d[0]['attachments'][0].update({key: value}))
                with self.assertRaises(ValueError): self.check()
        path.write_text(original)
        self.mutate(path, lambda d: d[0]['attachments'].append(d[0]['attachments'][0]))
        with self.assertRaises(ValueError): self.check()

    def test_truncated_png(self):
        path = next(self.receipts[0].parent.rglob('*.png'))
        path.write_bytes(path.read_bytes()[:-12])
        with self.assertRaises(ValueError): self.check()

    def test_malformed_json(self):
        self.receipts[0].write_text('{"tests":"PASS","tests":"PASS"}')
        with self.assertRaises(ValueError): self.check()

    def test_missing_expected_identity(self):
        with self.assertRaises(ValueError): verify(self.root, None, '123', '2', self.source)


if __name__ == '__main__':
    unittest.main()
