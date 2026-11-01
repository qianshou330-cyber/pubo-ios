"""Bounded recovery for a task-owned simulator that stalls before test execution."""
import json
import subprocess
from pathlib import Path


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
                subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], check=False, timeout=60)
    finally:
        Path(receipt).write_text(json.dumps({'device': identifier, 'attempts': attempts}, indent=2))
