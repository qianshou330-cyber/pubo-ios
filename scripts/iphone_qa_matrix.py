"""Exact simulator profiles; never substitute a different model or runtime."""
import json
from pathlib import Path
import re
import subprocess

MATRIX = json.loads(Path(__file__).with_name('iphone-qa-matrix.json').read_text())
RUNTIME = MATRIX['runtime']
SIZES = ('small', 'large')


def select_template(inventory, size):
    profile = MATRIX[size]
    matches = [d for d in inventory.get(RUNTIME, ()) if d.get('name') == profile['model']
               and d.get('deviceTypeIdentifier') == profile['deviceTypeIdentifier']
               and d.get('isAvailable') is True and isinstance(d.get('udid'), str)]
    if not matches:
        raise ValueError(f"No available {profile['model']} simulator template on {RUNTIME}; no fallback")
    return dict(min(matches, key=lambda d: d['udid']), runtime=RUNTIME)


def available_inventory():
    return json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], timeout=30))['devices']


def create_device(size, template, name):
    model = MATRIX[size]['model']
    kind = MATRIX[size]['deviceTypeIdentifier']
    if template.get('name') != model or template.get('deviceTypeIdentifier') != kind or template.get('runtime') != RUNTIME:
        raise ValueError('Template does not match QA matrix')
    identifier = subprocess.check_output(
        ['xcrun', 'simctl', 'create', name, kind, RUNTIME], text=True, timeout=60).strip()
    if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', identifier):
        raise ValueError('simctl did not return a fresh device UUID')
    try:
        matches = [(runtime, d) for runtime, rows in available_inventory().items()
                   for d in rows if d.get('udid') == identifier]
        if (len(matches) != 1 or matches[0][0] != RUNTIME or
                matches[0][1].get('deviceTypeIdentifier') != kind or
                matches[0][1].get('isAvailable') is not True or matches[0][1].get('name') != name):
            raise ValueError(f'Created simulator identity does not match {model} on {RUNTIME}')
        return dict(matches[0][1], runtime=RUNTIME, model=model)
    except BaseException:
        try:
            subprocess.run(['xcrun', 'simctl', 'delete', identifier], check=False, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            pass
        raise


def summary_matches_device(summary, size, udid, expected):
    configs = summary.get('devicesAndConfigurations')
    if not isinstance(configs, list) or len(configs) != 1 or not isinstance(configs[0], dict):
        return False
    result = configs[0]
    device = result.get('device')
    if not isinstance(device, dict):
        return False
    wanted = {'deviceId': udid, 'modelName': MATRIX[size]['model'], 'osVersion': MATRIX['osVersion'],
              'platform': 'iOS Simulator'}
    counts = {'passedTests': expected, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
    return (all(device.get(key) == value for key, value in wanted.items()) and
            all(type(result.get(key)) is int and result[key] == value for key, value in counts.items()))
