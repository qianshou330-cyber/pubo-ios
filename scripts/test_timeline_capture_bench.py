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
                 for a in ('filter-plus-capturedIDs', 'capturedIDs-only-8', 'noop-return-same-set')]
        order = [dict(round=r, position=i, loadedRecords=n, arm=a)
                 for r in range(-5, 40) for i, (n, a) in enumerate(cases)]
        rows = [dict(entry, visibleRecords=8, operations=100, batchNanoseconds=100, nanosecondsPerOperation=1.0)
                for entry in order if entry['round'] >= 0]
        summaries = [dict(loadedRecords=n, arm=a, samples=40, visibleRecords=8,
                          medianNanosecondsPerOperation=1.0, p95NanosecondsPerOperation=1.0) for n, a in cases]
        report = dict(schemaVersion=1, status='MEASURED_HOST_ONLY', smoothnessAcceptance='NOT_EVALUATED',
                      warmupRounds=5, rounds=40, operationsPerBatch=100,
                      clock='DispatchTime.uptimeNanoseconds', checksum=1, raw=rows,
                      orderIncludingWarmup=order, summaries=summaries)
        runner.validate_report(report) # Schema only; invented inputs are never benchmark evidence.
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
