"""Bounded recovery for a task-owned simulator that stalls before test execution."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def boot(identifier, receipt):
    attempts = []
    try:
        for attempt in range(2):
            try:
                subprocess.run(['xcrun', 'simctl', 'boot', identifier], check=True, timeout=60)
                subprocess.run(['xcrun', 'simctl', 'bootstatus', identifier, '-b'], check=True, timeout=300)
                attempts.append({'attempt': attempt + 1, 'status': 'READY'})
                return
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
                attempts.append({'attempt': attempt + 1, 'status': 'FAIL', 'error': type(error).__name__})
                if attempt == 1:
                    raise
                print('Simulator startup stalled; one task-owned restart before any tests.', flush=True)
                try:
                    shutdown = subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], check=False, timeout=60)
                    attempts[-1]['shutdown'] = {'status': 'COMPLETED', 'returncode': shutdown.returncode}
                except subprocess.TimeoutExpired:
                    # A stalled shutdown must not bypass the existing bounded recovery.
                    # Preserve the failure, then use the same CI-only service reset.
                    attempts[-1]['shutdown'] = {'status': 'TIMEOUT', 'timeoutSeconds': 60}
                    print('Task-owned simulator shutdown timed out; continuing bounded recovery.', flush=True)
                # GitHub provides an isolated, disposable VM. A stalled simulator
                # service can outlive the device; reset it only on that CI host.
                # Never reset the user's local Simulator service.
                if os.environ.get('GITHUB_ACTIONS') == 'true':
                    subprocess.run(['killall', '-TERM', 'com.apple.CoreSimulator.CoreSimulatorService'], check=False, timeout=30)
    finally:
        Path(receipt).write_text(json.dumps({'device': identifier, 'attempts': attempts}, indent=2))


def warmup_services(identifier, receipt=None, timeout=30):
    """Verify SpringBoard and WindowServer respond before launching xcodebuild."""
    started = time.monotonic()
    sb_deadline = started + min(15.0, max(1.0, timeout / 2.0))
    overall_deadline = started + max(1.0, float(timeout))
    springboard_ready = False
    screenshot_ready = False
    sb_attempts = 0
    shot_attempts = 0
    try:
        while True:
            sb_attempts += 1
            remaining = max(1.0, sb_deadline - time.monotonic())
            try:
                proc = subprocess.run(
                    ['xcrun', 'simctl', 'spawn', identifier, 'launchctl', 'print', 'system/com.apple.SpringBoard'],
                    capture_output=True, text=True, check=False, timeout=min(10.0, remaining),
                )
                if proc.returncode == 0:
                    springboard_ready = True
                    break
            except (subprocess.TimeoutExpired, OSError):
                pass
            if time.monotonic() >= sb_deadline:
                break
            time.sleep(1.0)

        with tempfile.TemporaryDirectory() as tmp:
            probe_png = Path(tmp) / 'warmup-probe.png'
            while True:
                shot_attempts += 1
                remaining = max(1.0, overall_deadline - time.monotonic())
                try:
                    proc = subprocess.run(
                        ['xcrun', 'simctl', 'io', identifier, 'screenshot', str(probe_png)],
                        capture_output=True, text=True, check=False, timeout=min(15.0, remaining),
                    )
                    if proc.returncode == 0:
                        screenshot_ready = True
                        break
                except (subprocess.TimeoutExpired, OSError):
                    pass
                if time.monotonic() >= overall_deadline:
                    break
                time.sleep(1.0)
    finally:
        report = {
            'device': identifier,
            'status': 'READY' if (springboard_ready and screenshot_ready) else 'PARTIAL',
            'springBoardReady': springboard_ready,
            'screenshotReady': screenshot_ready,
            'springBoardAttempts': sb_attempts,
            'screenshotAttempts': shot_attempts,
            'elapsedSeconds': round(time.monotonic() - started, 3),
        }
        if receipt is not None:
            Path(receipt).write_text(json.dumps(report, indent=2))
    return report


def _is_zero_int(value):
    return type(value) is int and value == 0


def is_pretest_ax_handshake_failure(summary_data, log_text):
    """Return (True, reason) ONLY when 0 tests ran and runner hit AX Code=18 handshake failure."""
    if isinstance(summary_data, dict):
        for key in ('passedTests', 'failedTests', 'skippedTests', 'expectedFailures'):
            if key in summary_data and not _is_zero_int(summary_data[key]):
                return False, f'executed-tests:{key}={summary_data[key]!r}'
        if 'totalTestCount' in summary_data and not _is_zero_int(summary_data['totalTestCount']):
            return False, f"executed-tests:totalTestCount={summary_data['totalTestCount']!r}"
        configs = summary_data.get('devicesAndConfigurations')
        if isinstance(configs, list):
            for entry in configs:
                if not isinstance(entry, dict):
                    continue
                for key in ('passedTests', 'failedTests', 'skippedTests', 'expectedFailures'):
                    if key in entry and not _is_zero_int(entry[key]):
                        return False, f'device-executed-tests:{key}={entry[key]!r}'
    elif summary_data is not None:
        return False, 'malformed-summary'

    parts = [log_text or '']
    if isinstance(summary_data, dict):
        for item in summary_data.get('testFailures') or ():
            if isinstance(item, dict):
                parts.append(str(item.get('failureText') or ''))
                parts.append(str(item.get('message') or ''))
    combined = '\n'.join(parts)
    if 'Timed out waiting for AX loaded notification' in combined:
        return True, 'XCTDaemonErrorDomain Code=18: Timed out waiting for AX loaded notification (0 tests executed)'
    if 'XCTDaemonErrorDomain' in combined and 'Code=18' in combined:
        return True, 'XCTDaemonErrorDomain Code=18 pre-test handshake failure (0 tests executed)'
    return False, 'not-pretest-ax-handshake'


def read_xcresult_summary(bundle_path):
    path = Path(bundle_path)
    if not path.exists():
        return None
    try:
        result = subprocess.run(
            ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(path)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, OSError, ValueError):
        pass
    return None


def reset_simulator_for_pretest_recovery(identifier):
    """Tear down a broken pre-test simulator and reset CoreSimulatorService on CI only."""
    for cmd, limit in (
        (['xcrun', 'simctl', 'shutdown', identifier], 60),
        (['xcrun', 'simctl', 'delete', identifier], 60),
    ):
        try:
            subprocess.run(cmd, check=False, timeout=limit)
        except (subprocess.TimeoutExpired, OSError):
            pass
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        try:
            subprocess.run(['killall', '-TERM', 'com.apple.CoreSimulator.CoreSimulatorService'], check=False, timeout=30)
        except (subprocess.TimeoutExpired, OSError):
            pass


def resolve_xctestrun(env_path=None):
    """Return a validated regular .xctestrun file path when PUBO_XCTESTRUN is configured."""
    raw = (os.environ.get('PUBO_XCTESTRUN', '') if env_path is None else str(env_path)).strip()
    if not raw:
        return None
    path = Path(raw)
    if not path.is_file() or path.is_symlink() or path.suffix != '.xctestrun':
        raise ValueError(f'PUBO_XCTESTRUN must reference an existing regular .xctestrun file: {raw}')
    return str(path)
