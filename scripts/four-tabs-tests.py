"""Fresh task-owned iOS simulators, Debug synthetic transport only, exact result gate."""
import json
import os
import platform
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time
from simulator_boot import (
    boot,
    is_pretest_ax_handshake_failure,
    read_xcresult_summary,
    reset_simulator_for_pretest_recovery,
    resolve_xctestrun,
    warmup_services,
)
from iphone_qa_matrix import available_inventory, create_device, select_template, summary_matches_device
from four_tabs_gate import (SUITE, complete, declared_tests, validate_scope,
                            selected_methods, expected_method_ids, selectors, successful_method_ids)
from badge_pixel_gate import verify_badge_phases

root = Path('build')
root.mkdir(exist_ok=True)
size = os.environ.get('PUBO_SIM_SIZE')
if size not in ('small', 'large'):
    raise SystemExit('PUBO_SIM_SIZE must explicitly select small or large')
shard = os.environ.get('PUBO_NAV_SHARD', 'all')
validate_scope(declared_tests())
expected = len(selected_methods(shard))
template = select_template(available_inventory(), size)
device = create_device(size, template, 'PUBO four tabs ' + size)
identifier = device['udid']
record = dict(size=size, device=device['model'], deviceTypeIdentifier=device['deviceTypeIdentifier'],
              runtime=device['runtime'], udid=identifier,
              commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, timeout=15).strip(),
              hostArchitecture=platform.machine(),
              xcode=subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30).strip(),
              suite=SUITE, expectedTests=expected, tests='NOT_RUN', scope='four-tab-first-batch-only',
              schemaVersion=2, repository=os.environ.get('GITHUB_REPOSITORY', ''),
              runId=os.environ.get('GITHUB_RUN_ID', ''), runAttempt=os.environ.get('GITHUB_RUN_ATTEMPT', ''),
              shard=shard, selectedMethods=expected_method_ids(shard), successfulMethodIDs=[],
              methodGate='FAIL', testExitCode=None, exportedPNGs=0, boot='PENDING',
              realDeviceCamera='NOT_RUN', realAPNs='NOT_RUN', signedUpgrade='NOT_RUN', legacyFullUI='NOT_RUN')
receipt = root / 'four-tabs-environment.json'
bundle = root / 'four-tabs.xcresult'
shots = root / 'screenshots' / ('four-tabs-' + size)
shots.mkdir(parents=True, exist_ok=True)
started = time.time()
record['started'] = started
process = None
exit_code = 1


