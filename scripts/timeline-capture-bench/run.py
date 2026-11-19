"""Explicit local host run; no CI, installs, remote actions, or pass thresholds."""
import hashlib
import json
import math
import statistics
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

BASE = 'c1850dd33db9271977607f4ef0242ccda1bdc076'
SOURCES = {
    'Package.swift': 'bf7a9c5937c5e3b57bc1729aa53d86b13ed5cf22',
    'Sources/PUBOCore/JSONValue.swift': '3db70244d9f404407066d01333163870f2489559',
    'App/Features/TimelineView.swift': '3472342fb7da16f1b845e3a14809750d017a92ca',
    'Sources/PUBOCore/TimelineState.swift': '35897552813bb69d84bc0afed42f7b4e91c60d58',
}

def source_checks(root):
    for path, expected in SOURCES.items():
        data = (root / path).read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if actual != expected:
            raise ValueError('Source drift: ' + path + '; review and repin before measuring')
    app = (root / 'App/Features/TimelineView.swift').read_text()
    if 'TimelinePresentation.capturedIDs(feed.notes.filter { visibleIDs.contains($0.id) })' not in app:
        raise ValueError('Active capture expression changed')
    return dict(SOURCES)

def validate_report(report):
    if (report['schemaVersion'], report['status'], report['smoothnessAcceptance'],
        report['warmupRounds'], report['rounds'], report['operationsPerBatch']) != (
            2, 'MEASURED_HOST_ONLY', 'NOT_EVALUATED', 5, 40, 100):
        raise ValueError('Invalid scope')
    rows = report['raw']
    order = report['orderIncludingWarmup']
    summaries = report['summaries']
    if len(rows) != 40 * 12 or len(order) != 45 * 12 or len(summaries) != 12:
        raise ValueError('Missing samples, schedule entries, or summaries')
    if report['clock'] != 'DispatchTime.uptimeNanoseconds' or not report['checksum'] > 0:
        raise ValueError('Missing monotonic time or observable work')
    arms = ('filter-plus-capturedIDs', 'capturedIDs-only-8', 'noop-return-same-set', 'experimental-binary-plus-capturedIDs')
    expected = {(n, arm) for n in (20, 200, 2000) for arm in arms}
    def case(r):
        return r['loadedRecords'], r['arm']
    def slot(r):
        return r['round'], r['position']
    slots = {}
    for round_id in range(-5, 40):
        group = [entry for entry in order if entry['round'] == round_id]
        if len(group) != 12 or {r['position'] for r in group} != set(range(12)) or {case(r) for r in group} != expected:
            raise ValueError('Incomplete or duplicate schedule')
        slots.update({slot(r): case(r) for r in group})
    sample_slots = set()
    samples = {key: [] for key in expected}
    for row in rows:
        pos = slot(row)
        key = case(row)
        elapsed = row['batchNanoseconds']
        value = row['nanosecondsPerOperation']
        if (pos in sample_slots or pos[0] < 0 or slots.get(pos) != key
                or type(elapsed) is not int or elapsed <= 0
                or not math.isfinite(value) or not math.isclose(value, elapsed / 100, rel_tol=1e-12)
                or row['visibleRecords'] != 8 or row['operations'] != 100):
            raise ValueError('Invalid, duplicate or out-of-order measurement')
        sample_slots.add(pos)
        samples[key].append(value)
    if {case(r) for r in summaries} != expected:
        raise ValueError('Incorrect summary coverage')
    for row in summaries:
        values = sorted(samples[case(row)])
        if (len(values) != 40 or row['samples'] != 40 or row['visibleRecords'] != 8
                or not math.isclose(row['medianNanosecondsPerOperation'], statistics.median(values), rel_tol=1e-12)
                or not math.isclose(row['p95NanosecondsPerOperation'], values[37], rel_tol=1e-12)):
            raise ValueError('Summary disagrees with raw batches')
    return report

def main():
    directory = Path(__file__).resolve().parent
    root = directory.parents[1]
    fingerprints = source_checks(root)
    swift = shutil.which('swift')
    if swift is None:
        raise SystemExit('UNAVAILABLE: Swift is not installed; no measurements produced')
    reports = root / 'build/timeline-capture-bench'
    reports.mkdir(parents=True, exist_ok=True)
    # A failed later attempt cannot be mistaken for an older successful report.
    output = Path(tempfile.mkdtemp(prefix='attempt-', dir=reports))
    version = subprocess.check_output([swift, '--version'], text=True)
    completed = subprocess.run([swift, 'run', '--package-path', str(directory),
        '--scratch-path', str(output / 'swift-build'), '-c', 'release', 'CaptureBench'],
        capture_output=True, text=True, timeout=900)
    (output / 'stdout.txt').write_text(completed.stdout)
    (output / 'stderr.txt').write_text(completed.stderr)
    completed.check_returncode()
    report = validate_report(json.loads(completed.stdout))
    report['build'] = dict(baseSourceCommit=BASE, sourceGitBlobs=fingerprints, swiftVersion=version,
                          architecture=platform.machine(), optimization='release', experiment='C79_ROW_CALLBACK_INTEGRATION_BENCHMARK_STILL_C78_FOUR_ARMS')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(output / 'report.json')

if __name__ == '__main__': main()
