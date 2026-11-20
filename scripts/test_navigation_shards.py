"""Fabricated JSON and subprocess contracts, NOT a Simulator validation."""
import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from iphone_qa_matrix import MATRIX, RUNTIME
from four_tabs_gate import (SHARDS, SUITE, complete, declared_tests, expected_method_ids,
                            selected_methods, selectors, successful_method_ids, validate_scope)

ROOT = Path(__file__).resolve().parents[1]


def tree_for(shard):
    return {'testNodes': [{'nodeType': 'Test Plan', 'children': [
        {'nodeType': 'Test Bundle', 'name': 'PUBOUITests', 'children': [
            {'nodeType': 'Test Suite', 'name': SUITE, 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': name, 'result': 'Passed'}
                for name in expected_method_ids(shard)]}]}]}]}


def cases(tree):
    return tree['testNodes'][0]['children'][0]['children'][0]['children']


def summary_for(shard):
    return dict(passedTests=len(selected_methods(shard)), failedTests=0, skippedTests=0, expectedFailures=0)


class NavigationManifestTests(unittest.TestCase):
    def test_exact_disjoint_union(self):
        validate_scope(declared_tests(ROOT / 'UITests/FourTabNavigationUITests.swift'))
        self.assertEqual([len(v) for v in SHARDS.values()], [6, 7])
        self.assertEqual(len(set(selected_methods())), 13)

    def test_invalid_declarations_and_shards(self):
        names = list(selected_methods())
        for bad in (names[:-1], names + [names[0]], names[:-1] + ['testSubstitute']):
            with self.assertRaises(ValueError): validate_scope(bad)
        for bad in ('', 'optional', 'Routing'):
            with self.assertRaises(ValueError): selectors(bad)

    def test_exact_method_selectors_and_default_all(self):
        for shard in ('all', *SHARDS):
            self.assertEqual(len(selectors(shard)), len(expected_method_ids(shard)))
            self.assertTrue(all(x.startswith('-only-testing:PUBOUITests/' + SUITE + '/test') for x in selectors(shard)))
        self.assertEqual(len(selectors()), 13)

    def test_static_capture_floor_is_feasible_without_lowering_eight(self):
        source = (ROOT / 'UITests/FourTabNavigationUITests.swift').read_text()
        # Count only direct capture calls, ignoring helper-generated attachments.
        # Each listed method is selected whole; loop calls count only once here.
        for shard, methods in SHARDS.items():
            direct = 0
            for method in methods:
                body = source.split('    func ' + method + '(', 1)[1].split('\n    func ', 1)[0]
                direct += body.count('capture(app,') + body.count('capture(cold,')
            self.assertGreaterEqual(direct, 8, shard)
        roots = source.split('    func testFourRootsAndExclusiveComposerInBothThemes(', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('for dark in [false, true]', roots)

    def test_nested_tree_pass_and_summary(self):
        for shard in ('all', *SHARDS):
            self.assertEqual(successful_method_ids(tree_for(shard), shard), sorted(expected_method_ids(shard)))
            self.assertTrue(complete(summary_for(shard), len(selected_methods(shard))))

    def test_missing_duplicate_extra_or_wrong_identity_fail(self):
        for mode in ('missing', 'duplicate', 'extra', 'wrong_suite', 'method_only', 'wrong_bundle'):
            tree = tree_for('routing')
            nodes = cases(tree)
            if mode == 'missing': nodes.pop()
            elif mode == 'duplicate': nodes[-1] = copy.deepcopy(nodes[0])
            elif mode == 'extra': nodes.append(copy.deepcopy(nodes[0]))
            elif mode == 'wrong_suite': nodes[0]['nodeIdentifier'] = nodes[0]['nodeIdentifier'].replace(SUITE, 'OtherSuite')
            elif mode == 'method_only': nodes[0]['nodeIdentifier'] = nodes[0]['nodeIdentifier'].split('/')[1]
            else: tree['testNodes'][0]['children'][0]['name'] = 'OtherUITests'
            with self.subTest(mode=mode), self.assertRaises(ValueError): successful_method_ids(tree, 'routing')

    def test_unpassed_unknown_or_malformed_fail(self):
        for result in ('Failed', 'Skipped', 'Expected Failure', 'Unknown', None):
            tree = tree_for('routing'); cases(tree)[0]['result'] = result
            with self.assertRaises(ValueError): successful_method_ids(tree, 'routing')
        for tree in ({}, {'testNodes': None}, {'testNodes': [None]}, {'testNodes': [{'children': 'bad'}]}):
            with self.assertRaises(ValueError): successful_method_ids(tree, 'routing')

    def test_contradictory_suite_and_nested_duplicate_fail(self):
        tree = tree_for('routing')
        tree['testNodes'][0]['children'][0]['children'][0]['name'] = 'OtherSuite'
        with self.assertRaises(ValueError): successful_method_ids(tree, 'routing')
        tree = tree_for('routing'); cases(tree)[0]['children'] = [copy.deepcopy(cases(tree)[1])]
        with self.assertRaises(ValueError): successful_method_ids(tree, 'routing')

    def test_pass_parent_cannot_hide_failed_or_repeated_execution(self):
        for kind in ('Test Case Run', 'Repetition', 'Failure Message', 'Unknown'):
            tree = tree_for('routing')
            cases(tree)[0]['children'] = [{'nodeType': kind, 'result': 'Failed'}]
            with self.assertRaises(ValueError): successful_method_ids(tree, 'routing')

    def test_exact_summary_including_types(self):
        good = summary_for('routing')
        for field in good:
            for value in (None, True, str(good[field]), good[field] + 1):
                bad = dict(good, **{field: value})
                self.assertFalse(complete(bad, 6))
        self.assertFalse(complete({}, 6))


class RunnerContractTests(unittest.TestCase):
    def run_fake(self, shard='routing', fault=None):
        real_source = (ROOT / 'UITests/FourTabNavigationUITests.swift').read_text()
        old_cwd = Path.cwd()
        commands = []
        waits = []
        proof_calls = []
        device_id = 'aabbccdd-1111-2222-3333-aabbccddeeff'
        profile = MATRIX['small']
        created = []
        class FakeProcess:
            pid = 12345
            def __init__(self):
                self.done = False
            def wait(self, timeout):
                waits.append(timeout)
                if fault == 'timeout' and timeout == 2700:
                    raise subprocess.TimeoutExpired('xcodebuild', timeout)
                self.done = True
                return 65 if fault == 'nonzero' else 0
            def poll(self): return 0 if self.done else None
        def output(command, **kwargs):
            if command[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                rows = [dict(name=profile['model'], deviceTypeIdentifier=profile['deviceTypeIdentifier'],
                             udid='template-udid', isAvailable=True)]
                rows += created
                return json.dumps({'devices': {RUNTIME: rows}}).encode()
            if command[:3] == ['xcrun', 'simctl', 'create']:
                self.assertEqual(command[3:], ['PUBO four tabs small', profile['deviceTypeIdentifier'], RUNTIME])
                created.append(dict(name=command[3], deviceTypeIdentifier=command[4],
                                    udid=device_id, isAvailable=True))
                return device_id
            if command[0] == 'git': return 'a' * 40
            return 'Xcode 26.0.1'
        def popen(command, **kwargs):
            commands.append(command)
            Path('build/four-tabs.xcresult').mkdir()
            return FakeProcess()
        def run(command, **kwargs):
            commands.append(command)
            value = ''
            if command[:4] == ['xcrun', 'xcresulttool', 'get', 'test-results']:
                if fault == 'reader_error': raise subprocess.CalledProcessError(1, command)
                if command[4] == 'summary':
                    value = summary_for(shard)
                    value['devicesAndConfigurations'] = [dict(value, device={
                        'deviceId': device_id, 'modelName': profile['model'], 'platform': 'iOS Simulator',
                        'osVersion': MATRIX['osVersion']})]
                    if fault == 'summary': value['skippedTests'] = 1
                    if fault == 'wrong-device': value['devicesAndConfigurations'][0]['device']['modelName'] = 'iPhone SE'
                else:
                    value = tree_for(shard)
                    if fault == 'identity': cases(value)[0]['nodeIdentifier'] = 'OtherSuite/testSubstitute()'
                value = json.dumps(value)
            elif command[:3] == ['xcrun', 'xcresulttool', 'export']:
                shots = Path(command[-1]); shots.mkdir(parents=True, exist_ok=True)
                for i in range(7 if fault == 'screenshots' else 8): (shots / (str(i) + '.png')).write_bytes(b'fake')
            return subprocess.CompletedProcess(command, 0, value, '')
        def proof(*args, **kwargs):
            proof_calls.append(kwargs)
            return {'status': 'FAIL' if fault == 'badge' else 'PASS', 'phases': []}
        with tempfile.TemporaryDirectory() as temp:
            os.chdir(temp)
            try:
                Path('UITests').mkdir(); Path('UITests/FourTabNavigationUITests.swift').write_text(real_source)
                env = dict(PUBO_SIM_SIZE='small', GITHUB_REPOSITORY='qianshou330-cyber/pubo-ios',
                           GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='2')
                if shard != 'all': env['PUBO_NAV_SHARD'] = shard
                with patch.dict(os.environ, env, clear=True), patch('subprocess.check_output', side_effect=output), \
                     patch('subprocess.Popen', side_effect=popen), patch('subprocess.run', side_effect=run), \
                     patch('simulator_boot.boot'), patch('badge_pixel_gate.verify_badge_phases', side_effect=proof), \
                     patch('os.killpg'), self.assertRaises(SystemExit) as exited:
                    runpy.run_path(str(ROOT / 'scripts/four-tabs-tests.py'), run_name='__main__')
                record = json.loads(Path('build/four-tabs-environment.json').read_text())
                badge = json.loads(Path('build/four-tabs-badge-pixels.json').read_text())
                return exited.exception.code, record, badge, commands, waits, proof_calls
            finally: os.chdir(old_cwd)

    def test_success_receipt_all_and_slices(self):
        for shard in ('all', 'routing', 'interaction'):
            code, record, badge, commands, waits, proof = self.run_fake(shard)
            self.assertEqual(code, 0)
            self.assertEqual(record['tests'], 'PASS')
            self.assertEqual(record['methodGate'], 'PASS')
            self.assertEqual(record['successfulMethodIDs'], sorted(expected_method_ids(shard)))
            self.assertEqual(record['selectedMethods'], expected_method_ids(shard))
            self.assertEqual((record['runId'], record['runAttempt'], record['shard']), ('123', '2', shard))
            self.assertEqual(record['repository'], 'qianshou330-cyber/pubo-ios')
            self.assertEqual(record['testExitCode'], 0)
            self.assertEqual((record['device'], record['deviceTypeIdentifier'], record['runtime']),
                             ('iPhone 17', MATRIX['small']['deviceTypeIdentifier'], RUNTIME))
            self.assertEqual(waits[0], 2700)
            self.assertEqual(record['exportedPNGs'], 8)
            if shard == 'interaction':
                self.assertEqual(proof, [])
                self.assertEqual(record['pixelGate'], 'NOT_APPLICABLE')
            else:
                self.assertEqual(proof, [dict(expected_device=record['udid'], commit=record['commit'], started=record['started'])])
            command = next(c for c in commands if c[0] == 'xcodebuild')
            self.assertEqual([c for c in command if c.startswith('-only-testing:')], selectors(shard))

    def test_fail_closed_negative_execution(self):
        for fault in ('timeout', 'nonzero', 'reader_error', 'identity', 'summary', 'wrong-device', 'screenshots', 'badge'):
            with self.subTest(fault=fault):
                code, record, *_ = self.run_fake(fault=fault)
                self.assertNotEqual(code, 0)
                self.assertEqual(record['tests'], 'FAIL')
                if fault == 'timeout': self.assertIsNone(record['testExitCode'])

    def test_interaction_still_requires_real_test_success_and_images(self):
        for fault in ('timeout', 'identity', 'screenshots'):
            code, record, *_ = self.run_fake('interaction', fault)
            self.assertNotEqual(code, 0)
            self.assertEqual(record['tests'], 'FAIL')
            self.assertEqual(record['pixelGate'], 'NOT_APPLICABLE')


if __name__ == '__main__': unittest.main()