def diagnostic(command, timeout=90):
    try:
        return subprocess.run(command, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        print('Diagnostic unavailable: ' + str(error), flush=True)


def _drain_stream(stream, log_path):
    with Path(log_path).open('w', encoding='utf-8', errors='replace') as handle:
        for line in stream:
            sys.stdout.write(line)
            sys.stdout.flush()
            handle.write(line)


def build_command(sim_udid):
    xctestrun = resolve_xctestrun()
    if xctestrun:
        return [
            'xcodebuild', 'test-without-building', '-xctestrun', xctestrun,
            '-destination', 'platform=iOS Simulator,id=' + sim_udid, '-destination-timeout', '90',
            '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO',
            *selectors(shard),
        ]
    return ['xcodebuild', '-project', 'PUBO.xcodeproj', '-scheme', 'PUBO', '-configuration', 'Debug',
            '-destination', 'platform=iOS Simulator,id=' + sim_udid, '-destination-timeout', '90',
            '-derivedDataPath', 'build/debug', '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO',
            *selectors(shard), 'CODE_SIGNING_ALLOWED=NO', 'test-without-building']


try:
    receipt.write_text(json.dumps(record, indent=2))
    boot(identifier, root / 'four-tabs-boot.json')
    record['warmup'] = warmup_services(identifier, root / 'four-tabs-warmup.json')
    record['boot'] = 'READY'
    overall_started = time.monotonic()
    for run_attempt in range(2):
        command = build_command(identifier)
        log_path = root / f'four-tabs-attempt-{run_attempt}.log'
        remaining = 2700 if run_attempt == 0 else max(60, int(2700 - (time.monotonic() - overall_started)))
        process = subprocess.Popen(
            command, start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
        )
        tee = None
        if getattr(process, 'stdout', None) is not None:
            tee = threading.Thread(target=_drain_stream, args=(process.stdout, log_path), daemon=True)
            tee.start()
        exit_code = process.wait(timeout=remaining)
        if tee is not None:
            tee.join(timeout=15)
        if exit_code == 0 or run_attempt == 1:
            break
        summary_probe = read_xcresult_summary(bundle)
        log_text = log_path.read_text(encoding='utf-8', errors='replace') if log_path.is_file() else ''
        matched, reason = is_pretest_ax_handshake_failure(summary_probe, log_text)
        if not matched or (time.monotonic() - overall_started) >= 2100:
            break
        print(f'[PRETEST-RECOVERY] {reason}; recreating fresh simulator (1 bounded attempt)', flush=True)
        old_id = identifier
        aborted_bundle = root / 'four-tabs-aborted-code18.xcresult'
        if aborted_bundle.exists():
            shutil.rmtree(aborted_bundle)
        if bundle.exists():
            shutil.move(str(bundle), str(aborted_bundle))
        shutil.rmtree(shots, ignore_errors=True)
        shots.mkdir(parents=True, exist_ok=True)
        reset_simulator_for_pretest_recovery(old_id)
        device = create_device(size, template, 'PUBO four tabs ' + size)
        identifier = device['udid']
        started = time.time()
        record['udid'] = identifier
        record['started'] = started
        record['pretestHandshakeRecovery'] = {
            'triggered': True,
            'abortedUdid': old_id,
            'reason': reason,
            'abortedResultBundle': aborted_bundle.name if aborted_bundle.exists() else None,
        }
        receipt.write_text(json.dumps(record, indent=2))
        boot(identifier, root / 'four-tabs-boot-recovery.json')
        record['warmupRecovery'] = warmup_services(identifier, root / 'four-tabs-warmup-recovery.json')
    record['testExitCode'] = exit_code
    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)],
                            text=True, capture_output=True, check=True, timeout=90)
    (root / 'four-tabs-summary.json').write_text(result.stdout)
    summary = json.loads(result.stdout)
    tree_result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle)],
                                 text=True, capture_output=True, check=True, timeout=90)
    (root / 'four-tabs-tests.json').write_text(tree_result.stdout)
    record['successfulMethodIDs'] = successful_method_ids(json.loads(tree_result.stdout), shard)
    if not complete(summary, expected):
        raise ValueError(f'Exactly {expected} passing tests; zero failed, skipped or expected failures required')
    if not summary_matches_device(summary, size, identifier, expected):
        raise ValueError('xcresult simulator identity or per-device counts do not match the QA profile')
    record['methodGate'] = 'PASS'
    record['tests'] = 'PASS' if exit_code == 0 else 'FAIL'
except BaseException as error:
    record['tests'] = 'FAIL'
    record['error'] = type(error).__name__ + ': ' + str(error)
    print(record['error'], flush=True)
    exit_code = 1
finally:
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
    if bundle.exists():
        export = diagnostic(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(shots)], 180)
        record['exportedPNGs'] = len(list(shots.rglob('*.png')))
        if exit_code == 0 and (export is None or export.returncode != 0 or record['exportedPNGs'] < 8):
            record['tests'] = 'FAIL'
            record['gateError'] = 'Real simulator screenshot export missing or incomplete'
            exit_code = 1
    if exit_code:
        diagnostic(['xcrun', 'simctl', 'io', identifier, 'screenshot', str(shots / 'runner-failure.png')], 30)
    # Badge phases stay together in routing, with the original device/start binding.
    if shard in ('all', 'routing'):
        proof = verify_badge_phases(shots, expected_device=identifier, commit=record['commit'], started=started)
    else:
        proof = dict(status='NOT_APPLICABLE', shard=shard, commit=record['commit'],
                     expectedDevice=identifier, started=started,
                     reason='Badge method belongs exclusively to required routing shard')
    (root / 'four-tabs-badge-pixels.json').write_text(json.dumps(proof, indent=2))
    record['pixelGate'] = proof['status']
    if shard in ('all', 'routing') and proof['status'] != 'PASS':
        record['tests'] = 'FAIL'
        record['gateError'] = 'Three-phase independent rendered badge OCR missing or failed'
        exit_code = 1
    receipt.write_text(json.dumps(record, indent=2))
    diagnostic(['xcrun', 'simctl', 'shutdown', identifier], 60)
    diagnostic(['xcrun', 'simctl', 'delete', identifier], 60)
sys.exit(exit_code)
