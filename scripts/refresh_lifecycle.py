"""Validate passive fixture-only app lifecycle evidence, not XCTest's cached state."""
import json
import re


def complete_lifecycle(raw):
    try:
        events = json.loads(raw)
    except (ValueError, TypeError):
        return False
    if not isinstance(events, list):
        return False
    processes = {}
    for event in events:
        if not isinstance(event, dict):
            continue
        pid = event.get('processID')
        message = event.get('eventMessage', '')
        if pid is None or not isinstance(message, str) or not message.startswith('PUBO_REFRESH_DIAG '):
            continue
        counts = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', message)}
        if counts.get('captureStarted') != 1:
            continue
        state = processes.setdefault(pid, {})
        if counts.get('sceneBackground', 0) >= 1 and 'backgroundActive' not in state:
            state['backgroundActive'] = counts.get('sceneActive', 0)
        if 'backgroundActive' in state and counts.get('sceneActive', 0) > state['backgroundActive']:
            state['resumed'] = True
        if state.get('resumed') and counts.get('rowsApplied', 0) >= 3 and counts.get('fixtureGeneration', 0) >= 3:
            return True
    return False
