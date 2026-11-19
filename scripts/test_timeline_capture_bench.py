import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / 'scripts/timeline-capture-bench'
spec = importlib.util.spec_from_file_location('capture_benchmark_runner', BENCH / 'run.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

class CaptureBenchContracts(unittest.TestCase):
    def test_real_core_no_copied_traversal(self):
        source = (BENCH / 'Sources/CaptureBench/main.swift').read_text()
        self.assertIn('import PUBOCore', source)
        self.assertIn('TimelinePresentation.capturedIDs(notes.filter { visibleIDs.contains($0.id) })', source)
        self.assertNotIn('func capturedIDs', source)
        self.assertIn('path: "../.."', (BENCH / 'Package.swift').read_text())

    def test_controls_and_fixed_visible_scope(self):
        source = (BENCH / 'Sources/CaptureBench/main.swift').read_text()
        for text in ['[20, 200, 2000]', '(0..<8)', 'warmupRounds = 5', 'rounds = 40',
                     'operationsPerBatch = 100', '.shuffled(using: &rng)', 'consume(operation(',
                     'noop-return-same-set', 'capturedIDs-only-8', 'fixture.expected[variant]']:
            self.assertIn(text, source)
        self.assertIn('p95Definition', source)
        self.assertIn('nearest rank across batch means', source)
        self.assertIn('smoothnessAcceptance": "NOT_EVALUATED', source)

    def test_candidate_scope_and_current_record_invariant(self):
        core = (ROOT / 'Sources/PUBOCore/TimelineState.swift').read_text()
        app = (ROOT / 'App/Features/TimelineView.swift').read_text()
        bench = (BENCH / 'Sources/CaptureBench/main.swift').read_text()
        self.assertNotIn('experimentalCapturedIDs', app)
        candidate = core.split('public func experimentalCapturedIDs', 1)[1].split('private func cleaned', 1)[0]
        self.assertIn('notes[middle].id > id', candidate)
        self.assertIn('selected.append(notes[lower])', candidate)
        self.assertIn('TimelinePresentation.capturedIDs(selected)', candidate)
        self.assertNotIn('Task', candidate)
        self.assertNotIn('Dictionary', candidate)
        self.assertIn('public private(set) var notes:', core)
        self.assertIn('current.page(records, older: false', bench)
        self.assertIn('notes = current.notes', bench)
        self.assertIn('fixture.state.experimentalCapturedIDs', bench)
        self.assertIn('preconditionFailure("Unknown arm")', bench)
        self.assertIn('"schemaVersion": 2', bench)
        tests = (ROOT / 'Tests/PUBOCoreTests/TimelineCaptureLookupTests.swift').read_text()
        self.assertIn('0xC78020261119', tests)
        self.assertIn('for step in 0..<400', tests)
        self.assertIn('for records in [state.notes, state.pending]', tests)

    def test_source_pins_current_expression(self):
        self.assertEqual(runner.source_checks(ROOT), runner.SOURCES)

    def test_source_drift_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for path in runner.SOURCES:
                p = root / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes((ROOT / path).read_bytes())
            p = root / 'App/Features/TimelineView.swift'; p.write_bytes(p.read_bytes() + b'// drift\n')
            with self.assertRaises(ValueError): runner.source_checks(root)

    def test_missing_measurements_are_not_success(self):
        report = {'status': 'MEASURED_HOST_ONLY', 'smoothnessAcceptance': 'NOT_EVALUATED', 'raw': []}
        with self.assertRaises((ValueError, KeyError)): runner.validate_report(report)

    def test_fabricated_shape_validation_and_bad_values(self):
        cases = [(n, a) for n in (20, 200, 2000)
                 for a in ('filter-plus-capturedIDs', 'capturedIDs-only-8', 'noop-return-same-set', 'experimental-binary-plus-capturedIDs')]
        order = [dict(round=r, position=i, loadedRecords=n, arm=a)
                 for r in range(-5, 40) for i, (n, a) in enumerate(cases)]
        rows = [dict(entry, visibleRecords=8, operations=100, batchNanoseconds=100, nanosecondsPerOperation=1.0)
                for entry in order if entry['round'] >= 0]
        summaries = [dict(loadedRecords=n, arm=a, samples=40, visibleRecords=8,
                          medianNanosecondsPerOperation=1.0, p95NanosecondsPerOperation=1.0) for n, a in cases]
        report = dict(schemaVersion=2, status='MEASURED_HOST_ONLY', smoothnessAcceptance='NOT_EVALUATED',
                      warmupRounds=5, rounds=40, operationsPerBatch=100,
                      clock='DispatchTime.uptimeNanoseconds', checksum=1, raw=rows,
                      orderIncludingWarmup=order, summaries=summaries)
        runner.validate_report(report) # Schema only; invented inputs are never benchmark evidence.
        report['schemaVersion'] = 1
        with self.assertRaises(ValueError): runner.validate_report(report)
        report['schemaVersion'] = 2
        report['raw'] = [row for row in rows if row['arm'] != 'experimental-binary-plus-capturedIDs']
        with self.assertRaises(ValueError): runner.validate_report(report)
        report['raw'] = rows
        summaries[-1]['arm'] = 'noop-return-same-set'
        with self.assertRaises(ValueError): runner.validate_report(report)
        summaries[-1]['arm'] = 'experimental-binary-plus-capturedIDs'
        for bad in (float('nan'), float('inf'), 0, -1, 2):
            rows[0]['nanosecondsPerOperation'] = bad
            with self.assertRaises(ValueError): runner.validate_report(report)
        rows[0]['nanosecondsPerOperation'] = 1.0
        rows[0]['position'] = 1
        with self.assertRaises(ValueError): runner.validate_report(report)
        rows[0]['position'] = 0
        summaries[0]['p95NanosecondsPerOperation'] = 2.0
        with self.assertRaises(ValueError): runner.validate_report(report)
        summaries[0]['p95NanosecondsPerOperation'] = 1.0
        order.pop(0)
        with self.assertRaises(ValueError): runner.validate_report(report)
