"""Strict passive same-process background/resume/new-application evidence."""
import json
import re

PREFIX = 'PUBO_REFRESH_DIAG '
REQUIRED = {'captureStarted', 'sceneBackground', 'sceneActive', 'rowsApplied', 'fixtureGeneration'}
TOKEN = re.compile(r'([A-Za-z][A-Za-z0-9_]*)=([0-9]+)', re.ASCII)


def _counts(message):
    counts = {}
    for token in message[len(PREFIX):].split(';'):
        match = TOKEN.fullmatch(token)
        if match is None or match[1] in counts:
            return None
        try:
            counts[match[1]] = int(match[2])
        except ValueError:
            return None
    return counts if REQUIRED <= counts.keys() and counts['captureStarted'] == 1 else None


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
        pid, message = event.get('processID'), event.get('eventMessage')
        if type(pid) is not int or pid <= 0:
            continue
        if not isinstance(message, str) or not message.startswith(PREFIX):
            continue
        counts = _counts(message)
        state = processes.get(pid)
        if counts is None:
            processes.pop(pid, None)
            continue
        if state:
            previous = state['previous']
            # A reset/PID reuse, missing counter or out-of-order snapshot cannot
            # bridge lifecycle phases. Discard it; later evidence starts afresh.
            if counts.keys() != previous.keys() or any(counts[k] < previous[k] for k in counts):
                processes.pop(pid, None)
                continue
        else:
            previous = None
            state = processes[pid] = {'previous': counts, 'backgroundActive': None, 'resume': None}
        state['previous'] = counts
        new_background = counts['sceneBackground'] > (previous['sceneBackground'] if previous else 0)
        if new_background:
            state['backgroundActive'] = counts['sceneActive']
            state['resume'] = None
            continue
        if state['backgroundActive'] is None:
            continue
        if state['resume'] is None:
            if counts['sceneActive'] > state['backgroundActive']:
                # This snapshot is only a resume baseline, never an application.
                state['resume'] = counts.copy()
            continue
        baseline = state['resume']
        if (counts['rowsApplied'] >= 3 and counts['fixtureGeneration'] >= 3
                and counts['rowsApplied'] > baseline['rowsApplied']
                and counts['fixtureGeneration'] > baseline['fixtureGeneration']):
            return True
    return False
